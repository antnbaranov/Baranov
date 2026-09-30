//
//  BaranovApp.swift
//  Baranov
//
//  Created by Anton Baranov on 11.09.26.
//

import SwiftUI

@main
struct BaranovApp: App {
    /// Notifications: the delegate from launch, and the APNs device token.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
