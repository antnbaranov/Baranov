//
//  QuickActions.swift
//  Baranov
//
//  The Home Screen quick action: press and hold the app icon and
//  "Don't delete us!" shows up with an envelope badge. Tapping it opens the
//  app and schedules one friendly note from the ram for a minute later (only
//  if notifications are allowed, and the person is asked once if they never
//  were; see `NotificationManager.scheduleQuickActionNote`).
//
//  The item is dynamic, not in Info.plist, so its text follows the language
//  chosen in Settings. It is refreshed whenever the scene becomes active.
//
//  SwiftUI's lifecycle doesn't deliver quick actions by itself: the app
//  delegate hands every scene `QuickActionSceneDelegate`, which receives
//  them both on a cold launch and while the app is running.
//

import UIKit

enum QuickAction: String {
    case dontDeleteUs = "com.baranov.quickaction.dontDeleteUs"
}

enum QuickActions {
    /// Sets the Home Screen shortcut items.
    static func install() {
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(
                type: QuickAction.dontDeleteUs.rawValue,
                localizedTitle: String(localized: "Don't delete us!", bundle: .appLanguage, locale: .appLanguage),
                localizedSubtitle: String(localized: "You'll receive a message soon", bundle: .appLanguage, locale: .appLanguage),
                icon: UIApplicationShortcutIcon(systemImageName: "envelope.badge"),
                userInfo: nil
            ),
        ]
    }

    /// Runs the action behind a tapped shortcut. Returns whether it was one of ours.
    @discardableResult
    static func handle(_ item: UIApplicationShortcutItem) -> Bool {
        switch QuickAction(rawValue: item.type) {
        case .dontDeleteUs:
            Task { await NotificationManager.shared.scheduleQuickActionNote() }
            return true
        case nil:
            return false
        }
    }
}

/// Receives quick actions for the SwiftUI window scene.
final class QuickActionSceneDelegate: UIResponder, UIWindowSceneDelegate {
    /// Cold launch from a quick action.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem {
            QuickActions.handle(item)
        }
    }

    /// The app was already running.
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(QuickActions.handle(shortcutItem))
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        QuickActions.install()
    }
}
