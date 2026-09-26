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
//  people standing together who both meant to do this.
//
//  Discovery: both sides advertise AND browse on `serviceType`, publishing
//  their shake instant in `discoveryInfo["s"]`. Only the lexicographically
//  lower `displayName` invites, so the two devices can't race into two
//  half-open sessions.
//
//  Transfer: a typed, deterministic packet flow (see `TransferPacket`) —
//  no timers decide who sent what, so nothing can deadlock or fork a letter:
//
//    sender   -> .handshake(name, hasLetterToSend: true)
//    receiver -> .acceptTransfer(name)          (its own shake is the consent)
//    sender   -> .letterData(package)
//    receiver -> ingests, then .transferConfirmed   (or .transferDeclined)
//    both     -> heavy haptic, HUD summary
//
//  Every device sends a handshake on connect, with `hasLetterToSend` saying
//  whether it has a ram to give, and answers a peer's handshake with an
//  accept when the peer has one. The two directions are independent, so two
//  carriers can still trade rams in one shake. A ram is only marked handed
//  off after the receiver CONFIRMS it was ingested — never merely because
//  bytes left this phone — so a lost link can't leave the letter on neither
//  device, or on both.
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
import UIKit

/// The wire protocol of a nearby transfer.
enum TransferPacket: Codable, Sendable {
    case handshake(senderName: String, hasLetterToSend: Bool)
    case acceptTransfer(receiverName: String)
    case letterData(RamTransitPackage)
    case transferConfirmed
    /// The receiver could not take the ram (a full pasture, say). The sender
    /// keeps it.
    case transferDeclined(reason: String)
}

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

    /// How far apart two shakes may be and still count as "together". The
    /// first person to shake keeps advertising while they wait, so the
    /// second can shake a few seconds later — in either order.
    static let matchWindow: TimeInterval = 4

    /// How long we keep looking before giving up on finding a partner.
    static let searchTimeout: TimeInterval = 8

    /// How long a connected exchange may take before it is abandoned.
    static let transferTimeout: TimeInterval = 20

    /// Grace period after finishing, so the last packet (the confirmation)
    /// is delivered before the session is torn down.
    static let settleDelay: TimeInterval = 1.0

    private(set) var phase: HoofbeatPhase = .idle
    /// Bumped on every successful exchange; views key `.sensoryFeedback` to it.
    private(set) var successTick = 0
    /// Set when the exchange was started by tapping a specific nearby courier, so the HUD can say who
    /// we're waiting for. The pairing itself is still the mutual shake.
    private(set) var partnerName: String?

    /// Invoked on the main actor with each package received from a peer.
    /// Returns the name to show in the HUD, or `nil` if it was refused
    /// (a full pasture, a package that doesn't decode).
    var onReceive: ((RamTransitPackage) async -> String?)?

    /// Invoked on the main actor once the receiver has CONFIRMED a ram, with
    /// its id and the name of the carrier who took it. This is what lets the
    /// flock mark the ram `.handedOff` — a handoff that left the ram walking
    /// here too would advance the same letter on two phones at once.
    var onHandedOff: ((UUID, String) -> Void)?

    private let localPeerID: MCPeerID
    private let localCarrierName: String
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private var myShakeAt: Date = .distantPast
    private var outgoingPackage: RamTransitPackage?
    private var invitedPeers: Set<String> = []
    private var activePeer: MCPeerID?
    private var peerName = ""

    // Transfer state — one flag per fact, so each packet is idempotent.
    private var peerHandshakeSeen = false
    private var peerHasLetter = false
    private var outgoingSent = false
    private var outgoingConfirmed = false
    private var outgoingDeclined = false
    private var incomingStarted = false
    private var incomingDone = false
    private var receivedRamName: String?
    private var didConclude = false

    private var timeoutTask: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?

    /// - Parameters:
    ///   - carrierName: the person's own name, shown to the other side.
    ///   - installID: makes the peer name unique even when two people share
    ///     a first name, and gives the invite tie-break a stable ordering.
    init(carrierName: String, installID: UUID) {
        let trimmed = carrierName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Shepherd" : String(trimmed.prefix(32))
        let suffix = String(installID.uuidString.prefix(4))
        localCarrierName = base
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
    func begin(shakenAt: Date, offering package: RamTransitPackage?, partnerName: String? = nil) {
        guard !phase.isActive else { return }
        self.partnerName = partnerName

        myShakeAt = shakenAt
        outgoingPackage = package
        invitedPeers = []
        resetTransferState()

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
            self?.timeOut()
        }
    }

    /// Ends the exchange and clears the HUD back to idle.
    func reset() {
        timeoutTask?.cancel()
        timeoutTask = nil
        stallTask?.cancel()
        stallTask = nil
        settleTask?.cancel()
        settleTask = nil
        closeTask?.cancel()
        closeTask = nil
        teardownTransport()
        partnerName = nil
        phase = .idle
    }

    private func resetTransferState() {
        activePeer = nil
        peerName = ""
        peerHandshakeSeen = false
        peerHasLetter = false
        outgoingSent = false
        outgoingConfirmed = false
        outgoingDeclined = false
        incomingStarted = false
        incomingDone = false
        receivedRamName = nil
        didConclude = false
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

        outgoingPackage = nil
        invitedPeers = []
        activePeer = nil
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

    private func fail(_ reason: String) {
        guard phase.isActive, !didConclude else { return }
        timeoutTask?.cancel()
        stallTask?.cancel()
        teardownTransport()
        phase = .failed(reason: reason)
        autoDismiss(after: 3.0)
    }

    // MARK: - Pairing

    private func consider(peerID: MCPeerID, info: [String: String]?) {
        guard case .searching = phase, activePeer == nil, let session, let browser else { return }
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

    // MARK: - Transfer state machine

    private func handleConnected(peerID: MCPeerID) {
        guard activePeer == nil, phase.isActive, !didConclude else { return }
        activePeer = peerID
        peerName = Self.friendlyName(peerID.displayName)

        timeoutTask?.cancel()
        timeoutTask = nil
        phase = .exchanging(peerName: peerName)

        // If the exchange stalls, give up cleanly. Nothing was marked handed
        // off yet, so the sender simply keeps its ram.
        stallTask?.cancel()
        stallTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(HoofbeatRelay.transferTimeout))
            guard !Task.isCancelled else { return }
            self?.fail("The handoff was interrupted — nothing changed.")
        }

        send(.handshake(senderName: localCarrierName, hasLetterToSend: outgoingPackage != nil))
    }

    private func handle(_ packet: TransferPacket) {
        guard activePeer != nil, !didConclude else { return }

        switch packet {
        case let .handshake(_, hasLetter):
            peerHandshakeSeen = true
            peerHasLetter = hasLetter
            // Being armed (we shook) is the consent: accept at once.
            if hasLetter {
                send(.acceptTransfer(receiverName: localCarrierName))
            }
            checkComplete()

        case .acceptTransfer:
            guard let package = outgoingPackage, !outgoingSent else { return }
            outgoingSent = true
            send(.letterData(package))

        case let .letterData(package):
            guard peerHasLetter, !incomingStarted else { return }
            incomingStarted = true
            Task { [weak self] in
                guard let self else { return }
                let name = await self.onReceive?(package)
                guard !self.didConclude else { return }
                self.incomingDone = true
                if let name {
                    self.receivedRamName = name
                    self.send(.transferConfirmed)
                } else {
                    self.send(.transferDeclined(reason: "Pasture full"))
                }
                self.checkComplete()
            }

        case .transferConfirmed:
            guard outgoingSent else { return }
            outgoingConfirmed = true
            checkComplete()

        case .transferDeclined:
            guard outgoingSent else { return }
            outgoingDeclined = true
            checkComplete()
        }
    }

    /// Finishes once both directions are settled: our ram was confirmed (or
    /// declined) if we had one, and the peer's ram was ingested if it had one.
    private func checkComplete() {
        guard activePeer != nil, peerHandshakeSeen, !didConclude else { return }
        let outgoingResolved = outgoingPackage == nil || outgoingConfirmed || outgoingDeclined
        let incomingResolved = !peerHasLetter || incomingDone
        guard outgoingResolved, incomingResolved else { return }
        conclude()
    }

    private func conclude() {
        didConclude = true
        stallTask?.cancel()
        stallTask = nil

        let handed = outgoingConfirmed ? outgoingPackage?.ram : nil
        let peer = peerName
        let declined = outgoingDeclined ? outgoingPackage?.ram.name : nil

        let summary: String
        switch (handed?.name, receivedRamName) {
        case let (given?, taken?):
            summary = "Traded \(given) for \(taken) with \(peer)."
        case let (given?, nil):
            summary = "\(given) went with \(peer)."
        case let (nil, taken?):
            summary = "\(peer) handed you \(taken)."
        case (nil, nil):
            if let declined {
                summary = "\(peer)'s pasture is full — \(declined) stays with you."
            } else {
                summary = "Met \(peer) — neither of you had a ram to pass."
            }
        }

        if handed != nil || receivedRamName != nil {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            successTick += 1
        }
        if let handed {
            onHandedOff?(handed.id, peer)
        }
        phase = .finished(summary: summary)

        // Keep the link up briefly so our last packet reaches the peer.
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(HoofbeatRelay.settleDelay))
            guard !Task.isCancelled else { return }
            self?.teardownTransport()
        }
        autoDismiss(after: 3.0)
    }

    private func send(_ packet: TransferPacket) {
        guard let session, let peer = activePeer,
              let data = try? JSONEncoder().encode(packet) else { return }
        do {
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {
            fail("Couldn't send — the link dropped.")
        }
    }

    private func handleDisconnected(peerID: MCPeerID) {
        guard peerID == activePeer, !didConclude else { return }
        fail("The link dropped — nothing changed.")
    }

    private func handleData(_ data: Data, from peerID: MCPeerID) {
        guard peerID == activePeer,
              let packet = try? JSONDecoder().decode(TransferPacket.self, from: data) else { return }
        handle(packet)
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
            self?.fail("Local network access is off for Baranov.")
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
            guard let self, self.activePeer == nil, let session = self.session else {
                boxedHandler.value(false, nil)
                return
            }
            switch self.phase {
            case .searching, .connecting:
                self.phase = .connecting(peerName: HoofbeatRelay.friendlyName(boxedPeer.value.displayName))
                boxedHandler.value(true, session)
            default:
                boxedHandler.value(false, nil)
            }
        }
    }

    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: any Error
    ) {
        Task { @MainActor [weak self] in
            self?.fail("Local network access is off for Baranov.")
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
                switch self.phase {
                case .searching, .connecting:
                    self.phase = .connecting(peerName: HoofbeatRelay.friendlyName(boxed.value.displayName))
                default:
                    break
                }
            case .notConnected:
                self.handleDisconnected(peerID: boxed.value)
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let boxed = UnsafeTransfer(value: peerID)
        Task { @MainActor [weak self] in
            self?.handleData(data, from: boxed.value)
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
