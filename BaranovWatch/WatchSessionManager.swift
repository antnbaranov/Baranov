//
//  WatchSessionManager.swift
//  BaranovWatch
//
//  Receives live flock and ram companion state from iPhone via
//  WatchConnectivity and shared App Group container.
//

import Foundation
import Observation
import WatchConnectivity
import WatchKit

struct WatchRamState: Codable, Equatable {
    var ramName: String
    var fromCity: String
    var toCity: String
    var progress: Double
    var remainingSteps: Int
    var remainingDistance: String
    var statusSymbol: String
    var statusLabel: String
    var isAtSea: Bool
    var seaVoyageTitle: String?

    static var preview: WatchRamState {
        WatchRamState(
            ramName: "Klaus",
            fromCity: "London",
            toCity: "Edinburgh",
            progress: 0.42,
            remainingSteps: 248_000,
            remainingDistance: "248 km",
            statusSymbol: "figure.walk",
            statusLabel: "Walking",
            isAtSea: false,
            seaVoyageTitle: nil
        )
    }

    static var empty: WatchRamState {
        WatchRamState(
            ramName: String(localized: "Your ram"),
            fromCity: "",
            toCity: "",
            progress: 0.0,
            remainingSteps: 0,
            remainingDistance: "—",
            statusSymbol: "leaf.fill",
            statusLabel: String(localized: "Open Baranov on iPhone"),
            isAtSea: false,
            seaVoyageTitle: nil
        )
    }
}

@Observable
@MainActor
final class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    /// Real data only: the cached state from the iPhone, or a neutral empty
    /// state until the first sync arrives (never sample data).
    var state: WatchRamState = .empty

    override private init() {
        super.init()
        loadLocalCachedState()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    func loadLocalCachedState() {
        if let sharedDefaults = UserDefaults(suiteName: "group.com.baranov"),
           let data = sharedDefaults.data(forKey: "com.baranov.watchState"),
           let decoded = try? JSONDecoder().decode(WatchRamState.self, from: data) {
            self.state = decoded
        }
    }

    func saveLocalCachedState(_ newState: WatchRamState) {
        if let sharedDefaults = UserDefaults(suiteName: "group.com.baranov"),
           let encoded = try? JSONEncoder().encode(newState) {
            sharedDefaults.set(encoded, forKey: "com.baranov.watchState")
        }
    }

    func sendWalkSteps(_ steps: Int) {
        guard steps > 0 else { return }
        state.remainingSteps = max(0, state.remainingSteps - steps)
        let remaining = state.remainingSteps
        state.remainingDistance = remaining >= 1000 ? String(format: "%.1f km", Double(remaining) / 1000) : "\(remaining) m"
        saveLocalCachedState(state)

        if WCSession.isSupported() {
            let session = WCSession.default
            if session.isReachable {
                session.sendMessage(["walkSessionSteps": steps], replyHandler: nil)
            } else {
                session.transferUserInfo(["walkSessionSteps": steps])
            }
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("[WatchSessionManager] WCSession activation failed: \(error)")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        if let data = applicationContext["watchState"] as? Data,
           let decoded = try? JSONDecoder().decode(WatchRamState.self, from: data) {
            Task { @MainActor in
                self.state = decoded
                self.saveLocalCachedState(decoded)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        if let data = userInfo["watchState"] as? Data,
           let decoded = try? JSONDecoder().decode(WatchRamState.self, from: data) {
            Task { @MainActor in
                self.state = decoded
                self.saveLocalCachedState(decoded)
            }
        }
    }
}
