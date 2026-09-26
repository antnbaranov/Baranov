//
//  PendingAppAction.swift
//  Baranov
//
//  A one-slot mailbox between App Intents and the UI. An intent that opens the
//  app records what it wants shown; `RootView` consumes it the next time the
//  scene becomes active, so a Siri request lands on the right screen even from
//  a cold launch.
//

import Foundation

nonisolated enum PendingAppAction: String, Sendable {
    case openPasture
    case enterLetterCode

    private static let key = "com.baranov.pendingAppAction"

    static func request(_ action: PendingAppAction) {
        UserDefaults.standard.set(action.rawValue, forKey: key)
    }

    /// Returns the pending action, if any, and clears it.
    static func consume() -> PendingAppAction? {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        return PendingAppAction(rawValue: raw)
    }
}
