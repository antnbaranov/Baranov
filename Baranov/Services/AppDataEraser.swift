//
//  AppDataEraser.swift
//  Baranov
//
//  "Delete all data & reset" (App Store Review Guideline 5.1.1(v)).
//
//  Baranov has no accounts: a person is a Shepherd ID, a key pair in the
//  Keychain and a pile of local files. This is the one place that knows
//  everything the app keeps, and takes all of it away, in this order:
//
//   1. `isErasing` goes true. `ContentView` swaps the whole `RootView` for a
//      progress screen, which tears down every screen, store and `.task`
//      that was running, so nothing is left to write anything back.
//   2. The live parts stop: Live Activities, the flock's writes, HealthKit
//      wake-ups, APNs registration, notifications.
//   3. The relay is asked to forget the Shepherd ID, the push token, the gate
//      and any pending letters. Time-boxed; on failure the wipe goes on
//      (see `LetterRelayService.deleteUserData`). This has to come before
//      step 5: the inbox token that proves the ID is ours lives in the
//      Keychain.
//   4. The singletons that hold state in memory forget it, so none of it can
//      be written back after the files are gone.
//   5. Keychain, `UserDefaults`, and every file in Application Support,
//      Documents, Caches, `tmp` and the app group container are removed.
//   6. `isErasing` goes false. `UserDefaults` is empty, so
//      `hasCompletedOnboarding` is false again and `ContentView` shows
//      onboarding, exactly as on a first launch.
//
//  Purchases are not touched: they belong to the Apple ID, and RevenueCat's
//  own cache is left alone so a subscriber stays one (see `isKept`).
//
//  The wipe is best-effort per item: one file that won't delete never stops
//  the rest.
//

import Foundation
import Observation
import Security
import WidgetKit

@MainActor
@Observable
final class AppDataEraser {
    static let shared = AppDataEraser()

    /// True from the moment the person confirms until everything is gone.
    /// `ContentView` shows a progress screen meanwhile.
    private(set) var isErasing = false

    /// What the relay said last time (for diagnostics and tests).
    @ObservationIgnored private(set) var lastRemoteOutcome: RemoteEraseOutcome?

    /// Where the flock is mirrored for the widget and the watch.
    nonisolated static let appGroupIdentifier = "group.com.baranov"

    private init() {}

    /// Erases everything this app keeps about the person and returns the app
    /// to its first-launch state. Safe to call from a view that is about to
    /// disappear: nothing here is tied to the caller's lifetime.
    func eraseEverything(flock: FlockViewModel?) async {
        guard !isErasing else { return }
        isErasing = true

        // Let SwiftUI take the old root down before anything is removed.
        try? await Task.sleep(for: .milliseconds(250))

        // 2. Stop everything that is still running.
        flock?.eraseAll()
        BackgroundStepSync.shared.eraseAll()
        PhoneWatchSessionManager.shared.eraseAll()
        NotificationManager.shared.prepareForErase()

        // 3. The relay, while the inbox token is still in the Keychain.
        lastRemoteOutcome = await LetterRelayService.shared.deleteUserData()

        // 4. In-memory state.
        LetterTracker.shared.eraseAll()
        ExpectedLetterStore.shared.eraseAll()
        GateStore.shared.eraseAll()
        NameProfile.shared.eraseAll()
        RamColorStore.shared.eraseAll()
        ReelJobStore.shared.eraseAll()
        await Analytics.shared.eraseAll()
        await DiagnosticsLog.shared.clear()

        // 5. Storage.
        Self.wipeKeychain()
        Self.wipeUserDefaults()
        _ = await Task.detached(priority: .userInitiated) {
            Self.wipeFiles()
        }.value
        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)

        // The widget and the Lock Screen read what the app wrote.
        WidgetCenter.shared.reloadAllTimelines()

        // 6. Back to the beginning.
        isErasing = false
    }

    // MARK: - Keychain

    /// Every secret this app holds: the Shepherd ID's private key and inbox
    /// token (`AddressKeychain`), every letter's receiving code
    /// (`SealKeyVault`) and recall token (`RecallTokenVault`). Deleting by
    /// class, not by the three known services, also catches anything an
    /// older build left behind. Items only ever exist in this app's own
    /// access group, so nothing of any other app is touched.
    static func wipeKeychain() {
        AddressKeychain.reset()
        let classes: [CFString] = [
            kSecClassGenericPassword, kSecClassInternetPassword,
            kSecClassKey, kSecClassCertificate, kSecClassIdentity,
        ]
        for itemClass in classes {
            let query: [String: Any] = [
                kSecClass as String: itemClass,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    // MARK: - UserDefaults

    /// Keys another SDK owns. RevenueCat's cached customer info and anonymous
    /// ID carry no personal data, and dropping them would make a paying
    /// subscriber look new until the next receipt sync.
    private static func isKept(_ key: String) -> Bool {
        key.hasPrefix("com.revenuecat.")
    }

    /// Onboarding status, names, sharing toggles, telemetry flags, language,
    /// caches of every kind: everything the app and the app group keep in
    /// preferences. Keys are removed one by one first so `@AppStorage`
    /// views are told, then the whole domain goes.
    static func wipeUserDefaults() {
        var domains: [(UserDefaults, String)] = []
        if let bundleID = Bundle.main.bundleIdentifier {
            domains.append((.standard, bundleID))
        }
        if let group = UserDefaults(suiteName: appGroupIdentifier) {
            domains.append((group, appGroupIdentifier))
        }
        for (defaults, domain) in domains {
            let saved = defaults.persistentDomain(forName: domain) ?? [:]
            for key in saved.keys where !isKept(key) {
                defaults.removeObject(forKey: key)
            }
            // Anything that survives is kept on purpose: put it back after the
            // domain is dropped, which would otherwise take it too.
            let kept = saved.filter { isKept($0.key) }
            defaults.removePersistentDomain(forName: domain)
            for (key, value) in kept {
                defaults.set(value, forKey: key)
            }
        }
    }

    // MARK: - Files

    /// Letters, journey passports and stamps (`flock.json`), drafts, held
    /// letters, avatars, the analytics queue and the diagnostics log
    /// (Application Support and the app group container), reels and other
    /// temporary media (`tmp`), map tiles and every other cache (`Caches`),
    /// and Documents. The folders themselves stay, empty. Returns how many
    /// items could not be removed.
    @discardableResult
    nonisolated static func wipeFiles() -> Int {
        let fileManager = FileManager.default
        var failures = 0

        var roots: [URL] = []
        for directory: FileManager.SearchPathDirectory in [.applicationSupportDirectory, .documentDirectory, .cachesDirectory] {
            roots.append(contentsOf: fileManager.urls(for: directory, in: .userDomainMask))
        }
        roots.append(fileManager.temporaryDirectory)

        for root in roots {
            failures += removeContents(of: root, in: fileManager)
        }

        // The app group container: the flock mirror the widget reads. Its
        // `Library` holds the group's preferences, which `wipeUserDefaults`
        // owns.
        if let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            failures += removeContents(of: group, in: fileManager, keeping: ["Library"])
        }

        // Several stores write into Application Support on demand but only
        // create the folder once, at start-up.
        for root in fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask) {
            try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return failures
    }

    private nonisolated static func removeContents(of directory: URL, in fileManager: FileManager, keeping: Set<String> = []) -> Int {
        guard let items = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return 0 }
        var failures = 0
        for item in items where !keeping.contains(item.lastPathComponent) {
            do {
                try fileManager.removeItem(at: item)
            } catch {
                failures += 1
            }
        }
        return failures
    }
}
