//
//  NearbyCourierService.swift
//  Baranov
//
//  Couriers standing near you — no typing, no lists to maintain.
//
//  Two halves over MultipeerConnectivity (Bluetooth + peer-to-peer Wi-Fi):
//
//  - Browsing: while Profile is open, finds phones nearby that are open to
//    carrying letters and reads their first name and trip destination from
//    the Bonjour `discoveryInfo`. No session is ever opened.
//  - Advertising: only while Profile is open AND "Open to carry" is on
//    (off by default). It shares a display name and one trip city, nothing
//    else — never a position.
//
//  Multipeer gives proximity, not coordinates, so the UI places couriers
//  "in range" rather than at a surveyed spot.
//
//  Foreground only. Info.plist needs `_baranov-courier._tcp` / `._udp`
//  under `NSBonjourServices` (plus the existing local-network string).
//  Any failure (Local Network denied, say) just leaves the list empty.
//

import CoreLocation
import Foundation
import MultipeerConnectivity
import Observation

struct NearbyCourier: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let tripCity: String
    /// Where the trip ends, rounded to ~10 km by the sender. Never a
    /// position of the person.
    let tripLatitude: Double?
    let tripLongitude: Double?

    /// Heading the same way as this ram's true final destination: same city,
    /// or within the directory's match radius (800 km).
    /// A stable spot near `center`, derived deterministically from this
    /// courier's own id — Multipeer gives proximity, not coordinates, so
    /// every screen that shows nearby couriers on a map places them the
    /// same way: scattered a little inside "in range," not stacked on top
    /// of the user's own dot.
    func placed(around center: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let seed = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 100_000 }
        let angle = Double(seed % 360) * .pi / 180
        let distance = 35.0 + Double(seed % 45)
        let dLat = distance * cos(angle) / 111_000
        let dLon = distance * sin(angle) / (111_000 * max(cos(center.latitude * .pi / 180), 0.2))
        return CLLocationCoordinate2D(latitude: center.latitude + dLat, longitude: center.longitude + dLon)
    }

    func isGoingSameWay(as ram: Ram) -> Bool {
        let target = ram.targetCity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !target.isEmpty, tripCity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == target {
            return true
        }
        guard let tripLatitude, let tripLongitude else { return false }
        let trip = CLLocation(latitude: tripLatitude, longitude: tripLongitude)
        let goal = CLLocation(latitude: ram.finalDestinationCoordinate.latitude,
                              longitude: ram.finalDestinationCoordinate.longitude)
        return trip.distance(from: goal) <= KnownCarrierDirectory.matchRadiusMeters
    }
}

/// "Anton wants to hand you Klaus": the ask that reaches a courier's phone
/// when someone taps them and chooses Hand over. It travels as the context of
/// a Multipeer invitation that is always declined — no session is opened for
/// it. The token then pairs the two phones' hoofbeat relays, instead of a
/// shake.
struct HandoverRequest: Codable, Identifiable, Hashable, Sendable {
    let token: String
    let fromName: String
    let ramName: String?
    /// Where the letter is ultimately going, so the courier can decide by
    /// direction, not just by who's asking. Optional: older builds omit it.
    var destinationCity: String? = nil
    var destinationLatitude: Double? = nil
    var destinationLongitude: Double? = nil
    /// Handed over at the gate to the person the letter is for.
    var isDelivery: Bool? = nil
    var id: String { token }
}

/// A moment worth pointing out while a courier is in range: someone whose
/// trip matches one of your letters, or the very person a letter is for.
struct CourierSuggestion: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// Their trip goes where the letter is going.
        case goingYourWay
        /// They are the letter's recipient and it has reached their town.
        case deliver
    }
    let kind: Kind
    let courier: NearbyCourier
    let ramID: UUID
    let ramName: String
    let place: String
    var id: String { "\(courier.id)|\(ramID)" }
}

/// Carries a non-`Sendable` peer id from a delegate callback to the main
/// actor, where it is only ever used.
private struct PeerBox: @unchecked Sendable {
    let value: MCPeerID
}

@MainActor
@Observable
final class NearbyCourierService: NSObject {
    /// A handover someone nearby asked us to accept. Cleared on answer or
    /// after `requestLifetime`.
    private(set) var incomingRequest: HandoverRequest?
    /// A courier nearby worth handing a letter to right now.
    private(set) var suggestion: CourierSuggestion?

    /// Shows a suggestion unless the same one was shown in the last day —
    /// a courier who lingers in range must not be announced every minute.
    func suggest(_ suggestion: CourierSuggestion) {
        guard self.suggestion == nil, incomingRequest == nil else { return }
        var shown = UserDefaults.standard.dictionary(forKey: Self.shownSuggestionsKey) as? [String: Date] ?? [:]
        let now = Date()
        shown = shown.filter { now.timeIntervalSince($0.value) < 86_400 }
        guard shown[suggestion.id] == nil else { return }
        shown[suggestion.id] = now
        UserDefaults.standard.set(shown, forKey: Self.shownSuggestionsKey)
        self.suggestion = suggestion
    }

    func dismissSuggestion() {
        suggestion = nil
    }

    private static let shownSuggestionsKey = "com.baranov.shownCourierSuggestions"

    /// How long an unanswered request stays on screen. The sender's relay
    /// waits a little longer than this.
    static let requestLifetime: TimeInterval = 40

    private(set) var couriers: [NearbyCourier] = []
    private(set) var isRunning = false

    @ObservationIgnored nonisolated static let serviceType = "baranov-courier"
    @ObservationIgnored private let peerID = MCPeerID(displayName: "courier-" + String(UUID().uuidString.prefix(6)))
    @ObservationIgnored private var browser: MCNearbyServiceBrowser?
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?
    @ObservationIgnored private var found: [String: NearbyCourier] = [:]
    @ObservationIgnored private var peers: [String: MCPeerID] = [:]
    /// Only exists to address invitations; never connects.
    @ObservationIgnored private var requestSession: MCSession?
    @ObservationIgnored private var requestExpiry: Task<Void, Never>?

    /// Start looking. Pass `announce` to also be seen by others.
    func start(announce: (name: String, tripCity: String, trip: RamCoordinate?)?) {
        stop()
        let b = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        b.delegate = self
        b.startBrowsingForPeers()
        browser = b

        if let announce {
            var info = ["n": String(announce.name.prefix(24)), "c": String(announce.tripCity.prefix(40))]
            if let trip = announce.trip {
                info["la"] = String(format: "%.1f", trip.latitude)
                info["lo"] = String(format: "%.1f", trip.longitude)
            }
            let a = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: info, serviceType: Self.serviceType)
            a.delegate = self
            a.startAdvertisingPeer()
            advertiser = a
        }
        isRunning = true
    }

    func stop() {
        browser?.stopBrowsingForPeers()
        browser = nil
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        found = [:]
        peers = [:]
        couriers = []
        isRunning = false
    }

    /// Asks the courier with `courierID` to accept a handover. Returns
    /// `false` if they are no longer in range.
    @discardableResult
    func requestHandover(to courierID: String, request: HandoverRequest) -> Bool {
        guard let browser, let peer = peers[courierID],
              let context = try? JSONEncoder().encode(request) else { return false }
        let session = requestSession ?? MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .none)
        requestSession = session
        browser.invitePeer(peer, to: session, withContext: context, timeout: 5)
        return true
    }

    /// Clears the incoming request, whatever the answer was.
    func dismissIncomingRequest() {
        requestExpiry?.cancel()
        requestExpiry = nil
        incomingRequest = nil
    }

    fileprivate func receive(_ request: HandoverRequest) {
        incomingRequest = request
        requestExpiry?.cancel()
        requestExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(NearbyCourierService.requestLifetime))
            guard !Task.isCancelled, self?.incomingRequest?.token == request.token else { return }
            self?.incomingRequest = nil
        }
    }

    fileprivate func remember(_ peer: MCPeerID) {
        peers[peer.displayName] = peer
    }

    fileprivate func add(_ courier: NearbyCourier) {
        found[courier.id] = courier
        publish()
    }

    fileprivate func remove(id: String) {
        found[id] = nil
        peers[id] = nil
        publish()
    }

    private func publish() {
        couriers = found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

extension NearbyCourierService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        guard let name = info?["n"], !name.isEmpty else { return }
        let courier = NearbyCourier(
            id: peerID.displayName,
            name: name,
            tripCity: info?["c"] ?? "",
            tripLatitude: info?["la"].flatMap(Double.init),
            tripLongitude: info?["lo"].flatMap(Double.init)
        )
        let boxed = PeerBox(value: peerID)
        Task { @MainActor in
            self.remember(boxed.value)
            self.add(courier)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let id = peerID.displayName
        Task { @MainActor in self.remove(id: id) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in self.stop() }
    }
}

extension NearbyCourierService: MCNearbyServiceAdvertiserDelegate {
    /// Never opens a session. An invitation carrying a `HandoverRequest` is
    /// someone asking to hand us a ram: surface it, then decline the
    /// invitation itself — the actual transfer runs over the hoofbeat relay.
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(false, nil)
        guard let context, let request = try? JSONDecoder().decode(HandoverRequest.self, from: context) else { return }
        Task { @MainActor in self.receive(request) }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {}
}
