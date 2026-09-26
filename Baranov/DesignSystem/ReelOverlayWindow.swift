//
//  ReelOverlayWindow.swift
//  Baranov
//
//  Hosts the reel job's status bar (`ReelSnackbar`) in its own transparent
//  window one level above the app's window, so it floats over every sheet
//  (the passport, the reel sheet, Compose) instead of being covered by
//  them. Touches that don't land on the bar fall through to the app below.
//

import SwiftUI
import UIKit

@MainActor
final class ReelOverlayWindow {
    static let shared = ReelOverlayWindow()

    private var window: UIWindow?

    /// Safe to call more than once; installs the window the first time a
    /// scene is available.
    func install() {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }

        let overlay = PassThroughWindow(windowScene: scene)
        overlay.windowLevel = UIWindow.Level.normal + 1
        overlay.backgroundColor = .clear

        let host = UIHostingController(rootView: ReelOverlayRoot())
        host.view.backgroundColor = .clear
        overlay.rootViewController = host
        overlay.isHidden = false
        window = overlay
    }
}

/// Lets every touch that misses the bar reach the window underneath.
private final class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === rootViewController?.view ? nil : hit
    }
}

/// The overlay's content: the snackbar at the bottom, wearing the app's own
/// language and appearance (a separate window doesn't inherit them).
private struct ReelOverlayRoot: View {
    @AppStorage(AppLanguagePickerView.storageKey) private var languageCode = Locale.current.language.languageCode?.identifier ?? "en"
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

    var body: some View {
        Color.clear
            .overlay(alignment: .bottom) { ReelSnackbar() }
            .environment(\.locale, Locale(identifier: languageCode))
            .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .system).colorScheme)
    }
}
