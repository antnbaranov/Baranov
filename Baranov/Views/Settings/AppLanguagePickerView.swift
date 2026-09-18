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

    /// A broad, common set of ISO 639-1 codes — not exhaustive, but not a
    /// token handful either, since the whole point of the search field is
    /// picking one out of a real list. `Locale` supplies the actual
    /// display name for each, localized to however the device itself is
    /// currently set.
    private static let languageCodes: [String] = [
        "en", "es", "fr", "de", "it", "pt", "ru", "uk", "pl", "nl", "sv", "no", "da", "fi",
        "is", "cs", "sk", "hu", "ro", "bg", "el", "tr", "ar", "he", "hi", "bn", "ur", "fa",
        "ja", "ko", "zh", "vi", "th", "id", "ms", "tl", "sw",
    ]

    @AppStorage(AppLanguagePickerView.storageKey) private var selectedCode: String = Locale.current.language.languageCode?.identifier ?? "en"
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var languages: [(code: String, name: String)] {
        Self.languageCodes
            .map { code in (code: code, name: Locale.current.localizedString(forLanguageCode: code)?.capitalized(with: Locale.current) ?? code) }
            .sorted { $0.name < $1.name }
    }

    private var filteredLanguages: [(code: String, name: String)] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return languages }
        return languages.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            Section {
                ForEach(filteredLanguages, id: \.code) { language in
                    Button {
                        selectedCode = language.code
                        dismiss()
                    } label: {
                        HStack {
                            Text(language.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if language.code == selectedCode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } footer: {
                Text("Baranov is only in English right now — this just saves your preference for when more languages ship.")
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
