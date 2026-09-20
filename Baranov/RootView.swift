//
//  RootView.swift
//  Baranov
//
//  App root. There's no tab bar: Journey (the map) is the single root
//  screen, and Pasture opens over it as a modal sheet (the pawprint button
//  in Journey's toolbar) rather than being pushed — Journey's own
//  navigation stack already carries an always-on `.sheet` for its docked
//  search/tracking panel, and a second `.sheet` attached to that same
//  stack is exactly the "two presentations competing for one slot" bug
//  that once broke Look Around, so Pasture's sheet is owned here instead,
//  one level up. Swiping it down (or, on first launch, its own onboarding
//  flow) is how it's dismissed — see `JourneyView` and `PastureView`. Both
//  screens share one `FlockViewModel` instance via the environment so a
//  ram dispatched from Journey shows up in Pasture immediately, and vice
//  versa. `EntitlementService` is shared the same way and is what keeps
//  `maxAllowedRams` in sync with whatever RevenueCat says this carrier has
//  actually rented.
//
//  This is also where an AirDropped `.ram` file lands: iOS opens the app
//  and hands the file to `onOpenURL` regardless of which screen is
//  visible, so the import path lives here rather than inside `PastureView`.
//

import SwiftUI

struct RootView: View {
    @State private var flockViewModel: FlockViewModel
    @State private var entitlementService = EntitlementService()
    /// Local notifications for the four moments worth one: gate, handoff,
    /// a ram arriving from someone else, and a day of no steps.
    @State private var notificationService = RamNotificationService()
    // Shared across every screen that needs the sender's real-world
    // position (Journey's idle map dot, Pasture's trip suggestions,
    // Compose's "Starting From", the arrival ritual's stamped city) —
    // one `CLLocationManager` resolving one real fix, rather than each
    // screen spinning up its own and re-resolving independently. That
    // used to mean the map could already be showing you on it (Journey's
    // own instance resolved fine) while Compose's separate instance was
    // still stuck "finding your location" or reporting a stale denial.
    @State private var locationService = LocationService()
    private let telemetryService = TelemetryService()
    private let carrierUserId: UUID

    @State private var isCapacityPaywallPresented = false
    @State private var incomingImportErrorMessage: String?

    /// Whether Pasture's modal sheet is up — owned here (see the header
    /// doc) and handed down to `JourneyView` only so its docked panel
    /// knows to hide itself while Pasture is showing.
    @State private var isPasturePresented = false
    @State private var isCouriersPresented = false
    /// A receiving code found nearby, handed to the letter sheet that opens next.
    @State private var proximityCode: String?

    /// The ram whose wax seal is being broken from the main screen's
    /// courier dock or by tapping the ram on the map. Owned here so
    /// `LetterDetailView` is the only modal competing with Pasture for
    /// the presentation slot.
    @State private var letterRam: Ram?

    /// Coming back to the foreground is the moment to reconcile the packet
    /// schedule: a crossing runs on the wall clock, so a ship that sailed
    /// and landed while the app was closed has to be caught up on before
    /// anything is drawn.
    @Environment(\.scenePhase) private var scenePhase

    /// The Light/Dark/System preference set from Pasture's segmented
    /// picker — read here, once, at the root, and applied via
    /// `.preferredColorScheme` below. Same `@AppStorage` key as the
    /// picker itself, so the two stay in sync with no dedicated store.
    @AppStorage(AppAppearance.storageKey) private var appAppearanceRawValue = AppAppearance.system.rawValue
    private var appAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRawValue) ?? .system
    }

    /// "Shake and the ram jumps across." Lives at the root so the gesture
    /// works from any screen, exactly like the AirDrop import path above.
    @State private var shakeDetector = ShakeDetector()
    @State private var hoofbeatRelay: HoofbeatRelay

    /// The sender's own name, captured once in `OnboardingView` and
    /// reused from then on — read here only to decide whether onboarding
    /// still needs to run; `ComposeLetterView` reads the same key itself
    /// to auto-fill "Your Name".
    @AppStorage("com.baranov.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("com.baranov.carrierDisplayName") private var carrierDisplayName = ""
    @AppStorage(AppLanguagePickerView.storageKey) private var selectedLanguageCode = Locale.current.language.languageCode?.identifier ?? "en"

    private var currentLocale: Locale {
        Locale(identifier: selectedLanguageCode)
    }

    private var needsOnboarding: Bool {
        !hasCompletedOnboarding || carrierDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        // The real flock: restored from the on-disk cache (`FlockStore`)
        // so a ram three days into a walk is still three days into it
        // after a relaunch — never the illustrative `.preview` data
        // (Klaus/Calgary/Gander), which exists solely to seed SwiftUI
        // canvas previews.
        _flockViewModel = State(initialValue: FlockViewModel(store: .default))
        let userId = Self.loadOrCreateCarrierUserId()
        carrierUserId = userId
        _hoofbeatRelay = State(initialValue: HoofbeatRelay(
            carrierName: UserDefaults.standard.string(forKey: "com.baranov.carrierDisplayName") ?? "",
            installID: userId
        ))
    }

    var body: some View {
        JourneyView(
            telemetryService: telemetryService,
            carrierUserId: carrierUserId,
            isPasturePresented: $isPasturePresented,
            isCouriersPresented: $isCouriersPresented,
            letterRam: $letterRam,
            onManualHoofbeat: { triggerManualHoofbeat() }
        )
            .environment(flockViewModel)
            .environment(entitlementService)
            .environment(locationService)
            .overlay(alignment: .top) {
                HoofbeatOverlay(
                    phase: hoofbeatRelay.phase,
                    successTick: hoofbeatRelay.successTick,
                    onDismiss: { hoofbeatRelay.reset() },
                    onRetry: { triggerManualHoofbeat() }
                )
            }
            .task {
                await entitlementService.refresh()
                flockViewModel.maxAllowedRams = entitlementService.allowedRamSlots
                syncCarrierAttributes()
            }
            .task {
                startHoofbeatListening()
            }
            .task {
                await runPacketSchedule()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await tickPacketSchedule() }
            }
            .onChange(of: entitlementService.allowedRamSlots) { _, slots in
                flockViewModel.maxAllowedRams = slots
            }
            .task {
                notificationService.sync(rams: flockViewModel.activeRams)
            }
            .onChange(of: flockViewModel.activeRams) { _, rams in
                notificationService.sync(rams: rams)
            }
            .onChange(of: notificationService.tappedRamID) { _, ramID in
                guard let ramID else { return }
                flockViewModel.selectedRamId = ramID
                isPasturePresented = true
                notificationService.tappedRamID = nil
            }
            .onChange(of: flockViewModel.lettersDelivered) { _, _ in
                syncCarrierAttributes()
            }
            .onChange(of: flockViewModel.activeRams.count) { _, _ in
                syncCarrierAttributes()
            }
            .onChange(of: carrierDisplayName) { _, _ in
                syncCarrierAttributes()
            }
            .onOpenURL { url in
                guard url.scheme?.caseInsensitiveCompare("baranov") != .orderedSame else { return }
                Task { await receiveTransitFile(at: url) }
            }
            .sheet(isPresented: $isCapacityPaywallPresented) {
                PasturePaywallView()
                    .environment(flockViewModel)
                    .environment(entitlementService)
                    .environment(\.locale, currentLocale)
                    .preferredColorScheme(appAppearance.colorScheme)
            }
            .sheet(isPresented: $isPasturePresented) {
                NavigationStack {
                    PastureView()
                }
                .presentationDragIndicator(.visible)
                .environment(flockViewModel)
                .environment(entitlementService)
                .environment(locationService)
                .environment(\.locale, currentLocale)
                .preferredColorScheme(appAppearance.colorScheme)
            }
            .sheet(isPresented: $isCouriersPresented) {
                CouriersView(onOpenLetter: { ram, code in
                    proximityCode = code
                    isCouriersPresented = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        letterRam = ram
                    }
                })
                    .presentationDragIndicator(.visible)
                    .environment(flockViewModel)
                    .environment(entitlementService)
                    .environment(locationService)
                    .environment(\.locale, currentLocale)
                    .preferredColorScheme(appAppearance.colorScheme)
            }
            .sheet(item: $letterRam, onDismiss: { proximityCode = nil }) { ram in
                LetterDetailView(ram: ram, prefilledCode: proximityCode)
                    .presentationDragIndicator(.visible)
                    .environment(flockViewModel)
                    .environment(entitlementService)
                    .environment(locationService)
                    .environment(\.locale, currentLocale)
                    .preferredColorScheme(appAppearance.colorScheme)
            }
            .alert(
                "Couldn't Receive Letter",
                isPresented: Binding(
                    get: { incomingImportErrorMessage != nil },
                    set: { isPresented in if !isPresented { incomingImportErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { incomingImportErrorMessage = nil }
            } message: {
                Text(incomingImportErrorMessage ?? "")
            }
            .environment(\.locale, currentLocale)
            .preferredColorScheme(appAppearance.colorScheme)
    }

    /// Decodes an AirDropped `RamTransitPackage` and hands it to the flock,
    /// gated by the same capacity rule as every other admission path. A
    /// file that isn't actually a Baranov package, or that arrives while
    /// the pasture is full, never crashes the app — it surfaces an alert
    /// or the paywall instead.
    private func receiveTransitFile(at url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let package = try JSONDecoder().decode(RamTransitPackage.self, from: data)

            guard flockViewModel.canImport(package) else {
                isCapacityPaywallPresented = true
                return
            }

            await flockViewModel.importPackage(
                package,
                receivedAt: locationService.currentCoordinate
            )
        } catch {
            incomingImportErrorMessage = "That AirDrop didn't look like a Baranov letter."
        }
    }

    // MARK: - Hoofbeat (shake-to-hand-off)

    /// Arms the shake gesture for the lifetime of the app session. A shake
    /// offers whichever ram is most obviously ready to travel and, at the
    /// same time, opens the gate for one coming the other way — so two
    /// people shaking together can trade rams in a single gesture.
    private func startHoofbeatListening() {
        hoofbeatRelay.onReceive = { package in
            await receiveHoofbeatPackage(package)
        }
        // A ram that has gone out over the wire must stop walking here:
        // without this the same letter would advance on both phones.
        hoofbeatRelay.onHandedOff = { ramId, carrierName in
            flockViewModel.markHandedOff(ramId: ramId, to: carrierName)
        }
        shakeDetector.onShake = { shakenAt in
            hoofbeatRelay.begin(shakenAt: shakenAt, offering: handoffCandidate())
        }
        shakeDetector.start()
    }

    /// Toolbar-button alternative to the physical shake: arms the relay
    /// with `Date()` as the shake instant and offers the same candidate a
    /// real shake would.  The wider `matchWindow` (3.5 s) gives both people
    /// enough room to tap within a few seconds of each other.
    private func triggerManualHoofbeat() {
        hoofbeatRelay.begin(shakenAt: Date(), offering: handoffCandidate())
    }

    /// The ram a shake should offer: one already waiting at a border first,
    /// then whatever is selected, then anything still in play. `nil` means
    /// this device has nothing to give and will only receive.
    private func handoffCandidate() -> RamTransitPackage? {
        // Only rams a person can actually take: one already at sea belongs
        // to the packet, and one already handed on belongs to someone
        // else — offering either would fork the letter in two.
        let rams = flockViewModel.activeRams.filter { ram in
            ram.status == .grazing || ram.status == .walking || ram.status == .waitingForHandoff
        }
        let candidate = rams.first { $0.status == .waitingForHandoff }
            ?? rams.first { $0.id == flockViewModel.selectedRamId }
            ?? rams.first

        return candidate.map { RamTransitPackage(ram: $0) }
    }

    /// Admits a ram that arrived over a hoofbeat handoff, through exactly
    /// the same capacity gate as AirDrop. Returns the ram's name for the
    /// HUD, or `nil` if the pasture was full.
    private func receiveHoofbeatPackage(_ package: RamTransitPackage) async -> String? {
        guard flockViewModel.canImport(package) else {
            isCapacityPaywallPresented = true
            return nil
        }
        await flockViewModel.importPackage(
            package,
            receivedAt: locationService.currentCoordinate
        )
        return package.ram.name
    }

    // MARK: - The packet schedule

    /// Reconciles every booked crossing against the wall clock, then books
    /// one for any ram newly stood at a port. Both are cheap no-ops when
    /// nothing is waiting or sailing.
    private func tickPacketSchedule() async {
        await flockViewModel.advanceVoyages()
        await flockViewModel.bookPendingPassages()
    }

    /// The ticker behind the packet. Deliberately a plain sleeping loop
    /// tied to the root view's lifetime rather than a `Timer`: it is
    /// cancelled with the view, it cannot outlive the app, and the
    /// crossing itself is derived from timestamps, so a missed tick only
    /// delays noticing — never the voyage.
    private func runPacketSchedule() async {
        while !Task.isCancelled {
            await tickPacketSchedule()
            try? await Task.sleep(for: .seconds(30))
        }
    }

    /// Mirrors what this carrier has actually done onto their RevenueCat
    /// customer record (subscriber attributes) — the same numbers the
    /// ACIT3855 flock-metric telemetry reports, next to the revenue they
    /// relate to. No-op until the SDK is configured.
    private func syncCarrierAttributes() {
        entitlementService.syncCarrierAttributes(
            carrierName: carrierDisplayName,
            lettersDelivered: flockViewModel.lettersDelivered,
            stepsWalked: flockViewModel.totalStepsWalked,
            activeRams: flockViewModel.activeRams.count
        )
    }

    /// A stable per-install identifier the ACIT3855 telemetry receiver
    /// groups this carrier's ram-hop/flock-metric events under. Persisted
    /// locally rather than tied to any account system (none exists yet).
    private static func loadOrCreateCarrierUserId() -> UUID {
        let key = "com.baranov.carrierUserId"
        if let stored = UserDefaults.standard.string(forKey: key), let uuid = UUID(uuidString: stored) {
            return uuid
        }
        let uuid = UUID()
        UserDefaults.standard.set(uuid.uuidString, forKey: key)
        return uuid
    }
}

#Preview {
    RootView()
}
