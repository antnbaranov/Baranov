//
//  PastureView.swift
//  Baranov
//
//  The flock: the ram selector (your obойма — one free slot, the rest
//  rented through RevenueCat) up top, a small "Settings" section for the
//  actual app-level preferences (language, appearance, notifications —
//  nothing about any one ram). Letters are no longer listed here: a
//  letter is inspected and opened from the courier dock or by tapping the
//  ram on the map (`LetterDetailView`). A full pasture surfaces the
//  "Expand the Pasture" paywall instead of silently refusing new rams —
//  same as any AirDropped letter that lands while the pasture is full.
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

import SwiftUI
import UIKit

struct PastureView: View {
    @Environment(FlockViewModel.self) private var flockViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(EntitlementService.self) private var entitlementService
    @State private var isPaywallPresented = false


    /// App-level settings — not tied to any one ram. `appAppearanceRawValue`
    /// shares its `@AppStorage` key with `RootView`, which is what actually
    /// applies it via `.preferredColorScheme`; this view just exposes the
    /// picker. `AppLanguagePickerView` owns its own storage key the same way.
    @AppStorage(AppAppearance.storageKey) private var appAppearanceRawValue = AppAppearance.system.rawValue
    @AppStorage(AppLanguagePickerView.storageKey) private var selectedLanguageCode = Locale.current.language.languageCode?.identifier ?? "en"
    @AppStorage("com.baranov.carrierDisplayName") private var carrierDisplayName = ""
    /// High-water mark for the "Full Pasture" badge — the most rams this
    /// person has ever had out at once, kept across launches.
    @AppStorage("com.baranov.mostRamsAtOnce") private var mostRamsAtOnce = 0

    @State private var gameCenterFriends: [GameCenterFriend] = []
    @State private var carrierPrefillName: String?

    @State private var carrierDirectory = KnownCarrierDirectory()
    @State private var isCarrierDirectoryPresented = false

    @State private var ramLedger = RamLedger()
    private var gameCenterService: GameCenterService { .shared }
    @State private var calendarService = CalendarTripSuggestionService()
    @Environment(LocationService.self) private var locationService

    @State private var ramCompanionStore = RamCompanionStore()

    /// The ram the big selector card and the AirDrop card below it both
    /// focus on — falls back to the first ram in the flock so both cards
    /// still show something useful before any explicit selection is made.
    private var selectedRam: Ram? {
        flockViewModel.activeRams.first { $0.id == flockViewModel.selectedRamId }
            ?? flockViewModel.activeRams.first
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
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
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
                    onSignInTapped: { gameCenterService.signIn() }
                )
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)

            // Footer: always the last thing on the Pasture screen.
            PastureFooterView()
        }
        .listStyle(.insetGrouped)
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
            ToolbarItem(placement: .topBarLeading) {
                dismissButton
            }
        }
        .sheet(isPresented: $isCarrierDirectoryPresented, onDismiss: { carrierPrefillName = nil }) {
            CarrierDirectoryView(
                directory: carrierDirectory,
                gameCenterService: gameCenterService,
                prefilledName: carrierPrefillName
            )
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .task {
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
        .sheet(isPresented: $isPaywallPresented) {
            PasturePaywallView()
                .environment(flockViewModel)
                .environment(entitlementService)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .environment(\.locale, Locale(identifier: selectedLanguageCode))
    }

    /// Renames a ram in the flock and carries its ledger entry across.
    private func renameRam(_ ram: Ram, to newName: String) {
        guard let index = flockViewModel.activeRams.firstIndex(where: { $0.id == ram.id }) else { return }
        let oldName = flockViewModel.activeRams[index].name
        guard oldName != newName else { return }
        flockViewModel.activeRams[index].name = newName
        ramLedger.rename(from: oldName, to: newName)
    }

    /// Standard sheet dismiss control: the system close button on iOS 26,
    /// an `xmark` on earlier releases.
    @ViewBuilder
    private var dismissButton: some View {
        if #available(iOS 26.0, *) {
            Button(role: .close) { dismiss() }
        } else {
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Close")
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
