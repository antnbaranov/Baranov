//
//  PhoneWatchSessionManager.swift
//  Baranov
//
//  Broadcasts active ram and journey state to paired Apple Watches via
//  WatchConnectivity and shared App Group defaults.
//

import Foundation
import WatchConnectivity

@MainActor
final class PhoneWatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchSessionManager()

    override private init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    func syncRamState(
        ramName: String,
        fromCity: String,
        toCity: String,
        progress: Double,
        remainingSteps: Int,
        remainingDistance: String,
        statusSymbol: String,
        statusLabel: String,
        isAtSea: Bool = false,
        seaVoyageTitle: String? = nil
    ) {
        let payload: [String: Any] = [
            "ramName": ramName,
            "fromCity": fromCity,
            "toCity": toCity,
            "progress": progress,
            "remainingSteps": remainingSteps,
            "remainingDistance": remainingDistance,
            "statusSymbol": statusSymbol,
            "statusLabel": statusLabel,
            "isAtSea": isAtSea,
            "seaVoyageTitle": seaVoyageTitle as Any
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 }) else { return }

        // 1. Save to shared App Group for instant local reads
        if let sharedDefaults = UserDefaults(suiteName: "group.com.baranov") {
            sharedDefaults.set(data, forKey: "com.baranov.watchState")
        }

        // 2. Push to paired watch if session active
        if WCSession.isSupported() {
            let session = WCSession.default
            if session.activationState == .activated {
                try? session.updateApplicationContext(["watchState": data])
            }
        }
    }

    var onStepsReceived: ((Int) -> Void)?

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let steps = message["walkSessionSteps"] as? Int, steps > 0 {
            Task { @MainActor in
                self.onStepsReceived?(steps)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        if let steps = userInfo["walkSessionSteps"] as? Int, steps > 0 {
            Task { @MainActor in
                self.onStepsReceived?(steps)
            }
        }
    }
}
