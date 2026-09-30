//
//  AppLanguagePickerView.swift
//  Baranov
//
//  A full, searchable list of languages — pushed from the "Language" row.
//  SwiftUI text follows the pick through `.environment(\.locale, …)` at the
//  root; strings built in code follow it through `AppLanguage`
//  (`bundle: .appLanguage`), so the whole app switches at once.
//

import SwiftUI

struct AppLanguagePickerView: View {
    static let storageKey = AppLanguage.storageKey

    /// Full set of App Store Connect supported languages and all European languages
    static let languageCodes: [String] = [
        "en", "en-GB", "en-AU", "en-CA",
        "sq", "ar", "eu", "bs", "bg", "ca",
        "zh-Hans", "zh-Hant", "zh-HK", "hr", "cs",
        "da", "nl", "et", "fi", "fr", "fr-CA",
        "gl", "de", "el", "he", "hi", "hu",
        "is", "id", "ga", "it", "ja", "ka", "kk", "ko",
        "lv", "lt", "mk", "ms", "mt", "nb",
        "pl", "pt-BR", "pt-PT", "ro", "ru", "sr",
        "sk", "sl", "es", "es-419", "sv", "th",
        "tr", "uk", "vi"
    ]

    struct LanguageItem: Identifiable {
        var id: String { code }
        let code: String
        let autonym: String
        let localizedName: String

        var title: String {
            autonym
        }

        var subtitle: String? {
            if autonym.caseInsensitiveCompare(localizedName) == .orderedSame {
                return nil
            }
            return localizedName
        }
    }

    @AppStorage(AppLanguagePickerView.storageKey) private var selectedCode: String = Locale.current.language.languageCode?.identifier ?? "en"
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var languages: [LanguageItem] {
        Self.languageCodes.map { code in
            let targetLocale = Locale(identifier: code)
            let nativeName = targetLocale.localizedString(forIdentifier: code)?.capitalized(with: targetLocale)
                ?? targetLocale.localizedString(forLanguageCode: code)?.capitalized(with: targetLocale)
                ?? code

            let localName = Locale.current.localizedString(forIdentifier: code)?.capitalized(with: Locale.current)
                ?? Locale.current.localizedString(forLanguageCode: code)?.capitalized(with: Locale.current)
                ?? code

            return LanguageItem(
                code: code,
                autonym: nativeName,
                localizedName: localName
            )
        }.sorted { $0.autonym.localizedCaseInsensitiveCompare($1.autonym) == .orderedAscending }
    }

    private var filteredLanguages: [LanguageItem] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return languages }
        return languages.filter {
            $0.autonym.localizedCaseInsensitiveContains(searchText) ||
            $0.localizedName.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(filteredLanguages) { language in
                    Button {
                        selectedCode = language.code
                        // System-drawn text (permission prompts, share sheet)
                        // follows on next launch; scheduled notifications are
                        // rewritten now so they arrive in the new language.
                        AppLanguage.applyToSystem(language.code)
                        NotificationCenter.default.post(name: RamNotificationService.preferencesChanged, object: nil)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(language.title)
                                    .foregroundStyle(.primary)
                                if let subtitle = language.subtitle {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if language.code == selectedCode || (selectedCode.starts(with: language.code) && language.code == "en" && selectedCode == "en-US") {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            } footer: {
                Text("Apple Maps text and system prompts switch to the new language after you restart Baranov.")
            }
        }
        .searchable(text: $searchText, prompt: "Search Languages")
        .tint(.primary)
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AppLanguagePickerView()
    }
}
