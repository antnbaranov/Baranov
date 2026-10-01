//
//  ContentView.swift
//  Baranov
//
//  App entry point — hands off immediately to the root screen (Journey,
//  with Pasture reached by pushing from its toolbar; see `RootView`).
//  Kept as its own tiny file so `BaranovApp.swift` doesn't need to change.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("com.baranov.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("com.baranov.carrierDisplayName") private var carrierDisplayName = ""
    @AppStorage(AppLanguagePickerView.storageKey) private var selectedLanguageCode = Locale.current.language.languageCode?.identifier ?? "en"
    @AppStorage(AppAppearance.storageKey) private var appAppearanceRawValue = AppAppearance.system.rawValue

    @State private var presentedInAppEvent: InAppEvent?
    /// "Delete all data & reset" runs from Settings; while it does, the whole
    /// window shows a progress screen, and when it is done the emptied
    /// `UserDefaults` sends the app back to onboarding.
    @State private var eraser = AppDataEraser.shared

    private var appAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRawValue) ?? .system
    }

    private var currentLocale: Locale {
        let code = selectedLanguageCode == "no" ? "nb" : selectedLanguageCode
        return Locale(identifier: code)
    }

    private var needsOnboarding: Bool {
        #if DEBUG
        if CommandLine.arguments.contains("-demoMode") { return false }
        #endif
        return !hasCompletedOnboarding || carrierDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if eraser.isErasing {
                ErasingDataView()
            } else if needsOnboarding {
                OnboardingView(onFinished: {
                    hasCompletedOnboarding = true
                })
            } else {
                // Rebuilt when the language changes: text that views build
                // in code (not through `Text`) only re-reads the language
                // when the view is made again.
                RootView()
                    .id(currentLocale.identifier)
            }
        }
        // A real background behind everything: while sheets scale the
        // content back or the map re-lays out, what shows through is the
        // system background, not the window's black.
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .environment(\.locale, currentLocale)
        .preferredColorScheme(appAppearance.colorScheme)
        .onOpenURL { url in
            if url.scheme?.caseInsensitiveCompare("baranov") == .orderedSame {
                handleDeepLink(url)
            }
        }
        .sheet(item: $presentedInAppEvent) { event in
            NavigationStack {
                InAppEventDetailView(event: event)
            }
            .presentationDragIndicator(.visible)
            .environment(\.locale, currentLocale)
            .preferredColorScheme(appAppearance.colorScheme)
        }
    }

    private func handleDeepLink(_ url: URL) {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()

        // "A letter is on its way to you" — from the link in a shared code.
        if let expected = ExpectedLetter(url: url) {
            ExpectedLetterStore.shared.add(expected)
            return
        }

        if host == "event" || path.hasPrefix("event") {
            let slug: String
            if host == "event" {
                slug = path.isEmpty ? "new-york" : path
            } else {
                let stripped = path.replacingOccurrences(of: "event/", with: "").replacingOccurrences(of: "event", with: "")
                slug = stripped.isEmpty ? "new-york" : stripped
            }
            presentedInAppEvent = InAppEvent(slug: slug)
        }
    }
}

#Preview {
    ContentView()
}
