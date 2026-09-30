//
//  AppLanguage.swift
//  Baranov
//
//  The language picked in Settings → Language, for code that builds text
//  outside a SwiftUI view. `.environment(\.locale, …)` only reaches `Text`
//  and friends; `String(localized:)` on its own looks strings up in the
//  device's language, so travel notes, notifications, quotes and any other
//  text built in a model or service came out in the phone's language
//  instead of the one chosen in the app. Everything that builds a string
//  passes `bundle: .appLanguage, locale: .appLanguage` so it follows the
//  picker right away, no relaunch needed.
//

import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

/// `nonisolated` because the target defaults to main-actor isolation, and
/// services, actors and background tasks build strings too.
nonisolated enum AppLanguage {
    static let storageKey = "com.baranov.appLanguageCode"

    /// The picker's stored code, or the device language when nothing was picked.
    static var code: String {
        let stored = UserDefaults.standard.string(forKey: storageKey)
        let raw = (stored?.isEmpty == false ? stored : nil)
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"
        return raw == "no" ? "nb" : raw
    }

    static var locale: Locale { Locale(identifier: code) }

    /// The `.lproj` bundle that best matches the picked language, so
    /// `String(localized:bundle:)` looks strings up in it instead of the
    /// device's language. Falls back to the main bundle (and so to the
    /// development language) when no localization matches.
    static var bundle: Bundle {
        let available = Bundle.main.localizations.filter { $0 != "Base" }
        let match = Bundle.preferredLocalizations(from: available, forPreferences: [code]).first
        guard let match,
              let path = Bundle.main.path(forResource: match, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }

    /// The language's English name ("Russian", "Brazilian Portuguese"), for
    /// telling the on-device model which language to write in.
    static var englishName: String {
        Locale(identifier: "en").localizedString(forIdentifier: code)
            ?? Locale(identifier: "en").localizedString(forLanguageCode: code)
            ?? "English"
    }

    /// Appended to every on-device model instruction. The instructions
    /// themselves stay in English (the model follows English instructions
    /// best), so this spells out, twice, that the *reply* must be in the
    /// app's language, not English and not the phone's language.
    static var modelInstruction: String {
        """
        The person reading this uses the app in \(englishName) (locale \(code)). \
        Write your entire reply in \(englishName) only, even though these instructions are in English. \
        Keep names of people, rams and places as given.
        """
    }

    /// Whether Apple's on-device model can write in the app's language. When
    /// it can't, callers skip the model and show their translated built-in
    /// text instead of an English answer.
    static var modelSupportsAppLanguage: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.supportsLocale(locale)
        }
        #endif
        return false
    }

    /// Checks a model reply really came back in the app's language. Short or
    /// name-heavy replies the recognizer can't judge are let through; a reply
    /// it confidently reads as another language is rejected so the caller
    /// falls back to translated text.
    static func isInAppLanguage(_ text: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        guard let best = hypotheses.max(by: { $0.value < $1.value }),
              best.value >= 0.6
        else { return true }
        return family(of: best.key.rawValue) == family(of: code)
    }

    /// Languages the recognizer can't reliably tell apart count as one.
    private static func family(of identifier: String) -> String {
        let base = identifier.split(separator: "-").first.map(String.init)?.lowercased() ?? identifier
        switch base {
        case "hr", "bs", "sr": return "sh"
        case "ms", "id": return "ms"
        case "nb", "no", "nn", "da": return "no"
        case "zh": return "zh"
        default: return base
        }
    }

    /// Also tells iOS itself, so on the next launch system-drawn text
    /// (permission prompts, the Settings page, share sheet titles) matches too.
    /// This is the same setting Settings → Baranov → Language writes.
    static func applyToSystem(_ code: String) {
        UserDefaults.standard.set([code == "no" ? "nb" : code], forKey: "AppleLanguages")
    }
}

extension Bundle {
    /// Strings for the language picked in the app, not the device's.
    nonisolated static var appLanguage: Bundle { AppLanguage.bundle }
}

extension Locale {
    /// The locale for the language picked in the app, for formatting numbers
    /// and dates inside strings built outside SwiftUI views.
    nonisolated static var appLanguage: Locale { AppLanguage.locale }
}
