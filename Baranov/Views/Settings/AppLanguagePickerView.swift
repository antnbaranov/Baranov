//
//  AppLanguagePickerView.swift
//  Baranov
//
//  A full, searchable list of languages to save as a preference — pushed
//  from the "Language" row on Pasture (`PastureView`). Honest about what
//  it does right now: Baranov only actually ships English copy today, so
//  picking anything else here doesn't retranslate the app yet — it just
//  saves the preference (`@AppStorage`, `AppLanguagePickerView.storageKey`)
//  for whenever real localization lands, rather than pretending to be a
//  working language switcher it isn't.
//

import SwiftUI

struct AppLanguagePickerView: View {
    static let storageKey = "com.baranov.appLanguageCode"

    /// Full set of App Store Connect supported languages and all European languages
    static let languageCodes: [String] = [
        "en", "en-GB", "en-AU", "en-CA",
        "sq", "ar", "eu", "bs", "bg", "ca",
        "zh-Hans", "zh-Hant", "zh-HK", "hr", "cs",
        "da", "nl", "et", "fi", "fr", "fr-CA",
        "gl", "de", "el", "he", "hi", "hu",
        "is", "id", "ga", "it", "ja", "ko",
        "lv", "lt", "mk", "ms", "mt", "no",
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
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search Languages")
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AppLanguagePickerView()
    }
}
