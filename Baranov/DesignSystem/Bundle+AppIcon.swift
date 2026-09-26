//
//  Bundle+AppIcon.swift
//  Baranov
//
//  Reads the app's real icon straight out of the asset catalog via
//  `Info.plist`'s `CFBundleIcons` — the same lookup Settings uses to show a
//  third-party app's actual icon, so the reel's end card always matches
//  whatever `AppIcon.appiconset` currently contains, with zero upkeep.
//

import UIKit

extension Bundle {
    /// The app's primary icon, or `nil` if it can't be resolved (e.g. in a
    /// preview target with a stripped `Info.plist`). Never a placeholder —
    /// callers decide what "no icon" looks like.
    var appIconImage: UIImage? {
        guard let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last
        else { return nil }
        return UIImage(named: name)
    }
}
