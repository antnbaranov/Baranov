//
//  HoofbeatRelay.swift
//  Baranov
//
//  "Shake and the ram jumps to whoever shook theirs too."
//
//  A foreground, zero-UI peer-to-peer handoff built on MultipeerConnectivity
//  (Bluetooth + peer-to-peer Wi-Fi, no internet required). This is NOT
//  AirDrop: there is no system share sheet, no picker, no Accept dialog.
//  The pairing proof is the shake itself — two devices that registered a
//  shake within `matchWindow` of each other are, by construction, two
//  people standing together who both meant to do this. That consent is
//  what lets both sides auto-accept.
//
//  Wire protocol, deliberately minimal:
//    1. Both sides advertise AND browse on `serviceType`, publishing their
//       shake instant in `discoveryInfo["s"]`.
//    2. A browser that finds a peer whose shake is inside the window
//       invites it — but only the lexicographically lower `displayName`
//       invites, so the two devices can't race into two half-open sessions.
//    3. The other side accepts any invitation while it is still armed.
//    4. On connect, each side sends its own JSON-encoded `RamTransitPackage`
//       (if it has one to give) and imports whatever arrives.
//    5. After a short settle window the session is torn down.
//
//  Both sides can hand off simultaneously — the exchange is symmetric, so
//  two carriers can genuinely trade rams in one shake.
//
//  Requires in Info.plist: `NSLocalNetworkUsageDescription` and
//  `NSBonjourServices` entries for `_baranov-gate._tcp` / `._udp`. Without
//  them iOS silently finds nobody.
//
//  Foreground only — MultipeerConnectivity does not browse in the
//  background, which is fine: shaking the phone implies looking at it.
//

import Foundation
import MultipeerConnectivity
import Observation

/// Where a hoofbeat exchange currently stands. Drives the on-screen HUD.
enum HoofbeatPhase: Equatable, Sendable {
    case idle
    case searching
    case connecting(peerName: String)
    case exchanging(peerName: String)
    case finished(summary: String)
    case failed(reason: String)

    var isActive: Bool {
        if case .idle = self { return false }
        return true
    }
}

/// Ferries a non-`Sendable` MultipeerConnectivity object from a delegate
/// callback (arbitrary queue) onto the main actor. Safe here because each
/// boxed value is used on exactly one actor after the hop, and the
/// framework does not mutate it concurrently behind our back.
private struct UnsafeTransfer<T>: @unchecked Sendable {
    let value: T
}

@Observable
@MainActor
final class HoofbeatRelay: NSObject {
    /// 1–15 chars, lowercase letters/digits/hyphens — a MultipeerConnectivity
    /// rule, not a style choice.
    static let serviceType = "baranov-gate"

    /// How far apart two shakes may be and still count as "together".
    /// Wide enough to absorb device clock drift and human reaction time,
    /// narrow enough that a stranger idling nearby is never swept in.
    static let matchWindow: TimeInterval = 3.5

    /// How long we keep looking before giving up on finding a partner.
    static let searchTimeout: TimeInterval = 8

    /// Grace period after connecting, so a package arriving from the other
    /// side still lands before the session is torn down.
    static let settleDelay: TimeInterval = 1.0

    private(set) var phase: HoofbeatPhase = .idle
    /// Bumped on every successful exchange; views key `.sensoryFeedback` to it.
    private(set) var successTick = 0

    /// Invoked on the main actor with each package received from a peer.
    /// Returns the name to show in the HUD, or `nil` if it was refused
    /// (a full pasture, a package that doesn't decode).
    var onReceive: ((RamTransitPackage) async -> String?)?

    /// Invoked on the main actor once a ram has actually gone out over the
    /// wire, with its id and the name of the carrier who took it. This is
    /// what lets the flock mark the ram `.handedOff` — a handoff that left
    /// the ram walking here too would advance the same letter on two
    /// phones at once.
    var onHandedOff: ((UUID, String) -> Void)?

    private let localPeerID: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private var myShakeAt: Date = .distantPast
    private var outgoingPayload: Data?
    private var outgoingRamName: String?
    private var outgoingRamId: UUID?
    private var invitedPeers: Set<String> = []
    private var didSend = false
    private var receivedRamName: String?
    private var timeoutTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?

    /// - Parameters:
    ///   - carrierName: the person's own name, shown to the other side.
    ///   - installID: makes the peer name unique even when two people share
    ///     a first name, and gives the invite tie-break a stable ordering.
    init(carrierName: String, installID: UUID) {
        let trimmed = carrierName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Shepherd" : String(trimmed.prefix(32))
        let suffix = String(installID.uuidString.prefix(4))
        localPeerID = MCPeerID(displayName: "\(base)#\(suffix)")
        super.init()
    }

    /// The human half of a peer name — "Anton#4F1C" reads as "Anton".
    nonisolated static func friendlyName(_ displayName: String) -> String {
        String(displayName.split(separator: "#").first ?? "Shepherd")
    }

    // MARK: - Lifecycle

    /// Arms the relay for one exchange.
    /// - Parameters:
    ///   - shakenAt: the instant the local shake was registered.
    ///   - package: the ram to offer, or `nil` to only receive.
    func begin(shakenAt: Date, offering package: RamTransitPackage?) {
        guard !phase.isActive else { return }

        myShakeAt = shakenAt
        outgoingPayload = package.flatMap { try? JSONEncoder().encode($0) }
        outgoingRamName = package?.ram.name
        outgoingRamId = package?.ram.id
        invitedPeers = []
        didSend = false
        receivedRamName = nil

        let session = MCSession(
            peer: localPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        session.delegate = self
        self.session = session

        let advertiser = MCNearbyServiceAdvertiser(
            peer: localPeerID,
            discoveryInfo: ["s": String(shakenAt.timeIntervalSince1970)],
            serviceType: Self.serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser

        phase = .searching

        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(HoofbeatRelay.searchTimeout))
            guard !Task.isCancelled else { return }
            await self?.timeOut()
        }
    }

    /// Ends the exchange and clears the HUD back to idle.
    func reset() {
        timeoutTask?.cancel()
        timeoutTask = nil
        settleTask?.cancel()
        settleTask = nil
        teardownTransport()
        phase = .idle
    }

    private func teardownTransport() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil

        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil

        session?.disconnect()
        session?.delegate = nil
        session = nil

        outgoingPayload = nil
        outgoingRamName = nil
        outgoingRamId = nil
        invitedPeers = []
    }

    private func timeOut() {
        guard case .searching = phase else { return }
        teardownTransport()
        phase = .failed(reason: "No one shook back nearby.")
        autoDismiss(after: 2.5)
    }

    private func autoDismiss(after seconds: TimeInterval) {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.reset()
        }
    }

    // MARK: - Pairing

    private func consider(peerID: MCPeerID, info: [String: String]?) {
        guard phase.isActive, let session, let browser else { return }
        guard peerID.displayName != localPeerID.displayName else { return }
        guard !invitedPeers.contains(peerID.displayName) else { return }

        guard let stamp = info?["s"], let seconds = TimeInterval(stamp) else { return }
        let theirShake = Date(timeIntervalSince1970: seconds)
        guard abs(theirShake.timeIntervalSince(myShakeAt)) <= Self.matchWindow else { return }

        // Deterministic tie-break: exactly one of the two devices invites,
        // so they don't collide into two half-open sessions.
        guard localPeerID.displayName < peerID.displayName else { return }

        invitedPeers.insert(peerID.displayName)
        phase = .connecting(peerName: Self.friendlyName(peerID.displayName))
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    private func handleConnected(peerID: MCPeerID) {
        timeoutTask?.cancel()
        timeoutTask = nil

        let name = Self.friendlyName(peerID.displayName)
        phase = .exchanging(peerName: name)

        if let session, let payload = outgoingPayload {
            do {
                try session.send(payload, toPeers: [peerID], with: .reliable)
                didSend = true
            } catch {
                didSend = false
            }
        }

        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(HoofbeatRelay.settleDelay))
            guard !Task.isCancelled else { return }
            self?.conclude(peerName: name)
        }
    }

    private func conclude(peerName: String) {
        guard phase.isActive else { return }

        // Read what was sent BEFORE tearing the transport down — teardown
        // clears these, and reading them afterwards made every successful
        // handoff report itself as "neither of you had a ram to pass".
        let handed = didSend ? outgoingRamName : nil
        let handedId = didSend ? outgoingRamId : nil

        teardownTransport()
        let summary: String
        switch (handed, receivedRamName) {
        case let (given?, taken?):
            summary = "Traded \(given) for \(taken) with \(peerName)."
        case let (given?, nil):
            summary = "\(given) went with \(peerName)."
        case let (nil, taken?):
            summary = "\(peerName) handed you \(taken)."
        case (nil, nil):
            summary = "Met \(peerName) — neither of you had a ram to pass."
        }

        if handed != nil || receivedRamName != nil {
            successTick += 1
        }
        if let handedId {
            onHandedOff?(handedId, peerName)
        }
        phase = .finished(summary: summary)
        autoDismiss(after: 3.0)
    }

    private func ingest(_ data: Data) {
        guard let package = try? JSONDecoder().decode(RamTransitPackage.self, from: data) else { return }
        Task { [weak self] in
            guard let self else { return }
            let name = await self.onReceive?(package)
            self.receivedRamName = name ?? nil
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension HoofbeatRelay: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        let boxed = UnsafeTransfer(value: peerID)
        let discovered = info
        Task { @MainActor [weak self] in
            self?.consider(peerID: boxed.value, info: discovered)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // Nothing to do: an exchange either already connected or will time out.
    }

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: any Error
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.phase.isActive else { return }
            self.teardownTransport()
            self.phase = .failed(reason: "Local network access is off for Baranov.")
            self.autoDismiss(after: 3.0)
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension HoofbeatRelay: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let boxedPeer = UnsafeTransfer(value: peerID)
        let boxedHandler = UnsafeTransfer(value: invitationHandler)
        Task { @MainActor [weak self] in
            // The inviter already verified the shake windows match, and we
            // only advertise while armed — so being armed IS the consent.
            guard let self, self.phase.isActive, let session = self.session else {
                boxedHandler.value(false, nil)
                return
            }
            self.phase = .connecting(peerName: HoofbeatRelay.friendlyName(boxedPeer.value.displayName))
            boxedHandler.value(true, session)
        }
    }

    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: any Error
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.phase.isActive else { return }
            self.teardownTransport()
            self.phase = .failed(reason: "Local network access is off for Baranov.")
            self.autoDismiss(after: 3.0)
        }
    }
}

// MARK: - MCSessionDelegate

extension HoofbeatRelay: MCSessionDelegate {
    nonisolated func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        let boxed = UnsafeTransfer(value: peerID)
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch state {
            case .connected:
                self.handleConnected(peerID: boxed.value)
            case .connecting:
                self.phase = .connecting(peerName: HoofbeatRelay.friendlyName(boxed.value.displayName))
            case .notConnected:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            self?.ingest(data)
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {
        // Unused — packages are small enough to send as a single payload.
    }

    nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {
        // Unused — see above.
    }

    nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: (any Error)?
    ) {
        // Unused — see above.
    }
}
