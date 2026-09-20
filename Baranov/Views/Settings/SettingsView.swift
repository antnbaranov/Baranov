//
//  SettingsView.swift
//  Baranov
//
//  App-level preferences as their own screen, pushed from Pasture. An
//  inset-grouped list — the same look as Pasture and Satchel. "Expand the
//  Pasture" has exactly one entry point in the app, and it is here.
//

import RevenueCatUI
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(FlockViewModel.self) private var flockViewModel
    @Environment(EntitlementService.self) private var entitlementService

    @AppStorage(AppAppearance.storageKey) private var appAppearanceRawValue = AppAppearance.system.rawValue
    @AppStorage(AppLanguagePickerView.storageKey) private var selectedLanguageCode = Locale.current.language.languageCode?.identifier ?? "en"
    @AppStorage("com.baranov.notificationsEnabled") private var notificationsEnabled = false
    @AppStorage(SealStyle.storageKey) private var sealStyleRaw = SealStyle.wax.rawValue
    @AppStorage(DistanceFormatter.unitStorageKey) private var distanceUnit = Locale.current.measurementSystem == .metric ? "km" : "mi"

    @State private var isPaywallPresented = false
    @State private var isCustomerCenterPresented = false
    @State private var notificationsDeniedAlertPresented = false

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
        guard let ram = previewRam else { return "12 km to Lisbon" }
        return "\(DistanceFormatter.string(forMeters: ram.remainingSteps)) to \(ram.legDestinationCity)"
    }

    private var previewMessage: String {
        let name = previewRam?.name ?? "Your ram"
        return "\(name) walks when you do. Every step today counts."
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

                Picker("Seal", selection: $sealStyleRaw) {
                    ForEach(SealStyle.allCases) { style in
                        Text(style.title).tag(style.rawValue)
                    }
                }
                Text("How you close and open letters. Wax Seal: press and hold the wax until it presses shut or cracks open. Tap Prompt: a simple tap does the same, if holding is awkward for you.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle("Notifications", isOn: notificationsToggleBinding)
                    .tint(.accentColor)
            }

            Section {
                NotificationPreviewCard(title: previewTitle, message: previewMessage, time: "8:30 AM")
                    .opacity(notificationsEnabled ? 1 : 0.55)
                    .animation(.easeOut(duration: 0.2), value: notificationsEnabled)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                Text("What you'll get")
            } footer: {
                Text("A morning note at 8:30 while a ram is walking, plus a nudge when one goes quiet or arrives.")
            }

            Section {
                if entitlementService.hasPastureExpansion || entitlementService.hasAdoptedRam {
                    Button {
                        if entitlementService.isLive {
                            isCustomerCenterPresented = true
                        } else {
                            isPaywallPresented = true
                        }
                    } label: {
                        HStack {
                            Text("Manage Subscription")
                            Spacer()
                            Text(entitlementService.hasPastureExpansion ? "Expanded" : "Adopted Ram")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                } else {
                    Button {
                        isPaywallPresented = true
                    } label: {
                        HStack {
                            Label("Expand the Pasture", systemImage: "plus.circle.fill")
                            Spacer()
                            Text(flockViewModel.hasFreeRamSlot ? "1 ram, free forever" : "Pasture full")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPaywallPresented) {
            PasturePaywallView()
                .environment(flockViewModel)
                .environment(entitlementService)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .presentCustomerCenter(isPresented: $isCustomerCenterPresented)
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
}
