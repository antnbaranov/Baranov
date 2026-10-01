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


    // MARK: - On-device model

    /// The locale identifier handed to the on-device model, with a region
    /// (`de_DE`, `pt_BR`, `zh_Hans_CN`), since the model's locale phrase
    /// expects a full identifier. A bare picker code gets its most likely
    /// region ("de" -> "de_DE").
    static func modelLocaleIdentifier(for code: String = AppLanguage.code) -> String {
        let language = Locale.Language(identifier: code)
        let maximal = Locale.Language(identifier: language.maximalIdentifier)
        guard let languageCode = maximal.languageCode?.identifier else {
            return code.replacingOccurrences(of: "-", with: "_")
        }
        var parts = [languageCode]
        // Only where the script changes the written language.
        if ["zh", "sr"].contains(languageCode), let script = maximal.script?.identifier {
            parts.append(script)
        }
        if let region = language.region?.identifier ?? maximal.region?.identifier {
            parts.append(region)
        }
        return parts.joined(separator: "_")
    }

    /// Wraps a feature's instructions for Apple's on-device model, following
    /// Apple's "Supporting languages and locales with Foundation Models":
    ///
    /// 1. Starts with the exact phrase "The person's locale is <id>." The
    ///    phrase comes from the model's training and reduces hallucinations
    ///    in multilingual use. Apple skips it for U.S. English.
    /// 2. Ends with an explicit "You MUST respond in <language>" rule. By
    ///    default the model answers in the language of its inputs, and our
    ///    inputs mix English instructions with place and person names in
    ///    other languages.
    ///
    /// The feature's own instructions stay in English: every input has to
    /// be in a language the model supports, and English is the one it
    /// follows best.
    static func modelInstructions(_ body: String, code: String = AppLanguage.code) -> String {
        let identifier = modelLocaleIdentifier(for: code)
        let name = englishName(for: code)
        var parts: [String] = []
        if identifier != "en_US" {
            parts.append("The person's locale is \(identifier).")
        }
        parts.append(body)
        parts.append("""
            You MUST respond in \(name) only, and be mindful of \(name) spelling, grammar, vocabulary and cultural context, \
            even though these instructions are in English. Never answer in English unless \(name) is English. \
            Keep the names of people, rams and places as given. \
            Reply with the requested text only: no preamble, no notes, no markdown, no emoji, no links.
            """)
        return parts.joined(separator: "\n")
    }

    /// The English name of a language code, for the model's language rule.
    static func englishName(for code: String) -> String {
        let english = Locale(identifier: "en")
        return english.localizedString(forIdentifier: code)
            ?? english.localizedString(forLanguageCode: code)
            ?? "English"
    }

    /// Whether Apple's on-device model can write in the app's language. When
    /// it can't, callers skip the model and show their translated built-in
    /// text instead of an English answer.
    static var modelSupportsAppLanguage: Bool { modelSupports(code: code) }

    static func modelSupports(code: String) -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.supportsLocale(Locale(identifier: code))
        }
        #endif
        return false
    }

    // MARK: - Checking model replies

    /// Checks a model reply really came back in the app's language.
    ///
    /// Two checks, because either alone misses things:
    /// - **Script.** Russian must be mostly Cyrillic, Japanese mostly kana
    ///   and kanji, German mostly Latin letters. This is reliable even for a
    ///   five-word reply, where the recognizer is guessing.
    /// - **Recognizer.** A reply confidently read as another language is
    ///   rejected. For Latin-script languages that share an alphabet with
    ///   English, an unsure reply that still leans English is rejected too:
    ///   short English leaking into a German or French app is the most
    ///   common failure.
    static func isInAppLanguage(_ text: String, code: String = AppLanguage.code) -> Bool {
        let target = family(of: code)
        let expected = expectedScripts(for: target)
        let letters = text.unicodeScalars.filter { $0.properties.isAlphabetic }
        guard !letters.isEmpty else { return false }
        let inScript = letters.filter { scalar in expected.contains { $0.contains(scalar.value) } }.count
        let share = Double(inScript) / Double(letters.count)
        // Names in Latin letters are allowed inside a non-Latin reply.
        guard share >= (target == "en" || expected == latinScripts ? 0.8 : 0.5) else { return false }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 5)
        guard let best = hypotheses.max(by: { $0.value < $1.value }) else { return true }
        let bestFamily = family(of: best.key.rawValue)
        if bestFamily == target { return true }
        if best.value >= 0.6 { return false }
        if target != "en", bestFamily == "en" {
            let targetScore = hypotheses.filter { family(of: $0.key.rawValue) == target }.map(\.value).reduce(0, +)
            if best.value >= 0.35, best.value > targetScore * 1.5 { return false }
        }
        return true
    }

    /// Cleans a model reply and rejects the ones that shouldn't be shown:
    /// empty, too long, in the wrong language, a refusal, an echo of the
    /// instructions, or anything with links, markdown or code. `nil` means
    /// "use the translated built-in text instead".
    static func acceptModelText(_ raw: String, maxCharacters: Int, code: String = AppLanguage.code) -> String? {
        var text = raw
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Leading list markers or headings.
        while let first = text.first, "#-*•>".contains(first) {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'«»„‘’「」『』").union(.whitespacesAndNewlines))
        // Collapse runs of whitespace and newlines into single spaces.
        text = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")

        guard !text.isEmpty, text.count <= maxCharacters else { return nil }
        let lowered = text.lowercased()
        let blocked = [
            "http", "www.", "://", "person's locale", "locale is", "these instructions", "as an ai", "language model",
            "i'm sorry", "i am sorry", "i can't", "i cannot", "i'm unable", "i am unable",
        ]
        guard !blocked.contains(where: { lowered.contains($0) }) else { return nil }
        guard !text.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) else { return nil }
        guard isInAppLanguage(text, code: code) else { return nil }
        return text
    }

    private static let latinScripts: [ClosedRange<UInt32>] = [0x0041...0x024F, 0x1E00...0x1EFF]

    /// Unicode ranges a language is written in (letters only).
    private static func expectedScripts(for family: String) -> [ClosedRange<UInt32>] {
        let han: [ClosedRange<UInt32>] = [0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF]
        switch family {
        case "ru", "uk", "be", "bg", "mk", "kk", "ky", "mn", "tg":
            return [0x0400...0x052F]
        case "el": return [0x0370...0x03FF, 0x1F00...0x1FFF]
        case "he", "yi": return [0x0590...0x05FF, 0xFB1D...0xFB4F]
        case "ar", "fa", "ur", "ps":
            return [0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF]
        case "hi", "mr", "ne": return [0x0900...0x097F]
        case "bn": return [0x0980...0x09FF]
        case "ta": return [0x0B80...0x0BFF]
        case "te": return [0x0C00...0x0C7F]
        case "th": return [0x0E00...0x0E7F]
        case "ka": return [0x10A0...0x10FF]
        case "hy": return [0x0530...0x058F]
        case "ko": return [0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F] + han
        case "ja": return [0x3040...0x30FF, 0x31F0...0x31FF] + han
        case "zh": return han
        case "sh": return latinScripts + [0x0400...0x052F] // Serbian is written in both
        default: return latinScripts
        }
    }

    /// Languages the recognizer can't reliably tell apart count as one.
    private static func family(of identifier: String) -> String {
        let base = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)?.lowercased() ?? identifier
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
