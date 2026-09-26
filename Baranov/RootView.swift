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
    /// The receiver's letter relay (claim codes) — same host as the telemetry.
    private let relay: LetterRelayService
    @State private var relayOutbox = RelayOutbox()
    /// Letters other people addressed to this person's profile code.
    @State private var letterInbox = LetterInbox()
    @State private var presenceService: CarrierPresenceService
    /// Passive nearby-sender discovery, on only when Settings → Nearby is.
    @State private var proximity = ProximityCodeDiscovery()
    /// Nearby couriers over Bluetooth/peer Wi-Fi — browsing runs whenever
    /// the app is active (Profile and the main map both show the result);
    /// advertising this device's own name and trip is opt-in separately
    /// (Profile's "Open to carry" toggle).
    @State private var nearbyCouriers = NearbyCourierService()
    /// Couriers met nearby and kept — saved from the map or Profile.
    @State private var savedCouriers = SavedCourierStore()
    @AppStorage("com.baranov.nearbyRadar") private var nearbyRadar = false

    @State private var isCapacityPaywallPresented = false
    /// The one-time offer to be reachable nearby (see `SharingInvitation`).
    @State private var isSharingInvitePresented = false
    /// The payoff after the very first letter leaves (see
    /// `FirstLetterCelebrationView`); shown once, ever.
    @State private var firstLetterMoment: FirstLetterMoment?
    @State private var opensPaywallAfterCelebration = false
    @AppStorage("com.baranov.hasSeenFirstLetterMoment") private var hasSeenFirstLetterMoment = false
    @State private var incomingImportErrorMessage: String?

    /// Whether Pasture's modal sheet is up — owned here (see the header
    /// doc) and handed down to `JourneyView` only so its docked panel
    /// knows to hide itself while Pasture is showing.
    @State private var isPasturePresented = false
    /// The profile sheet (identity, postal code, trips).
    @State private var isProfilePresented = false
    /// "Enter Code" (above the map) and "Send by Code" (Outgoing tab of the mailbag).
    @State private var isEnterCodePresented = false
    /// A Shepherd ID picked up from a phone nearby, handed to the compose page.
    @State private var sendToShepherdID: String?
    /// "Choose on Map" from the compose sheet's destination field, and its result.
    @State private var isDestinationPickerPresented = false
    @State private var pickedDestination: DroppedDestination?
    /// A receiving code found nearby, handed to the letter sheet that opens next.
    @State private var proximityCode: String?

    /// The ram whose wax seal is being broken from the main screen's
    /// courier dock or by tapping the ram on the map. Owned here so
    /// `LetterDetailView` is the only modal competing with Pasture for
    /// the presentation slot.
    @State private var letterRam: Ram?
    /// The ram whose bag is open — set by tapping its card in the mailbag.
    @State private var bagRam: Ram?

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
        let receiverURL = TelemetryService().baseURL
        relay = LetterRelayService(baseURL: receiverURL)
        _presenceService = State(initialValue: CarrierPresenceService(baseURL: receiverURL, carrierUserID: userId))
        _hoofbeatRelay = State(initialValue: HoofbeatRelay(
            carrierName: UserDefaults.standard.string(forKey: "com.baranov.carrierDisplayName") ?? "",
            installID: userId
        ))
    }

    /// Applies whatever an App Intent (Siri, Shortcuts, Spotlight) asked the app to show.
    private func consumePendingAppAction() {
        switch PendingAppAction.consume() {
        case .openPasture: isPasturePresented = true
        case .enterLetterCode: isEnterCodePresented = true
        case nil: break
        }
    }

    var body: some View {
        JourneyView(
            telemetryService: telemetryService,
            carrierUserId: carrierUserId,
            isPasturePresented: $isPasturePresented,
            isProfilePresented: $isProfilePresented,
            isEnterCodePresented: $isEnterCodePresented,
            sendToShepherdID: $sendToShepherdID,
            isDestinationPickerPresented: $isDestinationPickerPresented,
            pickedDestination: $pickedDestination,
            letterRam: $letterRam,
            bagRam: $bagRam,
            relay: relay,
            onOpenByCode: { ram, code in
                proximityCode = code
                letterRam = ram
            },
            onManualHoofbeat: { triggerManualHoofbeat() },
            onNearbySender: { openNearbySender() },
            onHandOverToNearby: handOverAction,
            onSendLetterToNearby: sendLetterAction
        )
            .environment(flockViewModel)
            .environment(relayOutbox)
            .environment(letterInbox)
            .environment(presenceService)
            .environment(proximity)
            .environment(nearbyCouriers)
            .environment(savedCouriers)
            .environment(entitlementService)
            .environment(locationService)
            .task { ReelOverlayWindow.shared.install() }
            .overlay(alignment: .top) {
                HoofbeatOverlay(
                    phase: hoofbeatRelay.phase,
                    successTick: hoofbeatRelay.successTick,
                    partnerName: hoofbeatRelay.partnerName,
                    onDismiss: { hoofbeatRelay.reset() },
                    onRetry: { triggerManualHoofbeat() }
                )
            }
            .task {
                // Once per launch: counts the session, then maybe offers sharing.
                SharingInvitation.registerSession()
                await considerSharingInvitation()
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
            .task {
                await runRelayTicks()
            }
            .task(id: nearbyRadar) {
                syncNearbyRadar()
            }
            .onChange(of: scenePhase) { old, phase in
                syncNearbyRadar()
                if phase == .active {
                    // Just browsing here; Profile layers in this device's
                    // own name/trip (its "Open to carry" toggle) while
                    // it's the one on screen.
                    nearbyCouriers.start(announce: nil)
                } else {
                    nearbyCouriers.stop()
                }
                if phase == .active { Analytics.shared.track(.appOpened) }
                if phase == .active, old == .background {
                    SharingInvitation.registerSession()
                    Task { await considerSharingInvitation() }
                }
                if phase == .background { Task { await Analytics.shared.flush() } }
                guard phase == .active else { return }
                Task { await tickPacketSchedule() }
                consumePendingAppAction()
            }
            .task {
                consumePendingAppAction()
                nearbyCouriers.start(announce: nil)
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
            .sheet(isPresented: $isSharingInvitePresented) {
                SharingInvitationView(
                    onTurnOn: {
                        SharingInvitation.turnOn()
                        isSharingInvitePresented = false
                    },
                    onNotNow: { isSharingInvitePresented = false }
                )
                .environment(\.locale, currentLocale)
                .preferredColorScheme(appAppearance.colorScheme)
            }
            .sheet(isPresented: $isCapacityPaywallPresented) {
                PasturePaywallView()
                    .environment(flockViewModel)
                    .environment(entitlementService)
                    .environment(\.locale, currentLocale)
                    .preferredColorScheme(appAppearance.colorScheme)
            }
            .onReceive(NotificationCenter.default.publisher(for: .firstLetterDispatched)) { note in
                guard !hasSeenFirstLetterMoment, firstLetterMoment == nil else { return }
                let info = note.userInfo ?? [:]
                let moment = FirstLetterMoment(
                    recipient: info["recipient"] as? String ?? "",
                    ramName: info["ramName"] as? String ?? "",
                    targetCity: info["targetCity"] as? String ?? "",
                    meters: info["meters"] as? Int ?? 0
                )
                hasSeenFirstLetterMoment = true
                Task { @MainActor in
                    // Let the compose panel finish handing over to the
                    // journey view before anything is presented on top.
                    try? await Task.sleep(for: .milliseconds(900))
                    firstLetterMoment = moment
                }
            }
            .sheet(item: $firstLetterMoment, onDismiss: {
                // Opened from the celebration's button: present the
                // paywall only once that sheet is fully gone.
                if opensPaywallAfterCelebration {
                    opensPaywallAfterCelebration = false
                    isCapacityPaywallPresented = true
                }
            }) { moment in
                FirstLetterCelebrationView(
                    moment: moment,
                    canUpsell: entitlementService.allowedRamSlots <= 1,
                    onExpand: { opensPaywallAfterCelebration = true }
                )
                .presentationDragIndicator(.visible)
                .environment(\.locale, currentLocale)
                .preferredColorScheme(appAppearance.colorScheme)
            }
            .sheet(isPresented: $isPasturePresented) {
                NavigationStack {
                    PastureView()
                }
                .presentationDragIndicator(.visible)
                .environment(\.dismissPasture, DismissPastureAction { isPasturePresented = false })
                .environment(flockViewModel)
                .environment(entitlementService)
                .environment(locationService)
                .environment(\.locale, currentLocale)
                .preferredColorScheme(appAppearance.colorScheme)
            }
            .sheet(isPresented: $isProfilePresented) {
                ProfileView(onHandOver: handOverAction, onSendLetter: sendLetterAction)
                    .presentationDragIndicator(.visible)
                    .environment(locationService)
                    .environment(nearbyCouriers)
                    .environment(savedCouriers)
                    .environment(\.locale, currentLocale)
                    .preferredColorScheme(appAppearance.colorScheme)
            }
            .sheet(isPresented: $isDestinationPickerPresented) {
                DestinationMapPicker { pin in
                    pickedDestination = pin
                }
                .presentationDragIndicator(.visible)
                .environment(locationService)
                .environment(\.locale, currentLocale)
                .preferredColorScheme(appAppearance.colorScheme)
            }
            .sheet(item: $bagRam) { ram in
                ramBagSheet(for: ram)
            }
            .sheet(item: $letterRam, onDismiss: { proximityCode = nil }) { ram in
                letterDetailSheet(for: ram)
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

    /// The ram's bag, built outside `body` for the same reason. The letter
    /// opens inside the bag itself, as a pushed page.
    private func ramBagSheet(for ram: Ram) -> some View {
        RamBagView(ramId: ram.id, onShakeHandoff: { triggerManualHoofbeat() })
        .presentationDragIndicator(.visible)
        .environment(flockViewModel)
        .environment(entitlementService)
        .environment(locationService)
        .environment(\.locale, currentLocale)
        .preferredColorScheme(appAppearance.colorScheme)
    }

    /// The letter sheet, built outside `body` so the compiler type-checks
    /// it on its own.
    private func letterDetailSheet(for ram: Ram) -> some View {
        LetterDetailView(
            ram: ram,
            prefilledCode: proximityCode,
            onShakeHandoff: { triggerManualHoofbeat() }
        )
        .presentationDragIndicator(.visible)
        .environment(flockViewModel)
        .environment(entitlementService)
        .environment(locationService)
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
    /// real shake would.  The `matchWindow` (4 s) gives both people
    /// enough room to tap within a few seconds of each other.
    private func triggerManualHoofbeat() {
        hoofbeatRelay.begin(shakenAt: Date(), offering: handoffCandidate())
    }

    /// The ram a shake should offer: one already waiting at a border first,
    /// then whatever is selected, then anything still in play. `nil` means
    /// this device has nothing to give and will only receive.
    private func handoffCandidate() -> RamTransitPackage? {
        handoffRam().map { RamTransitPackage(ram: $0) }
    }

    private func handoffRam() -> Ram? {
        // Only rams a person can actually take: one already at sea belongs
        // to the packet, and one already handed on belongs to someone
        // else — offering either would fork the letter in two.
        let rams = flockViewModel.activeRams.filter { ram in
            ram.status == .grazing || ram.status == .walking || ram.status == .waitingForHandoff
        }
        return rams.first { $0.status == .waitingForHandoff }
            ?? rams.first { $0.id == flockViewModel.selectedRamId }
            ?? rams.first
    }

    /// "Send a letter to <their city>": hands the courier's trip destination to Compose exactly like a map
    /// pin drop, so the destination is already filled in when the panel opens.
    private var sendLetterAction: (NearbyCourier) -> Void {
        { courier in
            guard let latitude = courier.tripLatitude, let longitude = courier.tripLongitude else { return }
            pickedDestination = DroppedDestination(
                latitude: latitude,
                longitude: longitude,
                name: courier.tripCity.isEmpty ? String(localized: "Dropped Pin") : courier.tripCity
            )
        }
    }

    /// Tapping a courier nearby (map or Profile) and choosing "Hand over": arms the same mutual-shake relay as
    /// a real shake, and the HUD names who we're waiting for. It works even with nothing to give, in which case
    /// this phone only receives.
    private var handOverAction: ((NearbyCourier) -> Void)? {
        { courier in
            hoofbeatRelay.begin(shakenAt: Date(), offering: handoffCandidate(), partnerName: courier.name)
        }
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

    // MARK: - Relay, presence and nearby senders

    /// Once a minute while the app runs: tell the receiver where a courier
    /// carrying someone else's ram is (only if they opted in), look up where
    /// the couriers carrying MY handed-on rams are, and check whether any
    /// letter I published by code has been claimed.
    private func runRelayTicks() async {
        while !Task.isCancelled {
            await presenceService.tick(
                rams: flockViewModel.activeRams,
                myName: carrierDisplayName,
                coordinate: locationService.currentCoordinate
            )
            await relayOutbox.refresh(using: relay) { letter in
                notificationService.announceLetterClaimed(recipientName: letter.recipientName, code: letter.code)
            }
            await letterInbox.refresh(using: relay)
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// Listens for a nearby sender only while the app is on screen and the
    /// person has switched Nearby on in Settings.
    private func syncNearbyRadar() {
        if nearbyRadar && scenePhase == .active {
            proximity.startListening()
        } else {
            proximity.stopListening()
        }
    }

    /// Offers nearby sharing once, when the moment is right (see
    /// `SharingInvitation`): after a few seconds of the app simply being open,
    /// with nothing else on screen.
    private func considerSharingInvitation() async {
        guard SharingInvitation.isDue else { return }
        try? await Task.sleep(for: .seconds(4))
        guard SharingInvitation.isDue, scenePhase == .active, !needsOnboarding,
              !isPasturePresented, !isProfilePresented, !isCapacityPaywallPresented,
              !isDestinationPickerPresented, firstLetterMoment == nil,
              letterRam == nil, bagRam == nil else { return }
        SharingInvitation.markAsked()
        isSharingInvitePresented = true
    }

    /// The map's nearby-sender marker was tapped. A nearby profile code means
    /// someone wants a letter from me: open the compose page with it filled in.
    /// Otherwise, if the shared code opens a letter waiting at my gate, go
    /// straight to the seal; failing that, open the code field.
    private func openNearbySender() {
        guard case .locked(let shared) = proximity.state else { return }
        if CourierCodeStore.isAddress(shared) {
            sendToShepherdID = shared
            proximity.resumeListening()
            return
        }
        let code = LetterCipher.normalize(shared)
        let match = flockViewModel.activeRams.first { ram in
            guard ram.status == .arrivedAtGate, let letter = ram.letter, letter.isEncrypted else { return false }
            return (try? LetterCipher.open(letter.sealedBody, receivingCode: code, letterID: letter.id)) != nil
        }
        if let match {
            proximityCode = shared
            letterRam = match
            proximity.resumeListening()
        } else {
            isEnterCodePresented = true
        }
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
