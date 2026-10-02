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

import CoreLocation
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
    /// Letters other people addressed to this person's profile code.
    @State private var letterInbox = LetterInbox()
    @State private var presenceService: CarrierPresenceService
    @State private var recallService: RecallService
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
    /// The tracking message for a letter that just left, waiting for the
    /// screen to be free (the first-letter moment comes first).
    @State private var pendingTrackingShare: String?
    @AppStorage("com.baranov.hasSeenFirstLetterMoment") private var hasSeenFirstLetterMoment = false
    @State private var incomingImportErrorMessage: String?
    /// "Marta opened your letter" — a delivery receipt arrived.
    @State private var receiptMessage: String?

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
    /// Profile's "Open to carry" switch: while on, nearby shepherds see this phone from the main map too.
    @AppStorage("com.baranov.openToCarry") private var openToCarry = false
    @AppStorage(AppLanguagePickerView.storageKey) private var selectedLanguageCode = Locale.current.language.languageCode?.identifier ?? "en"

    private var currentLocale: Locale {
        Locale(identifier: selectedLanguageCode)
    }

    private var needsOnboarding: Bool {
        #if DEBUG
        if CommandLine.arguments.contains("-demoMode") { return false }
        #endif
        return !hasCompletedOnboarding || carrierDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        #if DEBUG
        if CommandLine.arguments.contains("-demoMode") {
            let previewModel = FlockViewModel.preview
            if CommandLine.arguments.contains("-screenshotLetterOpen") || CommandLine.arguments.contains("-screenshotLetterOpened") {
                if var ram = previewModel.activeRams.first {
                    ram.status = .delivered
                    ram.stepsWalked = ram.totalStepsRequired
                    ram.addressedToThisPhone = true
                    ram.letter = Letter(
                        senderName: "Anton",
                        recipientName: "Marta",
                        messageBody: "By the time this reaches you, the leaves will have turned. Miss you.",
                        isSealed: false,
                        receivingCode: "KLAU-SRAM"
                    )
                    previewModel.activeRams = [ram]
                }
            } else if CommandLine.arguments.contains("-screenshotLetterGate") || CommandLine.arguments.contains("-screenshotLetterArrival") {
                if var ram = previewModel.activeRams.first {
                    ram.status = .arrivedAtGate
                    ram.stepsWalked = ram.totalStepsRequired
                    ram.addressedToThisPhone = true
                    previewModel.activeRams = [ram]
                }
            }
            FlockStore.default.save(FlockStore.Snapshot(activeRams: previewModel.activeRams, selectedRamId: previewModel.selectedRamId, savedAt: Date()))
            _flockViewModel = State(initialValue: previewModel)
        } else {
            _flockViewModel = State(initialValue: FlockViewModel(store: .default))
        }
        #else
        _flockViewModel = State(initialValue: FlockViewModel(store: .default))
        #endif
        let userId = Self.loadOrCreateCarrierUserId()
        carrierUserId = userId
        let receiverURL = TelemetryService().baseURL
        relay = LetterRelayService(baseURL: receiverURL)
        _presenceService = State(initialValue: CarrierPresenceService(baseURL: receiverURL, carrierUserID: userId))
        _recallService = State(initialValue: RecallService(baseURL: receiverURL))
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
        let base = journeyContent
        let s1 = stage1(base)
        let s2 = stage2(s1)
        let s3 = stage3(s2)
        let s4 = stage4(s3)
        let s5 = stage5(s4)
        let s6 = stage6(s5)
        return s6
    }

    private var journeyContent: some View {
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
    }

    /// Modifier stage 1: split out of `body` so the type-checker handles each chunk on its own.
    private func stage1(_ content: some View) -> some View {
        content
            .environment(flockViewModel)
            .environment(letterInbox)
            .environment(presenceService)
            .environment(recallService)
            .environment(proximity)
            .environment(nearbyCouriers)
            .environment(savedCouriers)
            .environment(entitlementService)
    }

    /// Modifier stage 2: split out of `body` so the type-checker handles each chunk on its own.
    private func stage2(_ content: some View) -> some View {
        content
            .environment(locationService)
            .task { ReelOverlayWindow.shared.install() }
            .task {
                // In its own window so it shows over Profile and every other
                // sheet — that's where handovers are usually started.
                HoofbeatOverlayWindow.shared.install(
                    relay: hoofbeatRelay,
                    nearby: nearbyCouriers,
                    onRetry: { triggerManualHoofbeat() },
                    onConfirm: { confirmHandoverTap() },
                    onAccept: { request in acceptHandover(request) },
                    directionHint: { request in
                        guard let latitude = request.destinationLatitude,
                              let longitude = request.destinationLongitude else { return nil }
                        return flockViewModel.isGoingMyWay(
                            to: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                            from: locationService.currentCoordinate
                        )
                    },
                    onSuggestion: { suggestion in
                        let ram = flockViewModel.activeRams.first { $0.id == suggestion.ramID }
                        handOver(to: suggestion.courier, ram: ram)
                    }
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
    }

    /// Modifier stage 3: split out of `body` so the type-checker handles each chunk on its own.
    private func stage3(_ content: some View) -> some View {
        content
            .task(id: nearbyRadar) {
                syncNearbyRadar()
            }
            .onChange(of: nearbyCouriers.couriers) { _, couriers in
                suggestCourierMoments(couriers)
            }
            .onChange(of: nearbyCouriers.suggestion) { _, current in
                // A card was swiped away (or answered): offer the next courier worth a tap, if there is one.
                if current == nil { suggestCourierMoments(nearbyCouriers.couriers) }
            }
            .onChange(of: openToCarry) { syncNearby() }
            .onChange(of: scenePhase) { old, phase in
                syncNearbyRadar()
                if phase == .active {
                    syncNearby()
                } else {
                    nearbyCouriers.stop()
                }
                if phase == .active { Analytics.shared.track(.appOpened) }
                if phase == .active, old == .background {
                    SharingInvitation.registerSession()
                    Task { await considerSharingInvitation() }
                }
                if phase == .background {
                    Task { await Analytics.shared.flush() }
                    // Last Live Activity push before suspension: a self-running
                    // estimate, plus the "almost there" notification.
                    flockViewModel.sceneDidEnterBackground()
                }
                guard phase == .active else { return }
                flockViewModel.sceneDidBecomeActive()
                Task { await tickPacketSchedule() }
                consumePendingAppAction()
                refreshTrackedPostSoon()
            }
            .onReceive(NotificationCenter.default.publisher(for: .relayPushReceived)) { _ in
                refreshTrackedPostSoon()
            }
            .onChange(of: NotificationManager.shared.tappedLetterID) { _, letterID in
                guard let letterID else { return }
                NotificationManager.shared.tappedLetterID = nil
                if let ram = flockViewModel.activeRams.first(where: { $0.letter?.id == letterID }) {
                    letterRam = ram
                }
            }
            .task {
                consumePendingAppAction()
                syncNearby()
                #if DEBUG
                if CommandLine.arguments.contains("-screenshotLetter") || CommandLine.arguments.contains("-screenshotLetterOpen") || CommandLine.arguments.contains("-screenshotLetterOpened") || CommandLine.arguments.contains("-screenshotLetterGate") || CommandLine.arguments.contains("-screenshotLetterArrival") {
                    letterRam = flockViewModel.activeRams.first
                } else if CommandLine.arguments.contains("-screenshotPasture") || CommandLine.arguments.contains("-screenshotPassport") {
                    isPasturePresented = true
                } else if CommandLine.arguments.contains("-screenshotBag") {
                    bagRam = flockViewModel.activeRams.first
                } else if CommandLine.arguments.contains("-screenshotPaywall") {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        isCapacityPaywallPresented = true
                    }
                }
                #endif
            }
            .onChange(of: entitlementService.allowedRamSlots) { _, slots in
                flockViewModel.maxAllowedRams = slots
            }
            .task {
                notificationService.sync(rams: flockViewModel.activeRams)
            }
    }

    /// Modifier stage 4: split out of `body` so the type-checker handles each chunk on its own.
    private func stage4(_ content: some View) -> some View {
        content
            .onChange(of: flockViewModel.activeRams) { _, rams in
                notificationService.sync(rams: rams)
                // A ram that just reached its gate is reported to the post
                // office now, so the recipient is pushed without waiting.
                LetterTracker.shared.flockChanged()
                // A letter reaching this phone's gate locks name edits for 24 hours.
                NameProfile.shared.noteArrivals(in: rams)
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
            .onReceive(NotificationCenter.default.publisher(for: .importTransitFile)) { note in
                guard let url = note.object as? URL else { return }
                Task { await receiveTransitFile(at: url) }
            }
            .onOpenURL { url in
                guard url.scheme?.caseInsensitiveCompare("baranov") != .orderedSame,
                      !ExpectedLetter.isLink(url) else { return }
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
    }

    /// Modifier stage 5: split out of `body` so the type-checker handles each chunk on its own.
    private func stage5(_ content: some View) -> some View {
        content
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
            .onReceive(NotificationCenter.default.publisher(for: .letterReadyToShare)) { note in
                guard let message = note.userInfo?["message"] as? String else { return }
                pendingTrackingShare = message
                Task { @MainActor in
                    // After the compose panel hands over to the journey, and
                    // after the first-letter moment has had its chance.
                    try? await Task.sleep(for: .milliseconds(1_300))
                    presentPendingTrackingShare()
                }
            }
            .sheet(item: $firstLetterMoment, onDismiss: {
                // Opened from the celebration's button: present the
                // paywall only once that sheet is fully gone.
                if opensPaywallAfterCelebration {
                    opensPaywallAfterCelebration = false
                    isCapacityPaywallPresented = true
                } else {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        presentPendingTrackingShare()
                    }
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
    }

    /// Modifier stage 6: split out of `body` so the type-checker handles each chunk on its own.
    private func stage6(_ content: some View) -> some View {
        content
            .alert(
                "Delivered",
                isPresented: Binding(
                    get: { receiptMessage != nil },
                    set: { isPresented in if !isPresented { receiptMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { receiptMessage = nil }
            } message: {
                Text(receiptMessage ?? "")
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
        .environment(recallService)
        .environment(entitlementService)
        .environment(locationService)
        .environment(\.locale, currentLocale)
        .preferredColorScheme(appAppearance.colorScheme)
    }

    /// The letter sheet, built outside `body` so the compiler type-checks
    /// it on its own.
    private func letterDetailSheet(for ram: Ram) -> some View {
        #if DEBUG
        if CommandLine.arguments.contains("-screenshotLetterArrival") {
            return AnyView(
                LetterArrivalView(ram: ram)
                    .presentationDragIndicator(.visible)
                    .environment(flockViewModel)
                    .environment(entitlementService)
                    .environment(locationService)
                    .environment(\.locale, currentLocale)
                    .preferredColorScheme(appAppearance.colorScheme)
            )
        }
        #endif
        return AnyView(
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
        )
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

            // A delivery receipt coming home: the recipient opened it.
            if FlockViewModel.isDeliveryReceipt(package) {
                if let name = flockViewModel.applyDeliveryReceipt(package) {
                    let recipient = package.ram.letter?.recipientName ?? ""
                    receiptMessage = String(localized: "\(recipient) opened your letter. \(name)'s whole journey is in the passport now.", bundle: .appLanguage, locale: .appLanguage)
                } else {
                    incomingImportErrorMessage = String(localized: "That's a receipt for a letter this phone didn't send.", bundle: .appLanguage, locale: .appLanguage)
                }
                return
            }

            if flockViewModel.shouldDecline(package) {
                incomingImportErrorMessage = declinedNoCodeMessage
                return
            }

            guard flockViewModel.canImport(package) else {
                // Someone else's letter never needs a pen, so a full mailbag
                // is not a reason to sell one — just say so.
                if FlockViewModel.isGuestLetter(package.ram) {
                    incomingImportErrorMessage = mailbagFullMessage
                } else {
                    isCapacityPaywallPresented = true
                }
                return
            }

            await flockViewModel.importPackage(
                package,
                receivedAt: locationService.currentCoordinate
            )
        } catch {
            incomingImportErrorMessage = String(localized: "That AirDrop didn't look like a Baranov letter.", bundle: .appLanguage, locale: .appLanguage)
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
        // One courier in range: ask them directly, so their phone shows Accept / Not now and they never
        // have to shake. Otherwise listen for a shake as before.
        if let courier = soleNearbyCourier() {
            handOver(to: courier, ram: handoffRam(for: courier.name))
            return
        }
        nearbyCouriers.requestAccess {
            hoofbeatRelay.begin(shakenAt: Date(), offering: handoffCandidate())
        }
    }

    private func soleNearbyCourier() -> NearbyCourier? {
        nearbyCouriers.couriers.count == 1 ? nearbyCouriers.couriers.first : nil
    }

    /// Who "Hand Over Now" should send a request to: the courier this exchange is about, or the only one
    /// in range. `nil` when it is ambiguous — then the phones pair by tapping on both sides instead.
    private func requestTarget() -> NearbyCourier? {
        if let name = hoofbeatRelay.partnerName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
           let match = nearbyCouriers.couriers.first(where: {
               $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame
           }) {
            return match
        }
        return soleNearbyCourier()
    }

    /// Starts (or restarts) nearby discovery for the main map: always browsing, and announcing this phone
    /// only when "Open to carry" is on, so couriers appear without Profile having to be open.
    private func syncNearby() {
        let trimmed = carrierDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty
            ? String(localized: "Courier", bundle: .appLanguage, locale: .appLanguage)
            : trimmed
        if openToCarry {
            let trip = KnownCarrierDirectory().carriers.first { $0.name.hasPrefix("You (") || $0.name == name }
            nearbyCouriers.baseline = (name: name, tripCity: trip?.destinationCity ?? "", trip: trip?.destinationCoordinate)
        } else {
            nearbyCouriers.baseline = nil
        }
        nearbyCouriers.startWithBaseline()
    }

    /// The tap alternative to shaking, from the "Hand Over Now" button. While
    /// this phone is already waiting for a partner's shake it confirms that
    /// exchange (pairing by who the partner is, not by when they shook);
    /// when idle it counts as the shake itself.
    private func confirmHandoverTap() {
        switch hoofbeatRelay.phase {
        case .searching:
            if !hoofbeatRelay.isByRequest, let courier = requestTarget() {
                // Turn the wait for a shake into a request they can Accept.
                let ram = handoffRam(for: courier.name)
                hoofbeatRelay.reset()
                handOver(to: courier, ram: ram)
            } else {
                hoofbeatRelay.confirmHandover()
            }
        case .idle:
            shakeDetector.simulateShake()
        case .connecting, .exchanging, .finished, .failed:
            break
        }
    }

    /// The ram a shake should offer: one already waiting at a border first,
    /// then whatever is selected, then anything still in play. `nil` means
    /// this device has nothing to give and will only receive.
    private func handoffCandidate() -> RamTransitPackage? {
        handoffRam().map { RamTransitPackage(ram: $0) }
    }

    /// Handing over to a named courier: if you're carrying a letter that
    /// person sent, that's the one to give — handing it back to its sender
    /// is how "take it back" works with no server at all.
    private func handoffRam(for courierName: String) -> Ram? {
        let name = courierName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, let theirs = flockViewModel.guestRams.first(where: { guest in
            (guest.status == .grazing || guest.status == .walking || guest.status == .waitingForHandoff)
                && guest.letter?.senderName.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(name) == .orderedSame
        }) {
            return theirs
        }
        return handoffRam()
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
                name: courier.tripCity.isEmpty ? String(localized: "Dropped Pin", bundle: .appLanguage, locale: .appLanguage) : courier.tripCity
            )
        }
    }

    /// Tapping a courier nearby (map or Profile) and choosing "Hand over": sends that courier's phone a
    /// request they can Accept, and arms the relay with the request's token so the two phones pair without
    /// a shake. If the courier has just gone out of range, it falls back to the mutual shake.
    private var handOverAction: ((NearbyCourier) -> Void)? {
        { courier in handOver(to: courier, ram: handoffRam(for: courier.name)) }
    }

    /// Sends a courier in range a request to take `ram` (or to meet, with
    /// nothing to give), and arms the relay to pair on its token.
    private func handOver(to courier: NearbyCourier, ram: Ram?) {
        // The card shows "Connecting…" from here until the handover has really begun, which may include
        // the first-time Local Network explainer.
        nearbyCouriers.beginHandover(courierID: courier.id)
        nearbyCouriers.requestAccess { startHandover(to: courier, ram: ram) }
    }

    private func startHandover(to courier: NearbyCourier, ram: Ram?) {
        let token = String(UUID().uuidString.prefix(8))
        let trimmed = carrierDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = HandoverRequest(
            token: token,
            fromName: trimmed.isEmpty ? "Shepherd" : trimmed,
            ramName: ram?.name,
            destinationCity: ram?.targetCity,
            destinationLatitude: ram?.finalDestinationCoordinate.latitude,
            destinationLongitude: ram?.finalDestinationCoordinate.longitude,
            isDelivery: ram?.status == .arrivedAtGate
        )
        let offering = ram.map { RamTransitPackage(ram: $0) }
        if nearbyCouriers.requestHandover(to: courier.id, request: request) {
            hoofbeatRelay.begin(shakenAt: Date(), offering: offering, partnerName: courier.name,
                                pairingToken: token, awaitingAcceptance: true)
        } else {
            hoofbeatRelay.begin(shakenAt: Date(), offering: offering, partnerName: courier.name)
        }
        nearbyCouriers.handoverDidStart()
    }

    // MARK: - Couriers worth pointing out

    /// Looks at who is in range and suggests the one handover worth a tap:
    /// first a letter at its gate whose recipient is standing here, then a
    /// courier whose trip goes where one of my letters is going. Runs only
    /// on the phone, from what Multipeer already shows.
    private func suggestCourierMoments(_ couriers: [NearbyCourier]) {
        guard !couriers.isEmpty, !hoofbeatRelay.phase.isActive else { return }

        for courier in couriers {
            let name = courier.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if let atGate = flockViewModel.activeRams.first(where: { ram in
                ram.status == .arrivedAtGate
                    && ram.letter?.recipientName.trimmingCharacters(in: .whitespacesAndNewlines)
                        .caseInsensitiveCompare(name) == .orderedSame
                    && !(ram.letter.map(FlockViewModel.isAddressedToMe) ?? false)
            }) {
                if nearbyCouriers.suggest(CourierSuggestion(
                    kind: .deliver, courier: courier, ramID: atGate.id,
                    ramName: atGate.name, place: atGate.targetCity
                )) { return }
            }
        }

        for courier in couriers {
            if let going = flockViewModel.activeRams.first(where: { ram in
                (ram.status == .grazing || ram.status == .walking || ram.status == .waitingForHandoff)
                    && ram.letter != nil
                    && courier.isGoingSameWay(as: ram)
            }) {
                if nearbyCouriers.suggest(CourierSuggestion(
                    kind: .goingYourWay, courier: courier, ramID: going.id,
                    ramName: going.name,
                    place: courier.tripCity.isEmpty ? going.targetCity : courier.tripCity
                )) { return }
            }
        }
    }

    /// The courier's side: they tapped Accept on the request card. This
    /// phone only receives — accepting someone's ram never gives away one
    /// of your own.
    private func acceptHandover(_ request: HandoverRequest) {
        nearbyCouriers.dismissIncomingRequest()
        // A transfer that is already passing the satchel must not be cut.
        if case .exchanging = hoofbeatRelay.phase { return }
        // Accepting a specific request beats anything else this phone was
        // doing: `begin` ignores calls while the relay is busy, which made
        // Accept do nothing after a stale shake search or a half-open
        // connection. This phone has nothing to give, so it can always
        // start over safely.
        if hoofbeatRelay.phase.isActive { hoofbeatRelay.reset() }
        hoofbeatRelay.begin(shakenAt: Date(), offering: nil, partnerName: request.fromName,
                            pairingToken: request.token)
        DiagnosticsLog.shared.log("accepted handover from \(request.fromName)", category: "hoofbeat")
    }

    /// Admits a ram that arrived over a hoofbeat handoff, through exactly
    /// the same capacity gate as AirDrop. Returns the ram's name for the
    /// HUD, or `nil` if the pasture was full.
    private func receiveHoofbeatPackage(_ package: RamTransitPackage) async -> String? {
        if flockViewModel.shouldDecline(package) {
            incomingImportErrorMessage = declinedNoCodeMessage
            return nil
        }
        guard flockViewModel.canImport(package) else {
            if FlockViewModel.isGuestLetter(package.ram) {
                incomingImportErrorMessage = mailbagFullMessage
            } else {
                isCapacityPaywallPresented = true
            }
            return nil
        }
        await flockViewModel.importPackage(
            package,
            receivedAt: locationService.currentCoordinate
        )
        return package.ram.name
    }

    private var declinedNoCodeMessage: String {
        String(localized: "That letter was declined. It has reached its gate, but this phone doesn't have its code, so it can't be opened here.", bundle: .appLanguage, locale: .appLanguage)
    }

    private var mailbagFullMessage: String {
        String(localized: "Your mailbag already holds \(FlockViewModel.maxGuests) letters for other people. Deliver or hand one on first.", bundle: .appLanguage, locale: .appLanguage)
    }

    // MARK: - Relay, presence and nearby senders

    /// Once a minute while the app runs: tell the receiver where a courier
    /// carrying someone else's ram is (only if they opted in), look up where
    /// the couriers carrying MY handed-on rams are, and check whether any
    /// letter I published by code has been claimed.
    private func runRelayTicks() async {
        // No server configured: everything here is network-only, so don't
        // spin at all. The rest of the app works entirely on the phone.
        guard TelemetryService.isServerConfigured else { return }
        configureTrackedPost()
        await NotificationManager.shared.registerForRemoteIfAuthorized()
        while !Task.isCancelled {
            await recallService.tick(
                flock: flockViewModel,
                onReleased: { ramName, sender in
                    notificationService.announceTakenBack(ramName: ramName, senderName: sender)
                },
                onCameHome: { ramName in
                    notificationService.announceCameHome(ramName: ramName)
                }
            )
            await presenceService.tick(
                rams: flockViewModel.activeRams,
                myName: carrierDisplayName,
                coordinate: locationService.currentCoordinate
            )
            await letterInbox.refresh(using: relay)
            // This person's gate, and the phone's push token, under their Shepherd ID.
            GateStore.shared.adoptIfNeeded(coordinate: locationService.currentCoordinate, city: locationService.currentCityName)
            await GateStore.shared.publish(using: relay)
            await NotificationManager.shared.uploadIfPossible()
            // The tracked post: publish and report what this phone carries,
            // then follow and collect what's coming to this person.
            await LetterTracker.shared.tick()
            await ExpectedLetterStore.shared.refresh()
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// Offers the tracking link to send the recipient, once nothing else is
    /// being presented. A letter that left while the paywall was up keeps
    /// its link in the letter's own screen ("Share tracking link").
    private func presentPendingTrackingShare() {
        guard let message = pendingTrackingShare, firstLetterMoment == nil,
              !isCapacityPaywallPresented, scenePhase == .active else { return }
        pendingTrackingShare = nil
        ActivitySharer.present(items: [message])
    }

    /// Asks the relay now rather than on the next tick: the app just came to
    /// the front, or a push said something happened.
    private func refreshTrackedPostSoon() {
        guard TelemetryService.isServerConfigured else { return }
        Task {
            await LetterTracker.shared.tick()
            await ExpectedLetterStore.shared.refresh(force: true)
        }
    }

    /// Hooks the tracked post up to this session's relay and flock.
    private func configureTrackedPost() {
        LetterTracker.shared.configure(
            relay: relay,
            flock: flockViewModel,
            onCollected: { record in
                NotificationManager.shared.announce(
                    .collected, letterID: record.letterID,
                    title: String(localized: "\(record.recipientName) has your letter", bundle: .appLanguage, locale: .appLanguage),
                    body: String(localized: "It's in their mailbag now, ready to open.", bundle: .appLanguage, locale: .appLanguage)
                )
            },
            onOpened: { record in
                let ram = flockViewModel.activeRams.first { $0.letter?.id == record.letterID }
                let ramName = flockViewModel.markOpenedByRecipient(letterID: record.letterID, recipientName: record.recipientName)
                    ?? ram?.name ?? String(localized: "Your ram", bundle: .appLanguage, locale: .appLanguage)
                let isPostcard = ram?.letter.map { !$0.isEncrypted } ?? false
                NotificationManager.shared.announce(
                    .opened, letterID: record.letterID,
                    title: isPostcard
                        ? String(localized: "\(record.recipientName) read your postcard", bundle: .appLanguage, locale: .appLanguage)
                        : String(localized: "\(record.recipientName) broke the seal on your letter", bundle: .appLanguage, locale: .appLanguage),
                    body: String(localized: "\(ramName)'s journey is complete.", bundle: .appLanguage, locale: .appLanguage),
                    ramID: ram?.id
                )
            },
            onSetOut: { record, ram in
                NotificationManager.shared.announce(
                    .gateSet, letterID: record.letterID,
                    title: String(localized: "\(record.recipientName) opened your link", bundle: .appLanguage, locale: .appLanguage),
                    body: String(localized: "\(ram.name) is setting out for \(ram.targetCity).", bundle: .appLanguage, locale: .appLanguage),
                    ramID: ram.id
                )
            }
        )
        ExpectedLetterStore.shared.configure(
            relay: relay,
            isOnPhone: { letterID in
                flockViewModel.activeRams.contains { ram in
                    ram.letter?.id == letterID || ram.passengerLetters.contains { $0.id == letterID }
                }
            },
            onDelivered: { expected, package in
                await receiveRelayDelivery(package, expected: expected)
            }
        )
    }

    /// A tracked letter reached its gate and the post office handed it over:
    /// straight into the mailbag, sealed, with the key already on the phone.
    private func receiveRelayDelivery(_ package: RamTransitPackage, expected: ExpectedLetter) async -> Bool {
        guard let letter = package.ram.letter, letter.id == expected.letterID else { return false }
        if let code = expected.code {
            SealKeyVault.store(code, for: letter.id)
        }
        guard flockViewModel.canImport(package) else { return false }
        // The gate notification ("… is at the gate, hold the seal") comes
        // from `RamNotificationService.sync` as the ram appears.
        await flockViewModel.importPackage(package, receivedAt: nil, asRecipient: true)
        return true
    }

    /// Listens for a nearby sender only while the app is on screen and the
    /// person has switched Nearby on in Settings.
    private func syncNearbyRadar() {
        proximity.setRadarListening(nearbyRadar && scenePhase == .active)
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
        // Before the packet moves: a ram whose carrier has already flown
        // across goes ashore with them rather than waiting for the boat.
        if let here = locationService.currentCoordinate {
            await flockViewModel.rideAlong(carrierAt: here)
        }
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
