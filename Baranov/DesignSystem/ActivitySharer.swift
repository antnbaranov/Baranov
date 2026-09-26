//
//  ActivitySharer.swift
//  Baranov
//
//  Presents the system share sheet with several items at once: the reel's
//  video file AND the message with the App Store link. `ShareLink` with a
//  video drops its message in most apps (Messages sends only the file);
//  handing `UIActivityViewController` both items makes Messages, Mail and
//  the rest send the video together with the text.
//
//  It presents from the topmost view controller of the app's window, so it
//  appears above any sheet, including when started from the reel status
//  bar's own overlay window.
//

import SwiftUI
import UIKit

@MainActor
enum ActivitySharer {
    static func present(items: [Any]) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
              var top = window.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }

        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = top.view
        controller.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 40, width: 1, height: 1)
        top.present(controller, animated: true)
    }
}

extension RamReelData {
    /// The caption that travels with a shared reel, ending in the App Store link.
    var shareMessage: String {
        String(localized: "\(ramName) is \(personality.title). Narrated by \(voice?.name ?? String(localized: "a mystery guest")). Made with Baranov, letters that walk: \(AppLinks.appStore.absoluteString)")
    }
}
