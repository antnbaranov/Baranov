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

@MainActor
@Observable
final class NearbyCourierService: NSObject {
    private(set) var couriers: [NearbyCourier] = []
    private(set) var isRunning = false

    @ObservationIgnored nonisolated static let serviceType = "baranov-courier"
    @ObservationIgnored private let peerID = MCPeerID(displayName: "courier-" + String(UUID().uuidString.prefix(6)))
    @ObservationIgnored private var browser: MCNearbyServiceBrowser?
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?
    @ObservationIgnored private var found: [String: NearbyCourier] = [:]

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
        couriers = []
        isRunning = false
    }

    fileprivate func add(_ courier: NearbyCourier) {
        found[courier.id] = courier
        publish()
    }

    fileprivate func remove(id: String) {
        found[id] = nil
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
        Task { @MainActor in self.add(courier) }
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
    /// Only ever advertising — refuse every session invitation.
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(false, nil)
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {}
}
