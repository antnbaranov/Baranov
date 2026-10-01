import SwiftUI
import UIKit

/// The five illustrated guild presets. `rawValue` is the asset-catalog name.
enum ShepherdPreset: String, CaseIterable, Identifiable, Sendable {
    case wanderer = "shepherd_anton"
    case redhead = "shepherd_redhead"
    case english = "shepherd_english"
    case asian = "shepherd_asian"
    case african = "shepherd_african"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .wanderer: "Wanderer"
        case .redhead: "Redhead Shepherdess"
        case .english: "British Shepherd"
        case .asian: "Eastern Wanderer"
        case .african: "African Shepherd"
        }
    }

    /// Suggested creed applied when the preset is picked.
    var defaultMotto: String {
        switch self {
        case .wanderer: String(localized: "On foot through the fog to the Pacific", bundle: .appLanguage, locale: .appLanguage)
        case .redhead: String(localized: "Every letter is a step toward someone's home", bundle: .appLanguage, locale: .appLanguage)
        case .english: String(localized: "Slow but sure — the letter will arrive", bundle: .appLanguage, locale: .appLanguage)
        case .asian: String(localized: "A journey of a thousand miles begins with a single step", bundle: .appLanguage, locale: .appLanguage)
        case .african: String(localized: "Whoever walks slowly gets far", bundle: .appLanguage, locale: .appLanguage)
        }
    }
}

/// Persistence keys shared by header, avatar and picker.
enum ShepherdIdentityKeys {
    static let name = "com.baranov.carrierDisplayName"
    static let avatarSelection = "com.baranov.shepherdAvatarSelection" // preset rawValue or "custom"
    static let avatarFile = "com.baranov.shepherdAvatarFile"           // file name of the generated image
    static let motto = "com.baranov.shepherdMotto"
    static let customSelection = "custom"
    static let defaultMotto = ShepherdPreset.wanderer.defaultMotto
    static let mottoLimit = 60
}

/// Local storage for user-generated (Image Playground) avatars. Offline-first: no network involved.
enum ShepherdAvatarStore {
    private static var directory: URL {
        let base = URL.applicationSupportDirectory.appending(path: "ShepherdAvatar", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Copies a (temporary) generated image into app storage; returns the new file name.
    static func save(from source: URL) throws -> String {
        let name = "avatar-\(UUID().uuidString).png"
        let destination = directory.appending(path: name)
        try Data(contentsOf: source).write(to: destination, options: .atomic)
        return name
    }

    /// Deletes one stored avatar (used when a picker session is cancelled).
    static func remove(_ fileName: String) {
        guard !fileName.isEmpty else { return }
        try? FileManager.default.removeItem(at: directory.appending(path: fileName))
    }

    static func image(named fileName: String) -> UIImage? {
        guard !fileName.isEmpty else { return nil }
        return UIImage(contentsOfFile: directory.appending(path: fileName).path)
    }

    /// Removes every stored avatar except `keeping`.
    static func prune(keeping fileName: String) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent != fileName {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
