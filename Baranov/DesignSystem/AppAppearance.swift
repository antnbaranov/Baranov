//
//  AppAppearance.swift
//  Baranov
//
//  The app-wide light/dark/system preference, set from a segmented
//  `Picker` on Pasture (`PastureView`) and applied once, at the root
//  (`RootView`), via `.preferredColorScheme`. Backed by a single shared
//  `@AppStorage` key — every view reading it (the picker and the root)
//  stays in sync automatically, no dedicated store needed for something
//  this small.
//

import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    static let storageKey = "com.baranov.appAppearance"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// `nil` for `.system` — `.preferredColorScheme(nil)` is exactly how
    /// you tell SwiftUI "stop overriding, follow the system setting."
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
