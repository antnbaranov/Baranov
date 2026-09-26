//
//  ProximityCodeDiscovery.swift
//  Baranov
//
//  Passive, shake-free discovery of a nearby code. A person advertises
//  their profile code (only while they've asked to share it) so a friend
//  standing next to them can put a letter straight into their mailbag; the
//  other phone browses while Nearby is on. No session is
//  ever opened — the code rides in the Bonjour `discoveryInfo` and that
//  is all that is exchanged.
//
//  Info.plist: `NSLocalNetworkUsageDescription` and `NSBonjourServices`
//  (`_baranov-post._tcp` / `._udp`). Discovery info is unencrypted, so a
//  code is only broadcast on an explicit tap and for a short window.
//

import Foundation
import MultipeerConnectivity
import Observation

@MainActor
@Observable
final class ProximityCodeDiscovery: NSObject {
    enum State: Equatable, Sendable {
        case idle
        case listening
        case locked(code: String)
    }

    private(set) var state: State = .idle
    private(set) var isBroadcasting = false

    @ObservationIgnored private let peerID = MCPeerID(displayName: "ram-" + String(UUID().uuidString.prefix(6)))
    @ObservationIgnored private var browser: MCNearbyServiceBrowser?
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?
    @ObservationIgnored private var broadcastTimeout: Task<Void, Never>?
    @ObservationIgnored nonisolated static let serviceType = "baranov-post"
    @ObservationIgnored nonisolated static let codeKey = "code"
    /// How long a shared code stays on the air.
    @ObservationIgnored static let broadcastWindow: Duration = .seconds(90)

    // MARK: Receiver — listen passively

    func startListening() {
        guard browser == nil else { return }
        let b = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        b.delegate = self
        b.startBrowsingForPeers()
        browser = b
        if state == .idle { state = .listening }
    }

    func stopListening() {
        browser?.stopBrowsingForPeers()
        browser = nil
        state = .idle
    }

    // MARK: Sender — announce a receiving code, briefly

    func startBroadcasting(code: String) {
        stopBroadcasting()
        let a = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: [Self.codeKey: code], serviceType: Self.serviceType)
        a.delegate = self
        a.startAdvertisingPeer()
        advertiser = a
        isBroadcasting = true
        broadcastTimeout = Task { [weak self] in
            try? await Task.sleep(for: Self.broadcastWindow)
            guard !Task.isCancelled else { return }
            self?.stopBroadcasting()
        }
    }

    func stopBroadcasting() {
        broadcastTimeout?.cancel()
        broadcastTimeout = nil
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        isBroadcasting = false
    }

    func stop() {
        stopListening()
        stopBroadcasting()
    }

    /// Dismiss a locked code and keep listening.
    func resumeListening() {
        state = browser == nil ? .idle : .listening
    }

    fileprivate func lock(code: String) { state = .locked(code: code) }

    fileprivate func peerLost() {
        if case .locked = state { return }   // keep a found code until the person acts on it
        state = browser == nil ? .idle : .listening
    }
}

extension ProximityCodeDiscovery: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        guard let code = info?[Self.codeKey], !code.isEmpty else { return }
        Task { @MainActor in self.lock(code: code) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in self.peerLost() }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        // Never let discovery failing (Local Network denied, say) touch step recording.
        Task { @MainActor in self.state = .idle }
    }
}

extension ProximityCodeDiscovery: MCNearbyServiceAdvertiserDelegate {
    /// Only ever advertising — refuse every session invitation.
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(false, nil)
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in self.stopBroadcasting() }
    }
}
