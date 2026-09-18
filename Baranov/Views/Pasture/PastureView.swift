//
//  PastureView.swift
//  Baranov
//
//  The flock: the ram selector (your obойма — one free slot, the rest
//  rented through RevenueCat) up top, a small "Settings" section for the
//  actual app-level preferences (language, appearance, notifications —
//  nothing about any one ram), and the actual Satchel — the letters it's
//  carrying — below that. An arrived-but-unopened letter is tapped open
//  here via the wax-seal ritual; a full pasture surfaces the "Expand the
//  Pasture" paywall instead of silently refusing new rams — same as any
//  AirDropped letter that lands while the satchel is already full.
//
//  Presented by `RootView` as a modal sheet (the pawprint button in
//  Journey's toolbar) rather than pushed — this view owns no
//  `NavigationStack` of its own; `RootView` wraps it in one so this
//  title/toolbar still render. Dismissed the ordinary sheet way (swipe
//  down), which is also why the toolbar carries only the one button it
//  still needs (Carriers) instead of a dedicated "back to map" button.
//  Manual `.ram` file import used to live here too, but it only ever
//  duplicated the automatic AirDrop/`onOpenURL` path, so it's gone.
//

import RevenueCatUI
import SwiftUI
import UIKit
import UserNotifications

struct PastureView: View {
    @Environment(FlockViewModel.self) private var flockViewModel
    @Environment(EntitlementService.self) private var entitlementService
    @Environment(\.dismiss) private var dismiss

    @State private var isPaywallPresented = false
    @State private var isCustomerCenterPresented = false
    @State private var letterRam: Ram?

    /// App-level settings — not tied to any one ram. `appAppearanceRawValue`
    /// shares its `@AppStorage` key with `RootView`, which is what actually
    /// applies it via `.preferredColorScheme`; this view just exposes the
    /// picker. `AppLanguagePickerView` owns its own storage key the same way.
    @AppStorage(AppAppearance.storageKey) private var appAppearanceRawValue = AppAppearance.system.rawValue
    @AppStorage(AppLanguagePickerView.storageKey) private var selectedLanguageCode = Locale.current.language.languageCode?.identifier ?? "en"
    @AppStorage("com.baranov.notificationsEnabled") private var notificationsEnabled = false
    /// Kilometers vs. miles for every distance readout in the app —
    /// read directly by `DistanceFormatter`, so nothing else needs to
    /// know this preference exists.
    @AppStorage(DistanceFormatter.unitStorageKey) private var distanceUnit = Locale.current.measurementSystem == .metric ? "km" : "mi"
    @AppStorage("com.baranov.carrierDisplayName") private var carrierDisplayName = ""
    /// High-water mark for the "Full Pasture" badge — the most rams this
    /// person has ever had out at once, kept across launches.
    @AppStorage("com.baranov.mostRamsAtOnce") private var mostRamsAtOnce = 0

    @State private var gameCenterFriends: [GameCenterFriend] = []
    @State private var carrierPrefillName: String?
    @State private var notificationsDeniedAlertPresented = false

    @State private var carrierDirectory = KnownCarrierDirectory()
    @State private var isCarrierDirectoryPresented = false

    @State private var ramLedger = RamLedger()
    @State private var gameCenterService = GameCenterService()
    @State private var calendarService = CalendarTripSuggestionService()
    @Environment(LocationService.self) private var locationService
    @State private var historyRam: Ram?

    @State private var ramCompanionStore = RamCompanionStore()
    @State private var isOnboardingPresented = false

    private var deliveredRams: [Ram] {
        flockViewModel.activeRams.filter { $0.status == .delivered }
    }

    /// The ram the big selector card and the AirDrop card below it both
    /// focus on — falls back to the first ram in the flock so both cards
    /// still show something useful before any explicit selection is made.
    private var selectedRam: Ram? {
        flockViewModel.activeRams.first { $0.id == flockViewModel.selectedRamId }
            ?? flockViewModel.activeRams.first
    }

    /// Names the person's own companion once one exists, rather than a
    /// generic "send your first letter" line — they already have a named,
    /// aging ram from onboarding; it just hasn't carried anything yet.
    private var emptyStateDescription: String {
        guard let companion = ramCompanionStore.companion else {
            return "Send your first letter from the Journey screen to welcome a ram to the pasture."
        }
        return "\(companion.name) is \(companion.ageDescription) and ready for a first letter — send one from the Journey screen."
    }

    /// The Satchel list's own empty-state heading — kept distinct from
    /// "no ram yet," since the person already has one (shown resting up
    /// in the selector card above); this is only ever about there being
    /// no *letters* on record yet.
    private var emptyStateTitle: String {
        guard let companion = ramCompanionStore.companion else { return "No Rams Yet" }
        return "\(companion.name) Hasn't Sent Anything Yet"
    }

    private var currentLanguageDisplayName: String {
        Locale.current.localizedString(forLanguageCode: selectedLanguageCode)?.capitalized(with: Locale.current) ?? selectedLanguageCode
    }

    /// Read locally too (not just in `RootView`) and applied again below —
    /// `.preferredColorScheme` doesn't propagate into `.sheet`/
    /// `.fullScreenCover` content across a presentation boundary, so
    /// Pasture (itself a sheet) needs its own copy to actually switch the
    /// instant the picker above changes it, rather than waiting for the
    /// sheet to be dismissed and reopened.
    private var appAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRawValue) ?? .system
    }

    /// Turning this on actually requests real notification authorization
    /// (never just flips a UI flag and pretends); turning it off can only
    /// ever mean "don't ask again on my behalf" — an already-granted OS
    /// permission can't be revoked from inside the app, only from Settings,
    /// so this stays an honest preference flag rather than claiming to
    /// control something it can't.
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

    var body: some View {
        List {
            Section {
                RamSelectorCard(
                    rams: flockViewModel.activeRams,
                    capacity: FlockViewModel.pastureCapacity,
                    unlockedSlots: flockViewModel.maxAllowedRams,
                    selectedRamId: Binding(
                        get: { flockViewModel.selectedRamId },
                        set: { flockViewModel.selectedRamId = $0 }
                    ),
                    onRentTapped: { isPaywallPresented = true },
                    onRename: { ram, newName in renameRam(ram, to: newName) },
                    ledgerEntry: { ram in ramLedger.entry(forName: ram.name) },
                    companion: ramCompanionStore.companion,
                    onRenameCompanion: { newName in ramCompanionStore.rename(to: newName) }
                )
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                AirDropSuggestionsCard(
                    ram: selectedRam,
                    matchedCarriers: selectedRam.map { carrierDirectory.matches(for: $0) } ?? [],
                    tripSuggestions: calendarService.suggestions,
                    onAddTripAsCarrier: { suggestion in addTripAsCarrier(suggestion) },
                    companionName: ramCompanionStore.companion?.name,
                    addedSuggestionIDs: addedTripSuggestionIDs,
                    friends: gameCenterFriends,
                    onFriendTapped: { friend in
                        carrierPrefillName = friend.displayName
                        isCarrierDirectoryPresented = true
                    },
                    knownCarrierCount: carrierDirectory.carriers.count,
                    onManageTapped: { isCarrierDirectoryPresented = true },
                    senderName: carrierDisplayName
                )
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                ShepherdsBoardCard(
                    experiencePoints: ramLedger.totalExperiencePoints,
                    progress: achievementProgress,
                    isAuthenticated: gameCenterService.isAuthenticated,
                    isLoading: gameCenterService.isLoadingLeaderboard,
                    topEntries: gameCenterService.topEntries,
                    localEntry: gameCenterService.localEntry,
                    totalPlayers: gameCenterService.totalPlayers,
                    onSignInTapped: { gameCenterService.authenticateIfNeeded() },
                    onOpenGameCenterTapped: { gameCenterService.presentLeaderboard() }
                )
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

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

                Picker("Appearance", selection: $appAppearanceRawValue) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Distance", selection: $distanceUnit) {
                    Text("Kilometers (km)").tag("km")
                    Text("Miles (mi)").tag("mi")
                }
                .pickerStyle(.segmented)

                Toggle("Notifications", isOn: notificationsToggleBinding)
                    .tint(.accentColor)

                if entitlementService.hasPastureExpansion || entitlementService.hasAdoptedRam {
                    // RevenueCat's Customer Center: cancel, refund,
                    // restore and change plans without leaving the app —
                    // and without any of it being hand-built here.
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
                            Text("Expand the Pasture")
                            Spacer()
                            Text("1 ram, free forever")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text("Settings")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
                    .padding(.bottom, 2)
            }

            if !deliveredRams.isEmpty {
                Section {
                    DeliveredLettersCarousel(rams: deliveredRams)
                        .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            Section {
                if flockViewModel.activeRams.isEmpty {
                    // A dynamic title (the companion's own name) needs the
                    // closure-based initializer — the plain
                    // `ContentUnavailableView(_:systemImage:description:)`
                    // convenience only accepts a `LocalizedStringKey`
                    // literal, not a `String` built at runtime.
                    ContentUnavailableView {
                        Label(emptyStateTitle, systemImage: "pawprint")
                    } description: {
                        Text(emptyStateDescription)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    // Lives here, inside the Satchel section's own empty
                    // state, rather than pinned to the bottom of the whole
                    // screen — it only appears once the person actually
                    // scrolls down to it, the same as every other row in
                    // this list, instead of sitting permanently on top of
                    // the selector/AirDrop cards above. Styled as the same
                    // two-line capsule "Let Them Graze" already uses (see
                    // `RamSelectorSlider.rentButton`) so Pasture's two
                    // action buttons read as one family instead of one
                    // being a full-width filled rectangle and the other a
                    // translucent pill.
                    HStack {
                        Spacer()
                        sendLetterButton
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(flockViewModel.activeRams) { ram in
                        RamCardView(
                            ram: ram,
                            isSelected: ram.id == flockViewModel.selectedRamId,
                            matchedCarriers: carrierDirectory.matches(for: ram),
                            onPassportTapped: { historyRam = ram },
                            onMarkHandedOff: {
                                flockViewModel.markHandedOff(ramId: ram.id, to: nil)
                            }
                        )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard ram.status == .arrivedAtGate || ram.status == .delivered else { return }
                                letterRam = ram
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            } header: {
                Text("Satchel")
            }

            if !flockViewModel.hasFreeRamSlot {
                Section {
                    Button {
                        isPaywallPresented = true
                    } label: {
                        Label("Expand the Pasture", systemImage: "plus.circle.fill")
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(appAppearance.colorScheme)
        .refreshable {
            // Pull-to-refresh: the only thing that re-queries the calendar
            // now that opening Pasture no longer does it automatically
            // every time — see `onChange(of: locationService.currentCityName)`
            // below and `CalendarTripSuggestionService`'s own cache.
            if let coordinate = locationService.currentCoordinate {
                await calendarService.refresh(near: coordinate)
            } else {
                locationService.resolveCurrentLocation()
            }
        }
        .navigationTitle("Pasture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // No more explicit "back to map" button — Pasture is a modal
            // sheet now (see the header doc), swipe-to-dismiss handles
            // that. This frees the toolbar for the one thing still worth
            // a tap: the two actions the old "Satchel" button-section used
            // to hold (manual AirDrop-file import, known-carrier directory).
            ToolbarItem(placement: .topBarTrailing) {
                // Manages `KnownCarrierDirectory` — the people this card's
                // "Heading the same way" matches and the trip chips above
                // both draw on. The one thing left worth a dedicated
                // button now that manual file import (redundant with the
                // automatic AirDrop/`onOpenURL` path) is gone.
                Button {
                    isCarrierDirectoryPresented = true
                } label: {
                    Image(systemName: "person.2")
                }
                .accessibilityLabel("Carriers")
            }
        }
        .sheet(isPresented: $isPaywallPresented) {
            PasturePaywallView()
                .environment(flockViewModel)
                .environment(entitlementService)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .presentCustomerCenter(isPresented: $isCustomerCenterPresented)
        .sheet(item: $letterRam) { ram in
            LetterArrivalView(ram: ram)
                .environment(flockViewModel)
                .environment(locationService)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .sheet(isPresented: $isCarrierDirectoryPresented, onDismiss: { carrierPrefillName = nil }) {
            CarrierDirectoryView(
                directory: carrierDirectory,
                gameCenterService: gameCenterService,
                prefilledName: carrierPrefillName
            )
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .sheet(item: $historyRam) { ram in
            RamHistoryView(ram: ram, ledgerEntry: ramLedger.entry(forName: ram.name))
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .task {
            // First time Pasture is ever opened, with no companion named
            // yet: onboard before anything else, so the person always has
            // a named, aging ram of their own — even before their first
            // letter is sent.
            if !ramCompanionStore.hasCompanion {
                isOnboardingPresented = true
            }

            // Backfill: a ram that was already `.delivered` before this
            // view existed this session (e.g. app relaunch) still needs
            // its one-time ledger credit.
            for ram in flockViewModel.activeRams {
                ramLedger.recordDeliveryIfNeeded(ram)
            }
            gameCenterService.authenticateIfNeeded()
            locationService.resolveCurrentLocation()
            mostRamsAtOnce = max(mostRamsAtOnce, flockViewModel.activeRams.filter { $0.status != .delivered }.count)
            if gameCenterService.isAuthenticated {
                await refreshGameCenter()
            }
        }
        .onChange(of: gameCenterService.isAuthenticated) { _, isAuthenticated in
            guard isAuthenticated else { return }
            Task { await refreshGameCenter() }
        }
        .fullScreenCover(isPresented: $isOnboardingPresented) {
            RamOnboardingView(store: ramCompanionStore) {
                isOnboardingPresented = false
            }
            .preferredColorScheme(appAppearance.colorScheme)
        }
        .onChange(of: locationService.currentCityName) { _, newCityName in
            // Trip suggestions need a real "home" coordinate to measure
            // distance from — wait for location to actually resolve (the
            // coordinate itself isn't Equatable in a way `.onChange` can
            // watch directly, same reason `ComposeLetterView` watches the
            // city name instead) rather than refreshing with nothing.
            //
            // Only auto-refreshes once, ever, for an install that has no
            // cached trips yet (`CalendarTripSuggestionService` persists
            // its own results now) — every other Pasture open reuses the
            // cache instead of silently re-querying EventKit and the
            // geocoder again in the background. Pull down the list to
            // refresh on purpose.
            guard calendarService.lastRefreshedAt == nil else { return }
            guard newCityName != nil, let coordinate = locationService.currentCoordinate else { return }
            Task { await calendarService.refresh(near: coordinate) }
        }
        .onChange(of: flockViewModel.activeRams) { _, newRams in
            var recordedNewDelivery = false
            for ram in newRams where ram.status == .delivered {
                if ramLedger.recordDeliveryIfNeeded(ram) {
                    recordedNewDelivery = true
                }
            }
            mostRamsAtOnce = max(mostRamsAtOnce, newRams.filter { $0.status != .delivered }.count)
            let earned = ShepherdAchievement.earned(achievementProgress)
            Task { await gameCenterService.report(earned) }

            guard recordedNewDelivery else { return }
            let totalXP = ramLedger.totalExperiencePoints
            Task {
                await gameCenterService.submitScore(totalXP)
                await gameCenterService.refreshLeaderboard()
            }
        }
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

    /// The Satchel empty state's own entry point back to Journey's docked
    /// compose panel — this screen owns no compose flow of its own (see
    /// the header doc), so tapping it is just `dismiss()`. Styled to match
    /// `RamSelectorSlider`'s "Let Them Graze" button one-for-one (same
    /// glass-on-iOS-26/thinMaterial-capsule fallback, same bigger two-line
    /// label) rather than the unrelated full-width `.borderedProminent`
    /// rectangle it used to be, so Pasture's two action buttons read as
    /// one family.
    @ViewBuilder
    private var sendLetterButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: { dismiss() }) {
                sendLetterButtonLabel
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
        } else {
            Button(action: { dismiss() }) {
                sendLetterButtonLabel
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .background(.thinMaterial, in: Capsule())
        }
    }

    private var sendLetterButtonLabel: some View {
        VStack(spacing: 4) {
            Image(systemName: "envelope.fill")
                .font(.title3)
            Text("Send a Letter")
                .font(.subheadline.weight(.semibold))
        }
    }

    /// Renames a ram in place (mutating `FlockViewModel`'s own array
    /// directly — no dedicated rename method needed there, since both
    /// `activeRams` and `Ram.name` are already mutable `var`s) and carries
    /// its lifetime ledger entry over to the new name.
    private func renameRam(_ ram: Ram, to newName: String) {
        guard let index = flockViewModel.activeRams.firstIndex(where: { $0.id == ram.id }) else { return }
        let oldName = flockViewModel.activeRams[index].name
        guard oldName != newName else { return }
        flockViewModel.activeRams[index].name = newName
        ramLedger.rename(from: oldName, to: newName)
    }

    /// Actually asks iOS for notification permission (never just flips
    /// the stored flag) — only sets `notificationsEnabled = true` if the
    /// person grants it. A denial (or an already-denied prior decision,
    /// which iOS answers instantly without re-prompting) surfaces a plain
    /// alert pointing at Settings rather than silently doing nothing.
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

    /// Friends and the board, fetched once signed in. Both best-effort.
    private func refreshGameCenter() async {
        gameCenterFriends = await gameCenterService.loadFriends()
        await gameCenterService.refreshLeaderboard()
        await gameCenterService.report(ShepherdAchievement.earned(achievementProgress))
    }

    /// Everything the badges are judged against, from the ledger (every
    /// finished journey) plus the flock (journeys still in flight) — never
    /// counting a delivered ram twice.
    private var achievementProgress: ShepherdAchievement.Progress {
        let inFlight = flockViewModel.activeRams.filter { $0.status != .delivered }
        let ledgerEntries = ramLedger.entriesByName.values
        let ledgerSteps = ledgerEntries.reduce(0) { $0 + $1.totalStepsWalked }
        let inFlightSteps = inFlight.reduce(0) { $0 + $1.journeyStepsSoFar }
        let ledgerHandoffs = ledgerEntries.reduce(0) { $0 + $1.stamps.filter { $0.kind == .handoff }.count }
        let inFlightHandoffs = inFlight.reduce(0) { $0 + $1.stamps.filter { $0.kind == .handoff }.count }
        return ShepherdAchievement.Progress(
            ramsDispatched: max(flockViewModel.activeRams.count, ramLedger.totalLettersDelivered),
            lettersDelivered: max(ramLedger.totalLettersDelivered, flockViewModel.lettersDelivered),
            metresWalked: ledgerSteps + inFlightSteps,
            handoffsMade: ledgerHandoffs + inFlightHandoffs,
            mostRamsAtOnce: mostRamsAtOnce
        )
    }

    /// Adds a calendar trip suggestion (already geocoded and distance-
    /// filtered by `CalendarTripSuggestionService`) to the known-carriers
    /// directory under your own name — the fast, tap-once alternative to
    /// typing it into `CarrierDirectoryView` by hand.
    private func addTripAsCarrier(_ suggestion: TripSuggestion) {
        carrierDirectory.add(
            name: "You (\(suggestion.title))",
            destinationCity: suggestion.displayName,
            destinationCoordinate: suggestion.coordinate
        )
    }

    /// Which trip chips already have a matching "You (<title>)" entry in
    /// the carrier directory — read back from the directory itself
    /// (the actual source of truth) rather than a separate flag that could
    /// drift from it, which is what let the checkmark forget itself
    /// whenever `AirDropSuggestionsCard` got recreated.
    private var addedTripSuggestionIDs: Set<UUID> {
        let carrierNames = Set(carrierDirectory.carriers.map(\.name))
        return Set(
            calendarService.suggestions
                .filter { carrierNames.contains("You (\($0.title))") }
                .map(\.id)
        )
    }
}

#Preview {
    NavigationStack {
        PastureView()
            .environment(FlockViewModel.preview)
            .environment(EntitlementService())
            .environment(LocationService())
    }
}
