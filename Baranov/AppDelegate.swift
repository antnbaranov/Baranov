//
//  AppDelegate.swift
//  Baranov
//
//  The little UIKit that SwiftUI's lifecycle doesn't cover: becoming the
//  notification delegate before launch finishes (so a tap that opens the
//  app is handled), registering the HealthKit step observer that wakes the
//  app in the background, and receiving the APNs device token.
//

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationManager.shared.activate()
        // Must be registered before launch finishes so a HealthKit step wake
        // of a terminated app is delivered (see BackgroundStepSync).
        BackgroundStepSync.shared.activate()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationManager.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationManager.shared.didFailToRegister(error)
    }
}
