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

/// Why a handoff failed, so the HUD can say what to do about it.
enum HoofbeatFailure: Equatable, Sendable {
    /// iOS refused Local Network access; only Settings can fix it.
    case localNetworkDenied
    /// Nobody armed their phone the same way in time.
    case noShake
    /// A requested handover that was never accepted.
    case notAccepted
    /// The phones found each other but the link never came up.
    case unreachable
    case other
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

    /// How long a found partner may take to actually connect. Without this
    /// a connection that never completes (an invite that times out, a
    /// peer that refused, a Wi-Fi hiccup) left the HUD on "Meeting …"
    /// forever, because the search timeout only ever fired while still
    /// searching.
    ///
    /// This is a HARD cap, measured from the first moment the relay shows
    /// "Meeting …" and never re-armed by retries, repeated invitations or
    /// session callbacks — each of those used to restart the clock.
    static let connectTimeout: TimeInterval = 18

    /// How long a phone that was confirmed with a tap keeps looking: the
    /// other person still has to notice and tap too.
    static let confirmedSearchTimeout: TimeInterval = 15

    /// How many times a failed connection to the same partner is retried
    /// before giving up. MultipeerConnectivity often fails the first
    /// attempt and succeeds on the second.
    static let maxConnectAttempts = 3

    /// How long a connected exchange may take before it is abandoned.
    static let transferTimeout: TimeInterval = 20

    /// The absolute limit for one shake, whatever phase it is in. Set once
    /// in `begin` and never re-armed, so no combination of retries,
    /// repeated invitations or missed callbacks can leave the HUD up.
    static let overallTimeout: TimeInterval = 40

    /// The same two limits when the exchange was asked for from Profile or
    /// the map: the other person has to notice the request and tap Accept.
    static let requestSearchTimeout: TimeInterval = 50
    static let requestOverallTimeout: TimeInterval = 75

    /// Grace period after finishing, so the last packet (the confirmation)
    /// is delivered before the session is torn down.
    static let settleDelay: TimeInterval = 1.0

    private(set) var phase: HoofbeatPhase = .idle
    /// Bumped on every successful exchange; views key `.sensoryFeedback` to it.
    private(set) var successTick = 0
    /// Set when the exchange was started by tapping a specific nearby courier, so the HUD can say who
    /// we're waiting for. The pairing itself is still the mutual shake.
    private(set) var partnerName: String?
    /// True while this phone asked a nearby courier to accept a handover
    /// and is waiting for their answer, rather than for a shake.
    private(set) var isAwaitingAcceptance = false

    /// True once the person tapped "Hand over now" instead of shaking. A
    /// confirmed phone pairs with its named partner (or any phone that was
    /// confirmed the same way) regardless of how far apart the two shake
    /// instants are.
    private(set) var isManuallyConfirmed = false

    /// What went wrong, while `phase` is `.failed`.
    private(set) var failure: HoofbeatFailure = .other

    /// True when this exchange was agreed by request and Accept, on either
    /// side. On the accepting phone it lets the HUD say "Connecting…"
    /// rather than "Waiting for … to shake".
    var isByRequest: Bool { pairingToken != nil }

    /// Pairs two phones by a shared token (from a `HandoverRequest`)
    /// instead of by the time of their shakes.
    private var pairingToken: String?

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
    /// Peers the browser has reported, kept so a failed connection can be
    /// retried — the browser won't report the same peer a second time.
    private var discoveredPeers: [String: MCPeerID] = [:]
    private var connectAttempts: [String: Int] = [:]
    private var activePeer: MCPeerID?
    private var peerName = ""

    /// Every phone the browser has reported this exchange, whether or not
    /// it was eligible at the time, so a tap can re-evaluate them at once.
    private struct SeenPeer {
        let peer: MCPeerID
        let info: [String: String]?
    }
    private var seenPeers: [String: SeenPeer] = [:]

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
    private var connectDeadlineTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
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
    /// - Parameters:
    ///   - pairingToken: set when the exchange was agreed by request and
    ///     accept rather than by a shake; only a peer armed with the same
    ///     token is paired, and the waits are long enough for a person to
    ///     read the request and tap Accept.
    ///   - awaitingAcceptance: the sender of such a request, so the HUD
    ///     says "Waiting for X to accept…".
    func begin(shakenAt: Date, offering package: RamTransitPackage?, partnerName: String? = nil,
               pairingToken: String? = nil, awaitingAcceptance: Bool = false) {
        // A new shake while the last result is still on screen starts a
        // fresh exchange instead of being swallowed by the old HUD.
        switch phase {
        case .finished, .failed: reset()
        default: break
        }
        guard !phase.isActive else { return }
        self.partnerName = partnerName
        self.pairingToken = pairingToken
        self.isAwaitingAcceptance = awaitingAcceptance

        myShakeAt = shakenAt
        outgoingPackage = package
        invitedPeers = []
        seenPeers = [:]
        isManuallyConfirmed = false
        failure = .other
        resetTransferState()

        // No transport encryption: `.required` with no identity is the
        // classic cause of MultipeerConnectivity sessions that sit in
        // "connecting" and never finish. The letter inside the package is
        // already sealed by `LetterCipher`, so the link carries ciphertext.
        let session = MCSession(
            peer: localPeerID,
            securityIdentity: nil,
            encryptionPreference: .none
        )
        session.delegate = self
        self.session = session

        let advertiser = MCNearbyServiceAdvertiser(
            peer: localPeerID,
            discoveryInfo: discoveryInfo(),
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

        let byRequest = pairingToken != nil
        armTimeout(byRequest ? Self.requestSearchTimeout : Self.searchTimeout)

        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(byRequest ? HoofbeatRelay.requestOverallTimeout : HoofbeatRelay.overallTimeout))
            guard !Task.isCancelled else { return }
            self?.watchdogFired()
        }
        trace("begin, offering \(package?.ram.name ?? "nothing")")
    }

    /// What this phone publishes while it is armed: the shake instant, the
    /// pairing token of a requested handover, and `m` once the person
    /// tapped instead of shaking.
    private func discoveryInfo() -> [String: String] {
        var info = ["s": String(myShakeAt.timeIntervalSince1970)]
        if let pairingToken { info["t"] = pairingToken }
        if isManuallyConfirmed { info["m"] = "1" }
        return info
    }

    /// The tap alternative to the second shake. Shaking only pairs two
    /// phones whose shakes land within `matchWindow` of each other, which
    /// is exactly what fails when one person is slower than the other. A
    /// confirmed phone drops that requirement: it re-advertises itself as
    /// deliberately ready, re-checks every phone already seen, and pairs
    /// with the named partner (or any other confirmed phone) at once.
    /// Only meaningful while looking for a shake partner; a requested
    /// handover is confirmed by the other person's Accept instead.
    func confirmHandover() {
        guard case .searching = phase, pairingToken == nil, !isManuallyConfirmed else { return }
        trace("manual confirm")
        isManuallyConfirmed = true
        myShakeAt = Date()
        invitedPeers = []
        connectAttempts = [:]

        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        let fresh = MCNearbyServiceAdvertiser(
            peer: localPeerID,
            discoveryInfo: discoveryInfo(),
            serviceType: Self.serviceType
        )
        fresh.delegate = self
        fresh.startAdvertisingPeer()
        advertiser = fresh

        armTimeout(Self.confirmedSearchTimeout)

        for seen in Array(seenPeers.values) {
            consider(peerID: seen.peer, info: seen.info)
        }
        browser?.stopBrowsingForPeers()
        browser?.startBrowsingForPeers()
    }

    /// Starts the hard "Meeting …" deadline unless one is already running.
    /// Deliberately not restartable: a retried invite, a repeated
    /// invitation or a `.connecting` callback must not buy more time.
    private func armConnectDeadline() {
        guard connectDeadlineTask == nil else { return }
        connectDeadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(HoofbeatRelay.connectTimeout))
            guard !Task.isCancelled else { return }
            self?.connectDeadlineFired()
        }
    }

    private func connectDeadlineFired() {
        connectDeadlineTask = nil
        guard case .connecting = phase, activePeer == nil, !didConclude else { return }
        trace("connect deadline fired in \(phase)")
        timeOut()
    }

    private func watchdogFired() {
        switch phase {
        case .searching, .connecting, .exchanging:
            trace("watchdog fired in \(phase)")
            fail(String(localized: "The handoff was interrupted — nothing changed.", bundle: .appLanguage, locale: .appLanguage))
        case .idle, .finished, .failed:
            break
        }
    }

    private func trace(_ message: String) {
        DiagnosticsLog.shared.log(message, category: "hoofbeat")
    }

    /// (Re)starts the pairing deadline. Covers both searching and
    /// connecting, so no pre-transfer phase can outlive it.
    private func armTimeout(_ seconds: TimeInterval) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.timeOut()
        }
    }

    /// Ends the exchange and clears the HUD back to idle.
    func reset() {
        timeoutTask?.cancel()
        timeoutTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        stallTask?.cancel()
        stallTask = nil
        settleTask?.cancel()
        settleTask = nil
        closeTask?.cancel()
        closeTask = nil
        teardownTransport()
        partnerName = nil
        pairingToken = nil
        isAwaitingAcceptance = false
        isManuallyConfirmed = false
        failure = .other
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
        connectDeadlineTask?.cancel()
        connectDeadlineTask = nil
        seenPeers = [:]

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
        discoveredPeers = [:]
        connectAttempts = [:]
        activePeer = nil
    }

    private func timeOut() {
        trace("timeout in \(phase)")
        let reason: String
        let kind: HoofbeatFailure
        switch phase {
        case .searching where isAwaitingAcceptance:
            kind = .notAccepted
            if let partnerName, !partnerName.isEmpty {
                reason = String(localized: "\(partnerName) didn't accept. Nothing changed.", bundle: .appLanguage, locale: .appLanguage)
            } else {
                reason = String(localized: "No one accepted. Nothing changed.", bundle: .appLanguage, locale: .appLanguage)
            }
        case .searching:
            kind = .noShake
            reason = String(localized: "No one shook back nearby.", bundle: .appLanguage, locale: .appLanguage)
        case let .connecting(name):
            kind = .unreachable
            reason = String(localized: "Couldn't reach \(name). Nothing changed — shake together again.", bundle: .appLanguage, locale: .appLanguage)
        default:
            return
        }
        teardownTransport()
        failure = kind
        phase = .failed(reason: reason)
        autoDismiss(after: 15.0)
    }

    private func autoDismiss(after seconds: TimeInterval) {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.reset()
        }
    }

    private func fail(_ reason: String, kind: HoofbeatFailure = .other) {
        guard phase.isActive, !didConclude else { return }
        failure = kind
        trace("failed in \(phase): \(reason)")
        timeoutTask?.cancel()
        connectDeadlineTask?.cancel()
        connectDeadlineTask = nil
        watchdogTask?.cancel()
        stallTask?.cancel()
        teardownTransport()
        phase = .failed(reason: reason)
        autoDismiss(after: 15.0)
    }

    // MARK: - Pairing

    private func consider(peerID: MCPeerID, info: [String: String]?) {
        if peerID.displayName != localPeerID.displayName {
            seenPeers[peerID.displayName] = SeenPeer(peer: peerID, info: info)
        }
        guard case .searching = phase, activePeer == nil, let session, let browser else { return }
        guard peerID.displayName != localPeerID.displayName else { return }
        guard !invitedPeers.contains(peerID.displayName) else { return }

        // A requested handover pairs only with the phone holding the same
        // token; a shake pairs only with another shake inside the window.
        guard info?["t"] == pairingToken else { return }
        if pairingToken == nil {
            if isManuallyConfirmed || info?["m"] == "1" {
                // A tap on either side replaces the timing check, so the
                // person we meant to hand over to is the proof instead.
                if let partnerName, !partnerName.isEmpty,
                   Self.friendlyName(peerID.displayName)
                    .caseInsensitiveCompare(partnerName) != .orderedSame { return }
            } else {
                guard let stamp = info?["s"], let seconds = TimeInterval(stamp) else { return }
                let theirShake = Date(timeIntervalSince1970: seconds)
                guard abs(theirShake.timeIntervalSince(myShakeAt)) <= Self.matchWindow else { return }
            }
        }

        // Deterministic tie-break: exactly one of the two devices invites,
        // so they don't collide into two half-open sessions.
        guard localPeerID.displayName < peerID.displayName else { return }

        discoveredPeers[peerID.displayName] = peerID
        invite(peerID, session: session, browser: browser)
    }

    /// Restarts Bonjour discovery on both halves. After a failed attempt
    /// MultipeerConnectivity often keeps a stale record of the other phone
    /// that blocks the next invitation; a fresh advertise/browse clears it.
    private func restartDiscovery() {
        browser?.stopBrowsingForPeers()
        browser?.startBrowsingForPeers()
        advertiser?.stopAdvertisingPeer()
        advertiser?.startAdvertisingPeer()
    }

    private func invite(_ peerID: MCPeerID, session: MCSession, browser: MCNearbyServiceBrowser) {
        trace("inviting \(peerID.displayName), attempt \(connectAttempts[peerID.displayName, default: 0] + 1)")
        invitedPeers.insert(peerID.displayName)
        connectAttempts[peerID.displayName, default: 0] += 1
        phase = .connecting(peerName: Self.friendlyName(peerID.displayName))
        armTimeout(Self.connectTimeout)
        armConnectDeadline()
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 12)
    }

    /// A connection that dropped before the exchange began. The inviter
    /// retries once; the invitee goes back to waiting for that retry. The
    /// pairing deadline still bounds the whole thing.
    private func handleConnectFailed(peerID: MCPeerID) {
        guard activePeer == nil, !didConclude, case .connecting = phase else { return }
        trace("connection to \(peerID.displayName) dropped before the exchange")
        let name = peerID.displayName
        if discoveredPeers[name] != nil,
           connectAttempts[name, default: 0] < Self.maxConnectAttempts {
            restartDiscovery()
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(900))
                guard let self, self.activePeer == nil, case .connecting = self.phase,
                      let session = self.session, let browser = self.browser,
                      let peer = self.discoveredPeers[name] else { return }
                self.invite(peer, session: session, browser: browser)
            }
        } else if discoveredPeers[name] == nil {
            // We were the invitee: wait for the inviter's retry, visible again.
            restartDiscovery()
            phase = .searching
        } else {
            fail(String(localized: "Couldn't reach \(Self.friendlyName(name)). Nothing changed — shake together again.", bundle: .appLanguage, locale: .appLanguage),
                 kind: .unreachable)
        }
    }

    // MARK: - Transfer state machine

    private func handleConnected(peerID: MCPeerID) {
        guard activePeer == nil, phase.isActive, !didConclude else { return }
        activePeer = peerID
        peerName = Self.friendlyName(peerID.displayName)
        isAwaitingAcceptance = false
        trace("connected to \(peerID.displayName)")

        timeoutTask?.cancel()
        timeoutTask = nil
        connectDeadlineTask?.cancel()
        connectDeadlineTask = nil
        phase = .exchanging(peerName: peerName)

        // If the exchange stalls, give up cleanly. Nothing was marked handed
        // off yet, so the sender simply keeps its ram.
        stallTask?.cancel()
        stallTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(HoofbeatRelay.transferTimeout))
            guard !Task.isCancelled else { return }
            self?.fail(String(localized: "The handoff was interrupted — nothing changed.", bundle: .appLanguage, locale: .appLanguage))
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
        watchdogTask?.cancel()
        stallTask?.cancel()
        stallTask = nil

        let handed = outgoingConfirmed ? outgoingPackage?.ram : nil
        let peer = peerName
        let declined = outgoingDeclined ? outgoingPackage?.ram.name : nil

        let summary: String
        switch (handed?.name, receivedRamName) {
        case let (given?, taken?):
            summary = String(localized: "Traded \(given) for \(taken) with \(peer).", bundle: .appLanguage, locale: .appLanguage)
        case let (given?, nil):
            summary = String(localized: "\(given) went with \(peer).", bundle: .appLanguage, locale: .appLanguage)
        case let (nil, taken?):
            summary = String(localized: "\(peer) handed you \(taken).", bundle: .appLanguage, locale: .appLanguage)
        case (nil, nil):
            if let declined {
                summary = String(localized: "\(peer)'s pasture is full — \(declined) stays with you.", bundle: .appLanguage, locale: .appLanguage)
            } else {
                summary = String(localized: "Met \(peer) — neither of you had a ram to pass.", bundle: .appLanguage, locale: .appLanguage)
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
            fail(String(localized: "Couldn't send — the link dropped.", bundle: .appLanguage, locale: .appLanguage))
        }
    }

    private func handleDisconnected(peerID: MCPeerID) {
        if activePeer == nil {
            handleConnectFailed(peerID: peerID)
            return
        }
        guard peerID == activePeer, !didConclude else { return }
        fail(String(localized: "The link dropped — nothing changed.", bundle: .appLanguage, locale: .appLanguage))
    }

    private func handleData(_ data: Data, from peerID: MCPeerID) {
        // Data can overtake the `.connected` callback on its way to the main
        // actor. Dropping that first handshake used to stall the exchange
        // until the transfer timeout; treat it as the connection instead.
        if activePeer == nil, session?.connectedPeers.contains(peerID) == true {
            handleConnected(peerID: peerID)
        }
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
            self?.fail(String(localized: "Local network access is off for Baranov.", bundle: .appLanguage, locale: .appLanguage),
                       kind: .localNetworkDenied)
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
                self.armTimeout(HoofbeatRelay.connectTimeout)
                self.armConnectDeadline()
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
            self?.fail(String(localized: "Local network access is off for Baranov.", bundle: .appLanguage, locale: .appLanguage),
                       kind: .localNetworkDenied)
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
                    self.armConnectDeadline()
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

    /// Accepts the peer's certificate. With `encryptionPreference: .required`
    /// and no identity, leaving this unimplemented makes some devices stall
    /// in "connecting" and then drop — the pairing proof is the shake, not
    /// the certificate.
    nonisolated func session(
        _ session: MCSession,
        didReceiveCertificate certificate: [Any]?,
        fromPeer peerID: MCPeerID,
        certificateHandler: @escaping (Bool) -> Void
    ) {
        certificateHandler(true)
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
