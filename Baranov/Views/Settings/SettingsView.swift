//
//  SettingsView.swift
//  Baranov
//
//  App-level preferences as their own screen, pushed from Pasture. An
//  inset-grouped list — the same look as Pasture and Satchel. "Expand the
//  Pasture" moved up to the Pasture screen itself (right under the ram
//  selector, where the locked pens already live) — this screen no longer
//  carries a subscription entry point at all.
//
//  Debug builds only: a hidden "Developer" section at the bottom lets a
//  tester punch in a code to flip the mock pasture-expansion entitlement
//  without RevenueCat. Compiled out of every release build via #if DEBUG,
//  so it never ships and never reaches App Review.
//

import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(FlockViewModel.self) private var flockViewModel
    #if DEBUG
    @Environment(EntitlementService.self) private var entitlementService
    #endif

    @AppStorage(AppAppearance.storageKey) private var appAppearanceRawValue = AppAppearance.system.rawValue
    @AppStorage(AppLanguagePickerView.storageKey) private var selectedLanguageCode = Locale.current.language.languageCode?.identifier ?? "en"
    @AppStorage("com.baranov.notificationsEnabled") private var notificationsEnabled = false
    @AppStorage(RamNotificationService.morningEnabledKey) private var morningNoteEnabled = true
    @AppStorage(RamNotificationService.morningMinutesKey) private var morningMinutes = RamNotificationService.defaultMorningMinutes
    @AppStorage(CarrierPresenceService.shareKey) private var sharesPresence = false
    @AppStorage("com.baranov.nearbyRadar") private var nearbyRadar = false
    @AppStorage(DistanceFormatter.unitStorageKey) private var distanceUnit = Locale.current.measurementSystem == .metric ? "km" : "mi"

    @State private var isSendLogsPresented = false
    @AppStorage(Analytics.consentKey) private var sharesUsageStats = true
    @State private var notificationsDeniedAlertPresented = false
    @State private var isDeleteConfirmationPresented = false
    @State private var deleteTick = 0
    @State private var deleteConfirmationText = ""

    /// The word the person has to type before "Delete Everything" works.
    private var canConfirmDelete: Bool {
        deleteConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("delete") == .orderedSame
    }

    #if DEBUG
    @State private var debugCode = ""
    @State private var debugRedeemResult: DebugRedeemResult?
    @State private var debugRedeemTick = 0

    private enum DebugRedeemResult {
        case unlocked, invalid
    }
    #endif

    private var appAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRawValue) ?? .system
    }

    private var currentLanguageDisplayName: String {
        let targetLocale = Locale(identifier: selectedLanguageCode)
        return targetLocale.localizedString(forIdentifier: selectedLanguageCode)?.capitalized(with: targetLocale)
            ?? targetLocale.localizedString(forLanguageCode: selectedLanguageCode)?.capitalized(with: targetLocale)
            ?? selectedLanguageCode
    }

    /// Turning this on actually requests notification authorization; off
    /// is an honest "don't ask on my behalf" flag (iOS permission can only
    /// be revoked in system Settings).
    private var notificationsToggleBinding: Binding<Bool> {
        Binding(
            get: { notificationsEnabled },
            set: { newValue in
                guard newValue else {
                    notificationsEnabled = false
                    return
                }
                Task { await requestNotificationAuthorization() }
            }
        )
    }

    /// The morning forecast as it would read right now, from the ram
    /// that's out (or a sample when nothing is).
    private var previewRam: Ram? {
        flockViewModel.activeRams.first { $0.status == .walking || $0.status == .grazing }
    }

    private var previewTitle: String {
        guard let ram = previewRam else { return String(localized: "12 km to Lisbon", bundle: .appLanguage, locale: .appLanguage) }
        return "\(DistanceFormatter.string(forMeters: ram.remainingSteps)) to \(ram.legDestinationCity)"
    }

    /// The morning note's chosen time as a `Date` for the picker.
    private var morningTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: morningMinutes / 60, minute: morningMinutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                morningMinutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private var previewTime: String {
        (Calendar.current.date(bySettingHour: morningMinutes / 60, minute: morningMinutes % 60, second: 0, of: Date()) ?? Date())
            .formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: .appLanguage))
    }

    private var previewMessage: String {
        let name = previewRam?.name ?? String(localized: "Your ram", bundle: .appLanguage, locale: .appLanguage)
        return String(localized: "\(name) walks when you do. Every step today counts.", bundle: .appLanguage, locale: .appLanguage)
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AppLanguagePickerView()
                } label: {
                    HStack {
                        Text("Language")
                        Spacer()
                        Text(currentLanguageDisplayName)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Appearance")
                    Picker("Appearance", selection: $appAppearanceRawValue) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.displayName).tag(appearance.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 2)

                Picker("Distance", selection: $distanceUnit) {
                    Text("Kilometers (km)").tag("km")
                    Text("Miles (mi)").tag("mi")
                }

            }

            Section {
                Toggle("Notifications", isOn: notificationsToggleBinding)
                    .tint(Color.accentColor)

                if notificationsEnabled {
                    Toggle("Morning note", isOn: $morningNoteEnabled)
                        .tint(Color.accentColor)
                    if morningNoteEnabled {
                        DatePicker("Time", selection: morningTimeBinding, displayedComponents: .hourAndMinute)
                    }
                }

                NotificationPreviewCard(title: previewTitle, message: previewMessage, time: previewTime, fill: AnyShapeStyle(Color(.tertiarySystemFill)))
                    .opacity(notificationsEnabled && morningNoteEnabled ? 1 : 0.55)
                    .animation(.easeOut(duration: 0.2), value: notificationsEnabled)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)

            } header: {
                Text("Notifications")
            } footer: {
                Text("A note when a ram arrives or goes quiet. The morning note comes once a day, at the time you choose, and only while a ram is walking.")
            }

            Section {
                Toggle("Share my location with senders", isOn: $sharesPresence)
                    .tint(Color.accentColor)
                PresencePreviewCard(
                    symbol: "location.circle",
                    title: "Your ram is near Burnaby",
                    detail: "About 1 km · updated 2 min ago",
                    showsApproximateArea: true
                )
                .opacity(sharesPresence ? 1 : 0.55)
                .animation(.easeOut(duration: 0.2), value: sharesPresence)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)


                Toggle("Show nearby senders on the map", isOn: $nearbyRadar)
                    .tint(Color.accentColor)
                PresencePreviewCard(
                    symbol: "envelope.badge",
                    title: "Someone nearby has a letter for you",
                    detail: "Tap the marker to enter their code"
                )
                .opacity(nearbyRadar ? 1 : 0.55)
                .animation(.easeOut(duration: 0.2), value: nearbyRadar)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)

            } header: {
                Text("Privacy & Nearby")
            } footer: {
                Text("Both are off until you turn them on. Sharing happens only while you carry someone's ram, and stops the moment you switch it off.")
            }

            Section {
                Toggle("Share anonymous usage stats", isOn: $sharesUsageStats)
                    .tint(Color.accentColor)
                    .onChange(of: sharesUsageStats) { _, on in
                        Task { await Analytics.shared.setEnabled(on) }
                    }
                Button { isSendLogsPresented = true } label: {
                    Label("Send logs to developer", systemImage: "envelope")
                }
                .foregroundStyle(.primary)
            } header: {
                Text("Privacy & support")
            } footer: {
                Text("Stats are counts tied to a random ID, never letter text, names or exact location. Logs stay on your phone until you send them.")
            }

            #if DEBUG
            Section {
                HStack(spacing: 12) {
                    TextField("Code", text: $debugCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { redeemDebugCode() }
                        .onChange(of: debugCode) { _, new in
                            if !new.isEmpty { debugRedeemResult = nil }
                        }

                    Button("Redeem") { redeemDebugCode() }
                        .compactGlassButton()
                        .disabled(debugCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .sensoryFeedback(trigger: debugRedeemTick) { _, _ in
                    debugRedeemResult == .unlocked ? .success : .error
                }
            } header: {
                Text("Developer")
            } footer: {
                switch debugRedeemResult {
                case .unlocked:
                    Label("Code accepted. Pasture expanded, all three ram slots are unlocked.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .invalid:
                    Label("That code isn't valid.", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                case nil:
                    Text("Debug builds only, never shows in a release build.")
                }
            }
            #endif

            Section {
                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    Label("Delete All Data & Reset", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Permanently deletes all letters, courier rams, and cryptographic keys from the Keychain, and unregisters your Shepherd ID from the relay. This action cannot be undone.")
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $isSendLogsPresented) { SendLogsSheet() }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: morningNoteEnabled) { _, _ in
            NotificationCenter.default.post(name: RamNotificationService.preferencesChanged, object: nil)
        }
        .onChange(of: morningMinutes) { _, _ in
            NotificationCenter.default.post(name: RamNotificationService.preferencesChanged, object: nil)
        }
        .onChange(of: notificationsEnabled) { _, _ in
            NotificationCenter.default.post(name: RamNotificationService.preferencesChanged, object: nil)
        }
        .alert("Delete All Data?", isPresented: $isDeleteConfirmationPresented) {
            TextField("Type delete to confirm", text: $deleteConfirmationText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Delete Everything", role: .destructive) {
                eraseEverything()
            }
            .disabled(!canConfirmDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently wipe your letters, journey passport, courier rams, and reset your Shepherd ID. This data cannot be recovered.")
        }
        .onChange(of: isDeleteConfirmationPresented) { _, isPresented in
            if !isPresented { deleteConfirmationText = "" }
        }
        .sensoryFeedback(.warning, trigger: deleteTick)
        .alert("Notifications Off", isPresented: $notificationsDeniedAlertPresented) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Baranov isn't allowed to send notifications. Turn them on in Settings if you change your mind.")
        }
    }

    /// Hands over to `AppDataEraser`, which outlives this screen: the first
    /// thing it does is replace the whole root, Settings included.
    private func eraseEverything() {
        deleteTick += 1
        let flock = flockViewModel
        Task { await AppDataEraser.shared.eraseEverything(flock: flock) }
    }

    private func requestNotificationAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            notificationsEnabled = granted
            notificationsDeniedAlertPresented = !granted
        } catch {
            notificationsEnabled = false
            notificationsDeniedAlertPresented = true
        }
    }

    #if DEBUG
    /// Debug-only cheat code. Never compiled into a release build, so it
    /// can't be reached — let alone abused — in a shipped app.
    private func redeemDebugCode() {
        let trimmed = debugCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        debugRedeemTick += 1
        guard trimmed == "NY2026" else {
            debugRedeemResult = .invalid
            return
        }
        entitlementService.debugSetPastureExpansion(true)
        debugCode = ""
        debugRedeemResult = .unlocked
    }
    #endif
}
