//
//  ComposeLetterView.swift
//  Baranov
//
//  Drafts a new letter and dispatches a new ram to carry it. Picking a
//  destination is the whole entry point — the same "search first" pattern
//  Apple Maps uses for its own bottom sheet: there is no separate "open
//  the compose form" button, and there is exactly one clear ("x") button
//  visible at a time, living on whichever field it belongs to. Once a
//  destination is picked, that field collapses into a compact confirmed
//  summary chip — Apple Maps' own selected-place header, not a search bar
//  left sitting open — and the rest of the letter's fields reveal
//  themselves; tapping that chip's "x" clears it and reopens the search
//  field, collapsing the sheet back to its default state.
//
//  There's no "Starting From" or "Your Name" field in the form itself:
//  the starting city is resolved silently from the sender's real location
//  (`LocationService`) the moment a destination is picked, and the
//  sender's name is whatever was captured once in `OnboardingView` —
//  neither is ever shown or re-asked for here.
//
//  The route is resolved as a REAL, road-following driving route via
//  `RouteService` (MapKit/MKDirections) — a ram walks streets, it doesn't
//  cut a diagonal line across the map. When no drivable road connects the
//  two cities (an ocean or a border with no bridge), the ram can't cross
//  on its own: the sender must name a reachable handoff city (itself
//  picked the same way, via search), and the letter travels there first
//  to await a foreground AirDrop handoff to someone who can carry it
//  onward.
//

import CoreLocation
import CryptoKit
import SwiftUI
import UIKit

struct ComposeLetterView: View {
    /// Fires the moment a destination is first picked — this is what tells
    /// the enclosing docked panel (in `JourneyView`) to grow from its
    /// collapsed search-bar height to something that can actually show the
    /// rest of the form.
    let onDestinationSelected: () -> Void

    /// Fires when the sender backs out of a draft in progress by clearing
    /// the destination chip back to empty — tells the panel to collapse
    /// back down. There's no `\.dismiss` here: this view never owns its
    /// own presentation, it's just content inside `JourneyView`'s
    /// persistent docked sheet.
    let onCancel: () -> Void

    /// Fires after a letter went into a ram's mailbag: the panel closes and
    /// the map flies to that ram.
    var onRodeAlong: (Ram) -> Void = { _ in }

    /// The letter relay. With it, the destination can be a Shepherd ID (or an
    /// ear tag to hand over) instead of an address — see `isCodeMode`.
    var relay: LetterRelayService?

    /// A Shepherd ID handed in from elsewhere (a phone nearby): switches the
    /// destination to code mode with it filled in, then clears itself.
    var shepherdIDRequest: Binding<String?> = .constant(nil)

    /// A profile code a phone nearby is broadcasting right now. While the code field is showing and empty,
    /// it is filled in for the sender (and can be edited or cleared like any typed code).
    var nearbyProfileCode: String?

    /// Asks the owner to keep listening for nearby codes while the code field is on screen, whether or not
    /// the Settings radar is on.
    var onListenForNearbyCode: (Bool) -> Void = { _ in }

    /// Set by the enclosing docked panel (`JourneyView`) whenever the
    /// sheet itself has been dragged open past its collapsed search-bar
    /// height. Lets the rest of the compose form reveal itself the moment
    /// the sheet expands, not only once a destination has actually been
    /// picked — mirroring how dragging up Apple Maps' own directions
    /// sheet reveals the full route-planning form immediately, without
    /// waiting for the first keystroke. Defaults to `false` so previews
    /// and any other caller not wired to a real sheet still render the
    /// collapsed state by default.
    let isPanelExpanded: Bool

    /// A destination the sender dropped on the map by pressing and holding.
    /// Treated exactly like one picked from search; cleared with the chip.
    var droppedDestination: Binding<DroppedDestination?> = .constant(nil)

    /// Opens the full-screen map picker ("Choose on Map"), owned by `RootView`.
    var onChooseOnMap: () -> Void = {}

    /// The shortest detent: the destination and the first question of the
    /// form. Never expands the rest.
    var isPanelCompact = false
    /// The very smallest sheet: only the destination field, nothing under it.
    var isPanelTiny = false

    /// The trip as it will look, published for the map to draw as soon as
    /// there is a start, a destination and a ram. Cleared with the form.
    var routePreview: Binding<RoutePreview?> = .constant(nil)

    @Environment(FlockViewModel.self) private var flockViewModel
    @Environment(EntitlementService.self) private var entitlementService
    @Environment(\.openURL) private var openURL

    /// The sender's own name, captured once in `OnboardingView`. There is
    /// no field for it in this form — it's used as-is when dispatching.
    @AppStorage("com.baranov.carrierDisplayName") private var storedDisplayName = ""
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControlEnabled

    @Environment(LocationService.self) private var locationService

    /// The destination is a code, not an address. A Shepherd ID sends the
    /// letter straight to that person's mailbag; with none you get an ear tag
    /// to hand over. Either way the recipient chooses where the ram arrives,
    /// so there is no ram, route or handoff to pick here.
    @State private var isCodeMode = false
    @State private var shepherdID = ""
    @FocusState private var isShepherdIDFocused: Bool
    @State private var savedCodes = SavedRecipientCodeStore()
    @State private var isSavingCode = false
    @State private var editingSavedCode: SavedRecipientCode?
    @State private var pendingSavedCodeRemoval: SavedRecipientCode?
    @State private var isSendingByCode = false
    @State private var sentByCode: SentByCode?
    /// The recipient's profile key, when their name matches a saved Shepherd
    /// ID: the letter's ear tag is sealed to it inside the `.ram`, so only
    /// their phone opens the seal — with nothing to type. Resolved in `send()`.
    @State private var recipientPublicKey: (address: String, key: Curve25519.KeyAgreement.PublicKey)?

    /// A letter sent by Shepherd ID or ear tag whose recipient's gate isn't
    /// known yet: held, and its ram sets out as soon as it is.
    private struct SentByCode {
        let recipientName: String
        let ramName: String
        /// The tracking message to send them (the link tells the ram where to walk).
        let shareMessage: String?
        /// Sent to a Shepherd ID: their phone will say where its gate is by itself.
        let isAddressed: Bool
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private var hasShepherdID: Bool { !CourierCodeStore.address(from: shepherdID).isEmpty }
    private var shepherdIDIsValid: Bool { !hasShepherdID || CourierCodeStore.isAddress(shepherdID) }

    @State private var targetCity = ""
    @State private var targetCoordinate: CLLocationCoordinate2D?
    @State private var handoffCity = ""
    @State private var handoffCoordinate: CLLocationCoordinate2D?

    @State private var ramName = ""
    @State private var recipientName = ""
    /// "Only this name can open it": the recipient's name must match; the code alone won't open it.
    @State private var requiresNameMatch = false
    @State private var messageBody = ""
    /// The wax the letter will be sealed with — crimson for everyone,
    /// the rest with the pasture expansion (see `SealColor`).
    @State private var sealColor: SealColor = .crimson
    @State private var paper: EnvelopePaper = .cream
    /// `#RRGGBB` picked on the paper colour wheel; nil = use the preset.
    @State private var customPaperHex: String?
    private var paperStyle: PaperStyle { PaperStyle(paper: paper, customHex: customPaperHex) }
    @Environment(\.colorScheme) private var colorScheme
    /// In Dark, the default paper is drawn as the same frosted field the
    /// compose form's other fields use, so the page reads as a field.
    private var padUsesFieldLook: Bool { paper == .cream && customPaperHex == nil && colorScheme == .dark }
    @State private var messageDictationService = DictationService()

    /// How the letter is closed before it travels — the sender's one
    /// real decision about privacy, made by *doing* something rather than
    /// flipping a switch:
    ///
    /// - `.sealed`: they held the wax and the signet came down. The letter
    ///   goes out encrypted (`Letter.write`); only the recipient, with the
    ///   receiving code, can read it. The message field folds away into
    ///   a closed envelope until the seal is broken again for editing.
    /// - `.postcard`: they chose to send it open (`Letter.writeOpen`).
    ///   Plain text on the wire; whoever carries the ram can read it and
    ///   the recipient needs no code at the gate.
    ///
    /// `nil` until they choose, and Send says so.
    @State private var closure: LetterClosure?
    @State private var waxPickTick = 0
    @State private var isHoldingSeal = false
    @State private var sealBrokenTick = 0

    /// Set once a direct route fails to resolve — reveals the "Handoff
    /// City" field so the sender can name a reachable waypoint instead.
    @State private var needsHandoffCity = false

    /// The port the app picked on the sender's behalf once the direct
    /// route failed (see `HandoffGatewayService`), with its road leg
    /// already resolved — so the follow-up Send needs no second lookup.
    @State private var handoffPlan: HandoffPlan?

    /// Set when the sender taps "Change" on the auto-picked port, or when
    /// no port at all was reachable — reveals the manual search field.
    @State private var showsManualHandoffField = false

    /// Drives the button's "Finding a Port…" state while candidates are
    /// being tried.
    @State private var isPlanningHandoff = false

    @State private var isResolvingRoute = false
    /// The sender's own recent steps per day, for "about N days at your pace".
    @State private var dailySteps: Int?
    /// Send this letter in the mailbag of a ram already heading there,
    /// instead of a new ram taking a pen.
    @State private var ridesWithExistingRam = false
    @State private var resolutionError: LocalizedStringKey?
    @State private var isPasturePaywallPresented = false
    /// Every pen is taken: says plainly that the letter starts later.
    @State private var startsLaterAlertPresented = false

    // MARK: - Premium Touches (paid: Time-Capsule, Geo-Lock, Scratch-Off)

    @State private var wantsTimeLock = false
    @State private var unlockAt = Date().addingTimeInterval(3600 * 24)
    @State private var wantsGeoLock = false
    @State private var geofenceCoordinate: CLLocationCoordinate2D?
    @State private var geofenceRadiusMeters: Double = LetterGeofence.defaultRadiusMeters
    @State private var wantsScratchSecret = false
    @State private var scratchSecretText = ""

    /// The unsent letter's home (see `LetterDraft`). Composing is never
    /// blocked by the pasture being full — the ceiling is only met at the
    /// moment of "Slide to Dispatch". When it is, the whole form goes here
    /// and "Expand the Pasture" opens; the form is restored from here the
    /// next time this view appears (including right after the paywall
    /// closes with the sheet still up, since the `@State` is untouched).
    @State private var draftStore = LetterDraftStore()

    /// Shown under the slider after a dispatch was set aside for lack of
    /// a free ram — clears itself the moment a ram is free again.
    @State private var draftSavedNotice = false

    /// Falls back to these only before the sender has any real ram
    /// history yet (their very first letter ever) — once they do,
    /// `ramPickerOptions` offers those real names instead of arbitrary
    /// whimsical ones. "Custom" always stays available either way.
    private static var fallbackRamNameOptions: [String] { [
        String(localized: "Basalt", bundle: .appLanguage, locale: .appLanguage), String(localized: "Juniper", bundle: .appLanguage, locale: .appLanguage), String(localized: "Nimbus", bundle: .appLanguage, locale: .appLanguage), String(localized: "Clove", bundle: .appLanguage, locale: .appLanguage), String(localized: "Marrow", bundle: .appLanguage, locale: .appLanguage), String(localized: "Suede", bundle: .appLanguage, locale: .appLanguage), String(localized: "Thistle", bundle: .appLanguage, locale: .appLanguage), String(localized: "Ember", bundle: .appLanguage, locale: .appLanguage),
    ] }

    /// Own, self-contained lifetime record of real ram names (same
    /// `UserDefaults`-backed store `PastureView` owns its own copy of) —
    /// read-only here, just to offer real names as quick-pick chips.
    @State private var ramLedger = RamLedger()

    /// Own, self-contained copy of the person's named companion (same
    /// store `PastureView` owns) — guaranteed to exist by the time
    /// composing is possible, since onboarding runs the first time
    /// Pasture opens. Always the first (and, for most people, only) name
    /// this picker offers.
    @State private var ramCompanionStore = RamCompanionStore()

    /// Names of the rams waiting in unlocked, unused pasture slots.
    @State private var pastureSlotNames = PastureSlotNames()

    /// Quick-pick chip names for the ram picker: the sender's own real
    /// rams first — currently active ones, then every name with lifetime
    /// history, most letters delivered first — deduplicated by name. Only
    /// falls back to `fallbackRamNameOptions` when there's no real history
    /// at all yet.
    private var ramPickerOptions: [String] {
        var names: [String] = []
        var seen: Set<String> = []

        func add(_ candidate: String) {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed.lowercased()) else { return }
            seen.insert(trimmed.lowercased())
            names.append(trimmed)
        }

        // The person's own named companion always comes first — it's the
        // one guaranteed non-empty entry, from the moment onboarding runs.
        if let companionName = ramCompanionStore.companion?.name {
            add(companionName)
        }

        for ram in flockViewModel.ownRams {
            add(ram.name)
        }

        // Rams waiting in the slots "Expand the Pasture" opened up.
        let firstOpenSlot = max(flockViewModel.ownRams.count, ramCompanionStore.companion != nil && flockViewModel.ownRams.isEmpty ? 1 : 0)
        if firstOpenSlot < flockViewModel.maxAllowedRams {
            let openSlots = Array(firstOpenSlot..<flockViewModel.maxAllowedRams)
            let waiting = pastureSlotNames.names(forOpenSlots: openSlots, excluding: names)
            for slot in openSlots {
                if let name = waiting[slot] { add(name) }
            }
        }

        let historicalNames = ramLedger.entriesByName.values
            .sorted { $0.lettersDelivered > $1.lettersDelivered }
            .map(\.name)
        for name in historicalNames {
            add(name)
        }

        guard !names.isEmpty else { return Self.fallbackRamNameOptions }
        return Array(names.prefix(10))
    }

    /// A destination has actually been confirmed (picked from search
    /// suggestions) — this alone gates collapsing the destination field
    /// itself into a compact confirmed chip.
    private var isDestinationConfirmed: Bool {
        targetCoordinate != nil
    }

    /// Gates showing the rest of the compose form. True either once a
    /// destination is confirmed, or — mirroring Apple Maps' own directions
    /// sheet — the instant the docked sheet itself is dragged open past
    /// its collapsed height, so the sender sees the whole form right away
    /// instead of it waiting on their first keystroke.
    private var isExpanded: Bool {
        #if DEBUG
        if CommandLine.arguments.contains("-screenshotCompose") {
            return true
        }
        #endif
        return !isPanelCompact && isPanelExpanded
    }

    /// Every field the form is still waiting on, in the order they sit on
    /// screen — `nil` once the letter is ready. Drives the inline notice
    /// under Send, and is what `send()` checks when tapped: the button is
    /// never simply disabled with no explanation (the failure mode that
    /// left "Send" gray with nothing telling the sender why).
    ///
    /// The sender's own name is deliberately *not* a requirement here —
    /// it's captured in onboarding, not in this form, so the sender could
    /// never fix it from here; `senderName` falls back instead.
    private var missingRequirementKey: String? {
        if isCodeMode {
            if !shepherdIDIsValid { return "A Shepherd ID has 10 characters, like ABCDE-FGHJK." }
            // The sender's ram walks it, whichever way it's addressed.
            if ramName.trimmed.isEmpty { return "Choose a ram to carry it." }
        } else {
            if targetCoordinate == nil { return "Pick a destination from the suggestions." }
            // Riding with a ram already going there needs no ram of its own.
            if ramName.trimmed.isEmpty, !isRidingWithExistingRam { return "Choose a ram to carry it." }
        }
        if recipientName.trimmed.isEmpty { return "Say who the letter is for." }
        if !hasContent { return "Write a message." }
        if closure == nil { return "Hold the wax to seal the letter." }
        if !isCodeMode, !isRidingWithExistingRam, needsHandoffCity, handoffPlan == nil, handoffCoordinate == nil {
            return "Pick a handoff city from the suggestions."
        }
        return nil
    }

    /// The ram heading the same way, when it is the one picked above.
    private var hostRam: Ram? { targetCoordinate.flatMap { flockViewModel.ramHeading(to: $0) } }

    /// On by itself when the picked ram is the one going there, or when no
    /// pen is free; otherwise an offer the sender can accept.
    private var ridesByDefault: Bool {
        hostRam != nil && (isPickedRamGoingThere || !flockViewModel.hasFreeRamSlot)
    }

    private var isPickedRamGoingThere: Bool {
        guard let hostRam, !ramName.trimmed.isEmpty else { return false }
        return hostRam.name == ramName.trimmed
    }

    private var isRidingWithExistingRam: Bool {
        ridesWithExistingRam && targetCoordinate.flatMap { flockViewModel.ramHeading(to: $0) } != nil
    }

    private var missingRequirement: LocalizedStringKey? {
        missingRequirementKey.map { LocalizedStringKey($0) }
    }

    private var canSend: Bool {
        missingRequirementKey == nil
    }

    /// The name stamped on the letter as its sender. Onboarding captures
    /// it once; if that ever comes back empty (a cleared install, a
    /// skipped step), sending still works under a generic name rather
    /// than blocking the whole form on a field it doesn't contain.
    private var senderName: String {
        let trimmed = storedDisplayName.trimmed
        return trimmed.isEmpty ? String(localized: "A Shepherd", bundle: .appLanguage, locale: .appLanguage) : trimmed
    }

    /// Shown under Send while a tap is waiting on the location fix.
    @State private var isAwaitingLocation = false

    /// What a Send tap found still missing (see `missingRequirement`) —
    /// shown under the button until the form changes.
    @State private var requirementNotice: LocalizedStringKey?

    var body: some View {
        // No `NavigationStack` here: this view lives on one page of the
        // docked sheet's paged `TabView`, and a UIKit navigation bar that
        // is hidden/shown as the sheet resizes (and recycled with the
        // page) triggers "Layout requested for visible navigation bar,
        // when the top item belongs to a different navigation bar".
        // Nothing in the composer pushes a screen, so a plain header
        // that only appears once the form opens does the same job.
        VStack(spacing: 0) {
            if isExpanded {
                composeHeader
            } else if isPanelCompact || isPanelTiny {
                // The shortest sheets name their page, so it's clear what
                // the field below belongs to.
                Text("New Letter")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.top, isPanelTiny ? 16 : 8)
                    .accessibilityAddTraits(.isHeader)
            }
            composerBody
        }
    }

    /// Inline-title bar: cancel at the leading edge, "Letter" centred.
    private var composeHeader: some View {
        ZStack {
            Text("Letter")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            HStack {
                GlassCloseButton(label: "Cancel") { cancelComposing() }
                Spacer()
                if relay != nil { codeModeToggleButton }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        // Room above: the sheet's grabber sits at the very top edge and the
        // close button was pressed right up under it.
        .padding(.top, 14)
    }

    /// Switches between choosing a place and writing to someone by their Shepherd ID.
    private var codeModeToggleButton: some View {
        Button(action: toggleCodeMode) {
            Image(systemName: isCodeMode ? "mappin.and.ellipse" : "number")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .liquidGlass(in: Circle(), fallbackMaterial: .thinMaterial)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCodeMode ? "Send by address" : "Send by code")
        .accessibilityHint(isCodeMode
            ? "Go back to choosing a place on the map"
            : "Write to someone far away with their Shepherd ID, or get an ear tag to send them")
    }

    private var composerBody: some View {
        // Destination row (with its own capped, independently-scrollable
        // suggestion dropdown) and the rest of the expanded form now live
        // inside ONE shared scroll container, not a plain fixed `VStack`
        // with a separately-scrolling region only below it. The docked
        // sheet's own height is fixed (a `presentationDetents` selection,
        // further squeezed whenever the keyboard is up), and once the
        // destination field's focus alone expands the full form (see
        // `PlaceSearchField.onFocusChange`), the destination suggestions
        // and the rest of the fields are competing for that same limited
        // space at once — a plain `VStack` can't shrink to fit and just
        // clips whatever overflows, with no way to reach it. Wrapping
        // everything in one `ScrollView` means anything that doesn't fit
        // — suggestions included — is simply reachable by scrolling,
        // instead of silently disappearing off the bottom of the sheet.
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 0) {
                    if !isExpanded, relay != nil {
                        // The expanded form has the toggle in its header; the short sheet has no header,
                        // so it sits beside the destination field.
                        HStack(alignment: .top, spacing: -8) {
                            destinationRow
                            codeModeToggleButton
                                .padding(.top, isPanelTiny ? 10 : 20)
                                .padding(.trailing, 12)
                        }
                    } else {
                        destinationRow
                    }

                    if isExpanded {
                        expandedFields
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .padding(.bottom, 24)
                            .transition(.opacity)
                    } else if !isPanelTiny {
                        collapsedForm
                            .transition(.opacity)
                    }
                }
            }
            .task {
                #if DEBUG
                if CommandLine.arguments.contains("-screenshotCompose") {
                    try? await Task.sleep(for: .milliseconds(1400))
                    withAnimation(.easeInOut(duration: 0.4)) {
                        scrollProxy.scrollTo("sealSection", anchor: .bottom)
                    }
                    try? await Task.sleep(for: .milliseconds(800))
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scrollProxy.scrollTo("sealSection", anchor: .bottom)
                    }
                }
                if CommandLine.arguments.contains("-demoSealAnimation") {
                    try? await Task.sleep(for: .milliseconds(1800))
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        closure = .sealed
                    }
                }
                #endif
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    isMessageFocused = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .accessibilityLabel("Hide keyboard")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .onChange(of: ramName) { _, _ in ridesWithExistingRam = ridesByDefault }
        .onChange(of: ridesWithExistingRam) { _, rides in
            // Sending with the ram that's already going there means that ram
            // is the chosen one.
            if rides, let hostRam, ramName.trimmed != hostRam.name { ramName = hostRam.name }
        }
        .onChange(of: hostRam?.id) { _, _ in ridesWithExistingRam = ridesByDefault }
        .onChange(of: missingRequirementKey) { _, _ in
            // A "you're still missing X" notice from a Send tap clears
            // itself the moment the form changes — it shouldn't linger
            // as a stale warning under a now-complete form.
            requirementNotice = nil
        }
        .onChange(of: flockViewModel.hasFreeRamSlot) { _, hasSlot in
            // The notice promised the letter goes the moment a ram is
            // free; once one is, the promise is kept by the slider, not
            // the notice.
            if hasSlot { withAnimation { draftSavedNotice = false } }
        }
        .sheet(isPresented: $isPasturePaywallPresented) {
            PasturePaywallView()
        }
        .alert("It will start later", isPresented: $startsLaterAlertPresented) {
            Button("OK", role: .cancel) {}
            if !entitlementService.hasPastureExpansion {
                Button("Expand the Pasture") { isPasturePaywallPresented = true }
            }
        } message: {
            Text("All \(flockViewModel.maxAllowedRams) of your rams are already out. Your letter is saved exactly as written. Send it again once a ram is free and it sets off then.")
        }
        .task {
            #if DEBUG
            if CommandLine.arguments.contains("-screenshotCompose") {
                targetCity = "Frankfurt"
                targetCoordinate = CLLocationCoordinate2D(latitude: 50.1109, longitude: 8.6821)
                ramName = "Klaus"
                recipientName = "Marta"
                messageBody = "Meet me by the old fountain when the autumn leaves begin to turn."
                sealColor = .crimson
                paper = .cream
                closure = nil
                onDestinationSelected()
            }
            #endif
            restoreDraftIfNeeded()
            applyShepherdIDRequest(shepherdIDRequest.wrappedValue)
            syncRoutePreview()
        }
        .onChange(of: previewSignature) { _, _ in
            syncRoutePreview()
        }
        .onChange(of: shepherdIDRequest.wrappedValue) { _, id in
            applyShepherdIDRequest(id)
        }
        .onDisappear {
            if routePreview.wrappedValue != nil { routePreview.wrappedValue = nil }
            // This view is rebuilt whenever the docked panel switches
            // page or the sheet is re-presented (Pasture, Look Around);
            // a letter in progress is kept across that, not lost. A
            // dispatched or abandoned letter has already been cleared,
            // so this saves nothing then.
            autosaveDraftIfNeeded()
        }
        .task {
            // `currentCity`/`currentCoordinate` below read straight from
            // `LocationService` now (no more locally-mirrored `@State`
            // copy) — there is no "sync" left to race, so this task only
            // needs to kick off a resolve when nothing has landed yet.
            // (A prior version of this view kept its own `@State` mirror,
            // updated only via `.onChange(of: locationService
            // .currentCityName)`; `onChange` never fires on a view's
            // initial appearance, so any time `ComposeLetterView` was
            // recreated *after* the location had already resolved once
            // this session — e.g. composing a second letter — the mirror
            // never got seeded and `canSend` stayed permanently blocked
            // with "Couldn't find your starting location yet" stuck on
            // screen. Reading the service directly removes that failure
            // mode entirely instead of patching around its timing.)
            if locationService.currentCoordinate == nil {
                locationService.resolveCurrentLocation()
            }
        }
    }

    /// Always the sender's real, currently-known location — read live
    /// from `LocationService` rather than mirrored into local state, so
    /// there's nothing here that can fall out of sync with it.
    private var currentCity: String {
        locationService.currentCityName ?? ""
    }

    private var currentCoordinate: CLLocationCoordinate2D? {
        locationService.currentCoordinate
    }

    // MARK: - Short sheet

    /// What sits under the destination field while the sheet is short: the
    /// next step of the form, "Choose Your Ram" — not Slide to Dispatch,
    /// which can't succeed until the letter is written. "Expand" lives in
    /// the bottom strip beside the page dots (see `JourneyView`).
    private var collapsedForm: some View {
        VStack(spacing: 10) {
            if isPanelCompact {
                // The shortest size asks the form's first question; the
                // Expand hint sits under it, beside the page dots.
                ContactSuggestionField(placeholder: "Who is this for?", text: $recipientName, onAddressSelected: recipientAddressPicked)
            } else {
                fieldSection("Choose Your Ram") {
                    ramPicker
                }
                // iPad has room under the ram: the next question shows too.
                if isPad {
                    ContactSuggestionField(placeholder: "Who is this for?", text: $recipientName, onAddressSelected: recipientAddressPicked)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    /// Only settles the destination from the recipient's address when there
    /// isn't one already — a destination the sender explicitly picked should
    /// never be swapped out by tapping an address suggestion under the
    /// recipient field.
    private func recipientAddressPicked(_ addressText: String, _ coordinate: CLLocationCoordinate2D) {
        guard targetCoordinate == nil else { return }
        targetCity = addressText
        targetCoordinate = coordinate
        locationService.resolveCurrentLocation()
        onDestinationSelected()
    }

    // MARK: - Destination

    private var destinationRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            destinationField
            tripSummary
        }
        .padding(.horizontal, 20)
        // A bit more breathing room above the destination field — it sits
        // right under the sheet's own drag indicator, and 10pt read as
        // too tight against it. The shortest sheet has a title above it.
        .padding(.top, isPanelTiny ? 10 : 20)
        .padding(.bottom, isExpanded ? 6 : 0)
        .onChange(of: droppedDestination.wrappedValue) { _, pin in
            guard let pin else { return }
            applyDroppedDestination(pin)
        }
        .onAppear {
            // A pin chosen in the map picker arrives while the docked panel
            // is hidden, so this form may be created after the value was set
            // and `onChange` never sees it.
            if targetCoordinate == nil, let pin = droppedDestination.wrappedValue {
                applyDroppedDestination(pin)
            }
        }
    }

    private var destinationField: some View {
        Group {
            if isCodeMode {
                shepherdIDField
            } else if isDestinationConfirmed {
                confirmedDestinationSummary
            } else {
                PlaceSearchField(
                    placeholder: "Where is this letter going?",
                    text: $targetCity,
                    onSelect: { title, coordinate in
                        targetCity = title
                        targetCoordinate = coordinate
                        locationService.resolveCurrentLocation()
                        onDestinationSelected()
                    },
                    onClear: {
                        clearDestination()
                    },
                    onFocusChange: { focused in
                        // Expand the panel the instant the field is
                        // tapped, not just once a place is actually
                        // picked — mirrors Apple Maps' own search bar,
                        // and sidesteps the enclosing sheet's
                        // `presentationDetents` selection not always
                        // updating when the keyboard alone grows it
                        // (see `PlaceSearchField.onFocusChange`).
                        if focused {
                            onDestinationSelected()
                        }
                    },
                    onChooseOnMap: onChooseOnMap
                )
            }
        }
    }

    private func applyDroppedDestination(_ pin: DroppedDestination) {
        targetCity = pin.name
        targetCoordinate = pin.coordinate
        locationService.resolveCurrentLocation()
        onDestinationSelected()
    }

    /// A destination has already been picked — this collapses the search
    /// field into a compact confirmed-place chip, the same way Apple
    /// Maps' own search bar turns into a result header once you've tapped
    /// a place, rather than leaving an active search field sitting open
    /// above an already-expanded form.
    private var confirmedDestinationSummary: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(.red)

            // A long place name used to just clip mid-word against the
            // clear button. Letting it shrink a little first, and only
            // wrapping to a second line if it still doesn't fit, keeps
            // the clear button's alignment stable instead of the row
            // growing unpredictably tall.
            Text(targetCity)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(action: clearDestination) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear destination")
            .layoutPriority(1)
        }
        .pillFieldBackground()
    }

    // MARK: - Expanded form

    @ViewBuilder private var expandedFields: some View {
        if let sentByCode {
            codeSentCard(sentByCode)
                .padding(.top, 14)
        } else {
            expandedFormFields
        }
    }

    private var expandedFormFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            fieldSection("Choose Your Ram") {
                ramPicker
            }
            .padding(.top, 14)

            fieldSection(nil) {
                VStack(spacing: 10) {
                    ContactSuggestionField(placeholder: "Who is this for?", text: $recipientName, onAddressSelected: recipientAddressPicked)
                    if closure != .postcard, !recipientName.trimmed.isEmpty {
                        nameMatchToggle
                    }
                    if closure != .sealed {
                        messageField
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }
                }
            }

            // Paper, wax and Slide to Dispatch are always on the page —
            // sending explains anything still missing instead of hiding.
            fieldSection(nil) {
                closureSection
            }

            if needsHandoffCity, !isCodeMode {
                handoffSection
            }

            startingLocationNotice

            if let resolutionError {
                Label(resolutionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.accentColor)
            }

            if let requirementNotice {
                Label(requirementNotice, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            if isCodeMode {
                codeTicketSection
            } else {
                ticketSection
            }

            sendButton

            if draftSavedNotice {
                draftSavedRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: draftSavedNotice)
    }

    /// Words on the page or a drawing — either counts as a letter.
    private var hasContent: Bool {
        !messageBody.trimmed.isEmpty || attachedPhoto != nil
    }

    /// The letter is finished and waiting on a free ram. Says where it
    /// went and offers the paywall again without making the sender slide
    /// a second time — the slider itself has already sprung home.
    private var draftSavedRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Saved to Drafts")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Every ram in your pasture is already out. This letter is kept exactly as written and goes the moment a ram is free.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button("Expand") {
                isPasturePaywallPresented = true
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// "Slide to Dispatch": sending is a full drag across the track, not
    /// a tap — this sheet is dragged between detents constantly, and a
    /// letter going out on a mis-tap is the one thing a slow-postal app
    /// must never do. Same full-width capsule footprint the old Send
    /// button had. Still always slidable: when something's still missing,
    /// completing the slide explains what (see `send()`) and the knob
    /// comes home, instead of greying out with no reason given. While a
    /// route or location fix is being resolved the knob holds at the
    /// end with a spinner and the track says what it's waiting on. Once
    /// the ram is out, `JourneyView` shows this same slot as the live
    /// `TransitProgressStrip`.
    private var sendButton: some View {
        Group {
            if isCodeMode {
                SlideToActionControl(
                    title: "Slide to Send",
                    role: .dispatch,
                    isBusy: isSendingByCode || isAwaitingLocation,
                    busyTitle: busyTitle,
                    isReady: canSend
                ) {
                    Task { await send() }
                }
            } else if needsHandoffCity && handoffPlan != nil && !showsManualHandoffField {
                SlideToActionControl(
                    title: "Slide to Dispatch via \(handoffCity.trimmed)",
                    role: .dispatch,
                    isBusy: isResolvingRoute || isAwaitingLocation,
                    busyTitle: busyTitle,
                    isReady: canSend
                ) {
                    Task { await send() }
                }
            } else {
                SlideToActionControl(
                    title: "Slide to Dispatch",
                    role: .dispatch,
                    isBusy: isResolvingRoute || isAwaitingLocation,
                    busyTitle: busyTitle,
                    isReady: canSend
                ) {
                    Task { await send() }
                }
            }
        }
        .sensoryFeedback(.warning, trigger: sendAttemptWarningTick)
    }

    private var busyTitle: LocalizedStringKey? {
        if isAwaitingLocation {
            return "Finding Your Location…"
        } else if isSendingByCode {
            return "Sending…"
        } else if isPlanningHandoff {
            return "Finding a Port…"
        } else if isResolvingRoute {
            return "Finding a Route…"
        }
        return nil
    }

    @State private var sendAttemptWarningTick = 0

    private func fieldSection<Content: View>(_ title: LocalizedStringKey?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }

    // MARK: - Message (with dictation)

    /// A sheet of paper, not a form field. Serif type (the system's own
    /// New York), today's date and where the letter is being written, room
    /// for a real letter, and a rotating prompt for the blank-page moment.
    /// Nothing here is decoration for its own sake — every part of it is
    /// what a page you'd actually write on has.
    private var messageField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(letterDateline)
                .font(.caption2)
                .foregroundStyle(paperStyle.ink.opacity(0.5))
                .lineLimit(1)

            // The idea stays visible while writing — the model's line when
            // there is one, otherwise the next static prompt — so the
            // "Idea" button always has something to visibly change.
            nudgeBadge(museNudge ?? writingPrompts[promptIndex % writingPrompts.count])
                .id(museNudge ?? "static-\(promptIndex)")

            ZStack(alignment: .topLeading) {
                TextField("", text: $messageBody, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(3)
                    .lineLimit(6...16)
                    .foregroundStyle(paperStyle.ink)
                    .focused($isMessageFocused)
                    .accessibilityLabel("Tap here to start writing")

                // Before anyone has written a word the page would otherwise
                // be blank paper with nothing to say "write here". A quiet
                // blinking caret and a line of text invite the first tap;
                // it disappears the moment the field is focused or filled.
                if messageBody.isEmpty && !isMessageFocused {
                    writeHere
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: promptIndex)
            .animation(.easeInOut(duration: 0.2), value: isMessageFocused)
            .animation(.easeInOut(duration: 0.2), value: messageBody.isEmpty)

            if let photo = attachedPhoto {
                photoAttachment(photo)
            }

            Text(letterFooter)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(paperStyle.ink.opacity(0.5))
                .contentTransition(.numericText())
                .animation(.snappy, value: messageWordCount)

            HStack(spacing: 8) {
                Button { openDoodle() } label: {
                    Label("Draw", systemImage: "pencil.tip")
                        .frame(minHeight: 24)
                }
                .accessibilityLabel(attachedPhoto == nil ? "Draw a picture" : "Edit drawing")

                Button {
                    withAnimation { promptIndex += 1 }
                    promptTick += 1
                    Task { await refreshMuseNudge(force: true) }
                } label: {
                    Group {
                        if muse.isThinking {
                            ProgressView()
                        } else {
                            Label("Idea", systemImage: "arrow.trianglehead.2.clockwise")
                        }
                    }
                    .frame(minHeight: 24)
                }
                .accessibilityLabel("Show another writing idea")

                dictationButton

                Spacer(minLength: 0)
            }
            .compactGlassButton()

            // Paper colour lives on the sheet itself, right under
            // Draw / Idea, so the colour is chosen where it is seen.
            // Colour is part of sealing: an open postcard travels plain,
            // so it never looks dressed up as something secure.
            if closure != .postcard {
                paperPicker
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        // No stroke/border here anymore — a hard-edged rectangle around
        // a page of handwriting read as a form field, not a letter. The
        // material's own edge plus a hair more elevation while focused
        // is enough to show it's active, without a harsh outline.
        .background(
            padUsesFieldLook ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(paperStyle.color),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .animation(.easeInOut(duration: 0.25), value: paperStyle)
        .shadow(color: .black.opacity(isMessageFocused ? 0.08 : 0), radius: 10, y: 4)
        .animation(.easeInOut(duration: 0.2), value: isMessageFocused)
        .contentShape(Rectangle())
        .onTapGesture { isMessageFocused = true }
        .sensoryFeedback(.selection, trigger: promptTick)
        .task(id: museContextKey) {
            await refreshMuseNudge(force: false)
        }
        .onChange(of: messageDictationService.transcript) { _, newValue in
            guard !newValue.isEmpty else { return }
            messageBody = newValue
        }
        .fullScreenCover(isPresented: $showsDoodle) {
            if let base = doodleBase {
                DoodleEditorView(image: base, backdrop: paperStyle.color) { edited in
                    // An untouched blank sheet is no drawing at all.
                    if attachedPhoto != nil || edited !== base { attachedPhoto = edited }
                    showsDoodle = false
                } onCancel: {
                    showsDoodle = false
                }
            }
        }
    }

    /// The "write here" invitation shown on an empty, unfocused page.
    private var writeHere: some View {
        HStack(spacing: 8) {
            Group {
                if reduceMotion {
                    caret.opacity(0.8)
                } else {
                    caret.phaseAnimator([true, false]) { view, on in
                        view.opacity(on ? 0.9 : 0.15)
                    } animation: { _ in
                        .easeInOut(duration: 0.65)
                    }
                }
            }
            Text("Tap here to start writing")
                .font(.system(.body, design: .serif))
                .foregroundStyle(paperStyle.ink.opacity(0.45))
            Image(systemName: "pencil.line")
                .font(.body)
                .foregroundStyle(paperStyle.ink.opacity(0.45))
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    private var caret: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(width: 2, height: 22)
    }

    /// The optional drawing that rides with the letter.
    @State private var attachedPhoto: UIImage?
    @State private var doodleBase: UIImage?
    @State private var showsDoodle = false

    private func openDoodle() {
        doodleBase = attachedPhoto ?? UIImage.blankPaper()
        showsDoodle = true
    }

    /// The one-line spark: a quiet quote with a shuffle button.
    private func nudgeBadge(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(.subheadline, design: .serif).italic())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .transition(.opacity)
    }

    /// Styled exactly like Draw and Idea (it sits in the same row and takes
    /// that row's compact glass style); only the tint changes, to red and
    /// pulsing, while it is listening.
    private var dictationButton: some View {
        let isRecording = messageDictationService.isRecording
        return Button {
            messageDictationService.toggleRecording(appendingTo: messageBody)
        } label: {
            Label(isRecording ? "Stop" : "Dictate", systemImage: "mic.fill")
                .symbolEffect(.pulse, isActive: isRecording)
                .frame(minHeight: 24)
        }
        .tint(isRecording ? Color.red : Color.secondary)
        .animation(.easeInOut(duration: 0.2), value: isRecording)
        .accessibilityLabel("Dictate Message")
        .sensoryFeedback(isRecording ? .start : .stop, trigger: isRecording)
    }

    private func photoAttachment(_ photo: UIImage) -> some View {
        Button { openDoodle() } label: {
            Image(uiImage: photo)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button { openDoodle() } label: {
                Image(systemName: "pencil.tip.crop.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel("Draw on picture")
        }
        .overlay(alignment: .topLeading) {
            Button {
                withAnimation { attachedPhoto = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel("Remove picture")
        }
        .accessibilityLabel("Your drawing")
    }

    @FocusState private var isMessageFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var promptIndex = Int.random(in: 0..<8)
    @State private var promptTick = 0

    /// The on-device model's one-sentence nudge for *this* letter, when
    /// the device can make one (iOS 26 + Apple Intelligence). `nil` means
    /// the static prompts show, exactly as before.
    @State private var muse = LetterMuseService()
    @State private var museNudge: String?

    /// Re-asks for a nudge when who or where changes — not on every
    /// keystroke, and never with the letter's text.
    private var museContextKey: String {
        "\(recipientName.trimmed)|\(targetCity.trimmed)|\(currentCity.trimmed)"
    }

    private func refreshMuseNudge(force: Bool) async {
        guard LetterMuseService.isSupported, !targetCity.trimmed.isEmpty else {
            museNudge = nil
            return
        }
        if !force, museNudge != nil { return }
        var distance = 0
        if let from = currentCoordinate, let to = targetCoordinate {
            distance = Int(CLLocation(latitude: from.latitude, longitude: from.longitude)
                .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude)))
        }
        let context = LetterMuseService.LetterContext(
            recipientName: recipientName.trimmed,
            senderName: senderName,
            destinationCity: targetCity.trimmed,
            originCity: currentCity.trimmed,
            distanceMeters: distance,
            needsHandoff: needsHandoffCity
        )
        if let nudge = await muse.nudge(for: context) {
            withAnimation { museNudge = nudge }
        }
    }

    /// Prompts for the blank page — a nudge toward the kind of thing a
    /// slow letter is for, never a template to fill in.
    private var writingPrompts: [String] { [
        String(localized: "Tell them what the light is like where you are right now.", bundle: .appLanguage, locale: .appLanguage),
        String(localized: "Something you'd never say in a text, because it needs a whole page.", bundle: .appLanguage, locale: .appLanguage),
        String(localized: "What you were doing an hour ago, in enough detail that they can see it.", bundle: .appLanguage, locale: .appLanguage),
        String(localized: "A thing they said once that you still think about.", bundle: .appLanguage, locale: .appLanguage),
        String(localized: "By the time this reaches you, the weather will have changed. Describe today's.", bundle: .appLanguage, locale: .appLanguage),
        String(localized: "The smallest good thing that happened this week.", bundle: .appLanguage, locale: .appLanguage),
        String(localized: "Ask them one real question and leave room for the answer.", bundle: .appLanguage, locale: .appLanguage),
        String(localized: "What you'd want them to know if the ram took a year to arrive.", bundle: .appLanguage, locale: .appLanguage),
    ] }

    private var messageWordCount: Int {
        messageBody.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var letterFooter: LocalizedStringKey {
        let words = messageWordCount
        if words == 0 { return "Sealed in \(sealColor.displayName.lowercased()) wax when it goes." }
        if words == 1 { return "1 word · sealed in \(sealColor.displayName.lowercased()) wax" }
        return "\(Int64(words)) words · sealed in \(sealColor.displayName.lowercased()) wax"
    }

    /// "Burnaby, 16 September" — where and when the letter is being
    /// written, like the top-right corner of a real one.
    private var letterDateline: String {
        let date = Date().formatted(.dateTime.day().month(.wide).locale(.appLanguage))
        let place = currentCity.trimmed
        return place.isEmpty || place == String(localized: "Current Location", bundle: .appLanguage, locale: .appLanguage) ? date : "\(place), \(date)"
    }

    // MARK: - Ram picker

    /// One full-width row, the same pill surface and height as the
    /// destination chip above it and the recipient field below — the way
    /// every row in Apple Maps' directions sheet is the same shape
    /// regardless of what it holds. Tapping it opens a system `Menu` of
    /// the sender's real ram names (plus "Expand the Pasture" for anyone
    /// out of slots); the row itself always shows the current pick, so
    /// there's no separate chip strip at a different size. Rams are never
    /// renamed here — a name is stamped for a ram's whole life the moment
    /// it's born (see `RamLedger`/`RamCompanionStore`), so this menu only
    /// ever chooses among real, existing names.
    private var ramPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Menu {
                ForEach(ramPickerOptions, id: \.self) { name in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            ramName = name
                        }
                    } label: {
                        if ramName == name {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }

                Divider()

                Button {
                    isPasturePaywallPresented = true
                } label: {
                    Label("Expand the Pasture…", systemImage: "lock")
                }
            } label: {
                HStack(spacing: 10) {
                    RamPortraitView(name: ramName.trimmed, diameter: 30)

                    Text(ramRowTitle)
                        .font(.body)
                        .foregroundStyle(ramName.trimmed.isEmpty ? .secondary : .primary)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Capsule())
                // Same 46 pt row as the other pills: the portrait
                // takes the place of the padding it would otherwise add.
                .frame(minHeight: 30)
                .padding(.vertical, 8)
                .padding(.leading, 8)
                .padding(.trailing, 16)
                .background(.thinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ram")
            .accessibilityValue(ramRowTitle)
        }
        .onAppear {
            guard ramName.trimmed.isEmpty,
                  let defaultName = ramPickerOptions.first
            else { return }
            ramName = defaultName
        }
    }

    private var ramRowTitle: String {
        ramName.trimmed.isEmpty ? String(localized: "Choose a Ram", bundle: .appLanguage, locale: .appLanguage) : ramName.trimmed
    }

    // MARK: - Closing the letter (seal or postcard)

    /// The sender's own signet — the first letter of their name, pressed
    /// into the wax on both ends of the journey.
    private var monogram: String { senderName.sealMonogram }

    private var addressee: String {
        recipientName.trimmed.isEmpty ? String(localized: "the recipient", bundle: .appLanguage, locale: .appLanguage) : recipientName.trimmed
    }

    @ViewBuilder
    private var closureSection: some View {
        switch closure {
        case .none:
            sealingRitual
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .sealed:
            sealedEnvelopeCard
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
        case .postcard:
            postcardCard
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    /// The letter as a postcard on the chosen paper, a row of papers, a
    /// row of waxes, and one instruction: hold the seal.
    private var sealingRitual: some View {
        VStack(spacing: 18) {
            PostcardView(
                paper: paper,
                addressee: addressee,
                excerpt: messageBody.trimmed,
                wax: sealColor,
                monogram: monogram,
                customHex: customPaperHex,
                sealPreview: isHoldingSeal ? 1 : 0,
                hasScratchSecret: wantsScratchSecret,
                scratchSecret: scratchSecretText
            )
            .padding(.top, 4)
            .animation(.easeInOut(duration: 0.25), value: paperStyle)
            .animation(isHoldingSeal ? .linear(duration: 1.5) : .easeOut(duration: 0.25), value: isHoldingSeal)

            premiumTouchesSection

            // Two clearly separate panels. Seal: a gesture (wax colour,
            // then hold). Open: an ordinary tappable row.
            VStack(spacing: 12) {
                waxPicker

                VStack(spacing: 6) {
                    if SealStyle.resolved(voiceOver: voiceOverEnabled, switchControl: switchControlEnabled) == .prompt {
                        Button {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                closure = .sealed
                            }
                        } label: {
                            WaxSealView(wax: sealColor, monogram: monogram, diameter: 72)
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.impact(weight: .heavy), trigger: closure == .sealed)
                        .accessibilityLabel("Seal the letter")
                        Text(hasContent ? LocalizedStringKey("Tap the seal!") : "Write the letter first.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        WaxSealPressView(wax: sealColor, monogram: monogram, onHoldChange: { isHoldingSeal = $0 }) {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                closure = .sealed
                            }
                            isHoldingSeal = false
                        }
                        Text(hasContent ? LocalizedStringKey("Hold to seal") : "Write the letter first.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!hasContent)
            .opacity(hasContent ? 1 : 0.4)
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .id("sealSection")
        }
        .frame(maxWidth: .infinity)
    }

    /// Which paper the letter travels on.
    private var paperPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 4) {
            ForEach(EnvelopePaper.allCases) { option in
                let isUnlocked = option.isIncludedFree || entitlementService.hasPastureExpansion
                Button {
                    if isUnlocked {
                        withAnimation(.snappy) { paper = option; customPaperHex = nil }
                        waxPickTick += 1
                    } else {
                        isPasturePaywallPresented = true
                    }
                } label: {
                    ZStack {
                        if paper == option && customPaperHex == nil {
                            Circle().strokeBorder(.primary, lineWidth: 2).frame(width: 38, height: 38)
                        }
                        Circle()
                            .fill(option.color)
                            .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
                            .frame(width: 30, height: 30)
                            .opacity(isUnlocked ? 1 : 0.45)
                        if !isUnlocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(radius: 1)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(option.displayName))
                .accessibilityHint(isUnlocked ? "" : "Comes with Expand the Pasture")
                .accessibilityAddTraits(paper == option && customPaperHex == nil ? .isSelected : [])
            }

            // Any colour: the system colour wheel, after the stationery swatches.
            ZStack {
                if customPaperHex != nil {
                    Circle().strokeBorder(.primary, lineWidth: 2).frame(width: 38, height: 38)
                }
                ColorPicker("Paper colour", selection: Binding(
                    get: { paperStyle.color },
                    set: { customPaperHex = $0.paperHex; waxPickTick += 1 }
                ), supportsOpacity: false)
                .labelsHidden()
            }
            .frame(width: 44, height: 44)
        }
        }
        .sensoryFeedback(.selection, trigger: waxPickTick)
    }

    /// Which wax to press the signet into. Crimson comes with the app;
    /// every other colour comes with "Expand the Pasture" — a lock on the
    /// swatch says so, tapping one opens the paywall, and nothing here
    /// ever blocks sending.
    private var waxPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 4) {
            ForEach(SealColor.allCases) { wax in
                let isUnlocked = wax.isIncludedFree || entitlementService.hasPastureExpansion
                Button {
                    if isUnlocked {
                        withAnimation(.snappy) { sealColor = wax }
                        waxPickTick += 1
                    } else {
                        isPasturePaywallPresented = true
                    }
                } label: {
                    ZStack {
                        if sealColor == wax {
                            Circle()
                                .strokeBorder(.primary, lineWidth: 2)
                                .frame(width: 38, height: 38)
                        }
                        WaxBlobShape()
                            .fill(wax.color.gradient)
                            .frame(width: 28, height: 28)
                            .metallicShimmer(isActive: wax.hasShimmer)
                            .clipShape(WaxBlobShape())
                            .opacity(isUnlocked ? 1 : 0.7)
                        if !isUnlocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isUnlocked ? "\(wax.displayName) wax" : "\(wax.displayName) wax, with Expand the Pasture")
                .accessibilityAddTraits(sealColor == wax ? .isSelected : [])
            }
        }
        }
        .sensoryFeedback(.selection, trigger: waxPickTick)
    }

    /// The three paid touches, always on the page as live cards. Locked
    /// cards still play their preview; tapping one opens the paywall.
    /// Unlocked, a tap switches the touch on and opens its settings.
    @ViewBuilder
    private var premiumTouchesSection: some View {
        let isUnlocked = entitlementService.hasPastureExpansion

        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Make it unforgettable")
                    .font(.headline)
                if !isUnlocked {
                    Text("Included with Expand the Pasture")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)

            PremiumTouchCard(
                title: "Scratch-off secret",
                subtitle: "A hidden line they scratch clear after opening.",
                isUnlocked: isUnlocked,
                isOn: wantsScratchSecret,
                onTap: { togglePremiumTouch($wantsScratchSecret, isUnlocked: isUnlocked) },
                preview: { ScratchTeaserView() },
                editor: { scratchSecretEditor }
            )

            PremiumTouchCard(
                title: "Geo-lock",
                subtitle: "Only opens when they stand in the right place.",
                isUnlocked: isUnlocked,
                isOn: wantsGeoLock,
                onTap: { toggleGeoLock(isUnlocked: isUnlocked) },
                preview: {
                    GeoLockTeaserView(
                        coordinate: geofenceCoordinate ?? locationService.currentCoordinate,
                        radiusMeters: geofenceRadiusMeters
                    )
                },
                editor: { geoLockEditor }
            )

            PremiumTouchCard(
                title: "Time capsule",
                subtitle: "Stays sealed until the moment you choose.",
                isUnlocked: isUnlocked,
                isOn: wantsTimeLock,
                onTap: { togglePremiumTouch($wantsTimeLock, isUnlocked: isUnlocked) },
                preview: { CapsuleTeaserView(target: wantsTimeLock ? unlockAt : nil) },
                editor: { timeLockEditor }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func togglePremiumTouch(_ flag: Binding<Bool>, isUnlocked: Bool) {
        guard isUnlocked else {
            isPasturePaywallPresented = true
            return
        }
        withAnimation(.snappy) { flag.wrappedValue.toggle() }
    }

    private func toggleGeoLock(isUnlocked: Bool) {
        guard isUnlocked else {
            isPasturePaywallPresented = true
            return
        }
        withAnimation(.snappy) {
            wantsGeoLock.toggle()
            if wantsGeoLock, geofenceCoordinate == nil {
                geofenceCoordinate = locationService.currentCoordinate
                if geofenceCoordinate == nil { locationService.resolveCurrentLocation() }
            }
        }
    }

    /// Time capsule settings: locks decryption until a chosen moment.
    private var timeLockEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("Opens", selection: $unlockAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .font(.subheadline)
            HStack(spacing: 8) {
                Button("1 day") { unlockAt = Date().addingTimeInterval(86_400) }
                Button("1 week") { unlockAt = Date().addingTimeInterval(7 * 86_400) }
                Button("1 month") { unlockAt = Date().addingTimeInterval(30 * 86_400) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Text("The letter still arrives on foot as usual. It just won't decrypt before this moment, even with the right ear tag.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Geo-lock settings: a radius around "right here" at compose time.
    private var geoLockEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if geofenceCoordinate != nil {
                Label("Locked to your spot right now", systemImage: "mappin.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Label("Finding your location…", systemImage: "location.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .task {
                        // Polled rather than `.onChange`: `CLLocationCoordinate2D`
                        // isn't Equatable in a way `.onChange` can watch.
                        locationService.resolveCurrentLocation()
                        while geofenceCoordinate == nil, wantsGeoLock, !Task.isCancelled {
                            try? await Task.sleep(for: .milliseconds(400))
                            if let resolved = locationService.currentCoordinate {
                                geofenceCoordinate = resolved
                            }
                        }
                    }
            }
            Picker("Radius", selection: $geofenceRadiusMeters) {
                Text("50 m").tag(50.0)
                Text("100 m").tag(100.0)
                Text("250 m").tag(250.0)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
            Text(String(localized: "The ram still needs to reach \(recipientName.trimmed.isEmpty ? String(localized: "the recipient", bundle: .appLanguage, locale: .appLanguage) : recipientName.trimmed)'s city. This is a second, tighter lock on top of that, down to the exact spot.", bundle: .appLanguage, locale: .appLanguage))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Scratch-off settings. The foil itself is on the postcard above, so it is not shown twice.
    private var scratchSecretEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("A short secret line", text: $scratchSecretText, axis: .vertical)
                .lineLimit(1...3)
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onChange(of: scratchSecretText) { _, newValue in
                    if newValue.count > 120 { scratchSecretText = String(newValue.prefix(120)) }
                }
            Text("Travels sealed, alongside the letter. They scratch it clear after opening the letter, not before.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the compose form actually hands to `Letter.write`, for the
    /// three Premium Touches — `nil`/empty when a toggle is off, so an
    /// ordinary letter is completely unaffected by this section existing.
    private var composedUnlockAt: Date? { wantsTimeLock ? unlockAt : nil }

    private var composedGeofence: LetterGeofence? {
        guard wantsGeoLock, let geofenceCoordinate else { return nil }
        return LetterGeofence(coordinate: geofenceCoordinate, radiusMeters: geofenceRadiusMeters)
    }

    private var composedScratchSecret: String? {
        guard wantsScratchSecret else { return nil }
        let trimmed = scratchSecretText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The letter has gone into its envelope. The message field above is
    /// hidden while sealed. Breaking the seal is staged — cracks spread,
    /// the wax shatters, the flap swings open — and only then does the
    /// form come back for editing.
    private var sealedEnvelopeCard: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .top) {
                SealedEnvelopeView(
                    wax: sealColor,
                    monogram: monogram,
                    addressee: addressee,
                    isOpen: breakShatter,
                    width: 240,
                    showsSeal: false,
                    paper: paper,
                    customPaperHex: customPaperHex
                )
                .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 7)

                WaxSealBreakView(
                    wax: sealColor,
                    monogram: monogram,
                    diameter: 52,
                    crackProgress: breakCrack,
                    isShattering: breakShatter
                )
                .offset(y: SealedEnvelopeView.sealCenterY(width: 240) - 26)
            }
            .frame(width: 240, height: 240 * 0.62)
            .padding(.top, 4)

            Button { breakSeal() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "seal")
                        .font(.system(size: 17, weight: .medium))
                    Text("Break the seal to edit")
                        .font(.body.weight(.medium))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isBreakingSeal)
            .opacity(isBreakingSeal ? 0.5 : 1)
            .accessibilityHint("Cracks the wax so you can keep editing")
        }
        .frame(maxWidth: .infinity)
    }

    @State private var isBreakingSeal = false
    @State private var breakCrack: Double = 0
    @State private var breakShatter = false

    private func breakSeal() {
        guard !isBreakingSeal else { return }
        isBreakingSeal = true
        Task {
            let rigid = UIImpactFeedbackGenerator(style: .rigid)
            rigid.prepare()
            withAnimation(.easeIn(duration: 0.7)) { breakCrack = 1 }
            for step in 1...4 {
                try? await Task.sleep(for: .milliseconds(160))
                rigid.impactOccurred(intensity: 0.3 + 0.2 * Double(step))
            }
            withAnimation(.easeOut(duration: 0.3)) { breakShatter = true }
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            SoundEffectPlayer.shared.play(.waxCrack, volume: 0.6)
            try? await Task.sleep(for: .milliseconds(750))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { closure = nil }
            breakCrack = 0
            breakShatter = false
            isBreakingSeal = false
        }
    }

    /// No wax: the letter goes as it is.
    private var postcardCard: some View {
        VStack(spacing: 12) {
            postcardNote
            sealWithWaxRow
        }
    }

    /// Same row idiom as "Send open", but for the other choice: press the
    /// letter shut with wax after all.
    private var sealWithWaxRow: some View {
        Button {
            // Back to the sealing ritual (wax colour, then press): choosing
            // wax must never seal and send in one tap.
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                closure = nil
            }
        } label: {
            HStack(spacing: 10) {
                WaxSealView(wax: sealColor, monogram: monogram, diameter: 30)
                Text("Seal with wax")
                    .font(.body.weight(.medium))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Seal the letter with wax instead")
    }

    private var postcardNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "envelope.open.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text("Travels open")
                    .font(.subheadline.weight(.semibold))
                Text("Not encrypted. Anyone who carries the ram can read it, and \(addressee) needs no code at the gate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Handoff

    /// What happens when no road reaches the destination. Normally the
    /// app has already picked the nearest reachable port and this just
    /// explains the plan — where the ram walks, how far, and that it then
    /// waits at the dock for an AirDrop handoff — with a "Change" to name
    /// a different city. Only when no port at all could be reached (or
    /// the sender asked to change it) does the manual search field show.
    @ViewBuilder
    private var handoffSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let handoffPlan, !showsManualHandoffField {
                let ramDisplayName = ramName.trimmed.isEmpty ? String(localized: "Your Ram", bundle: .appLanguage, locale: .appLanguage) : ramName.trimmed
                let crossing = targetCoordinate.flatMap {
                    PacketShipService.estimatedCrossing(from: handoffPlan.gateway.coordinate, toward: $0)
                }

                // The whole trip, before anything is sent: walk, sail, walk.
                // So the sender knows where the water is — and when a friend
                // flying that way would help — instead of finding out at the quay.
                VStack(alignment: .leading, spacing: 12) {
                    tripRow(
                        symbol: "figure.walk",
                        title: String(localized: "Walk to \(handoffPlan.gateway.name)", bundle: .appLanguage, locale: .appLanguage),
                        detail: DistanceFormatter.string(forMeters: handoffPlan.leg.distanceMeters)
                    ) {
                        Button("Change") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showsManualHandoffField = true
                            }
                        }
                        .font(.subheadline)
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }

                    tripRow(
                        symbol: "ferry.fill",
                        title: crossing.map {
                            String(localized: "Packet to \($0.arrivalPortName)", bundle: .appLanguage, locale: .appLanguage)
                        } ?? String(localized: "Packet across the water", bundle: .appLanguage, locale: .appLanguage),
                        detail: crossing.map {
                            String(localized: "About \(Duration.seconds($0.duration).formatted(.units(allowed: [.days, .hours, .minutes], width: .wide, maximumUnitCount: 1).locale(.appLanguage)))", bundle: .appLanguage, locale: .appLanguage)
                        }
                    ) { EmptyView() }

                    tripRow(
                        symbol: "mappin.and.ellipse",
                        title: String(localized: "Walk on to \(targetCity.trimmed)", bundle: .appLanguage, locale: .appLanguage),
                        detail: nil
                    ) { EmptyView() }
                }

                Text("Know someone flying that way? Hand them \(ramDisplayName) before it sails.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                fieldSection("Handoff City") {
                    VStack(alignment: .leading, spacing: 8) {
                        PlaceSearchField(placeholder: "Handoff City", text: $handoffCity) { title, coordinate in
                            handoffCity = title
                            handoffCoordinate = coordinate
                            handoffPlan = nil
                        }

                        Text(handoffPlan == nil
                             ? String(localized: "No road reaches \(targetCity.trimmed) from here, and none of the nearby ports could be reached by road either. Name a city \(ramName.trimmed.isEmpty ? String(localized: "your ram", bundle: .appLanguage, locale: .appLanguage) : ramName.trimmed) can walk to; it will look for a crossing from there, or wait for a carrier heading onward.", bundle: .appLanguage, locale: .appLanguage)
                             : String(localized: "\(ramName.trimmed.isEmpty ? String(localized: "Your ram", bundle: .appLanguage, locale: .appLanguage) : ramName.trimmed) will walk to this city and look for a crossing from there — a scheduled packet, or anyone heading onward.", bundle: .appLanguage, locale: .appLanguage))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(handoffPlan != nil && !showsManualHandoffField ? 12 : 0)
        .background {
            if handoffPlan != nil, !showsManualHandoffField {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.thinMaterial)
            }
        }
        .transition(.opacity)
    }

    /// One stop of the trip preview: icon, what happens, how far or long.
    private func tripRow<Accessory: View>(
        symbol: String,
        title: String,
        detail: String?,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            accessory()
        }
    }

    // MARK: - Pace, sharing a ram, open on arrival

    /// Rough walking distance for the pace estimate: the resolved port leg
    /// plus the onward stretch when there's water, otherwise the straight
    /// line with a little allowance for roads.
    private var estimatedWalkMeters: Double? {
        guard let origin = currentCoordinate, let destination = targetCoordinate else { return nil }
        let from = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let to = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        if let handoffPlan, needsHandoffCity {
            let port = CLLocation(latitude: handoffPlan.gateway.coordinate.latitude,
                                  longitude: handoffPlan.gateway.coordinate.longitude)
            let onward = PacketShipService.estimatedCrossing(from: handoffPlan.gateway.coordinate, toward: destination)
                .map { _ in to.distance(from: port) * 0.25 } ?? 0
            return Double(handoffPlan.leg.distanceMeters) + onward * 1.25
        }
        return from.distance(from: to) * 1.25
    }

    private var paceDays: Int? {
        guard let dailySteps, let meters = estimatedWalkMeters, meters > 0 else { return nil }
        return WalkingPaceService.days(toWalk: meters, dailySteps: dailySteps)
    }

    @ViewBuilder
    private var tripExtrasSection: some View {
        let host = hostRam
        if host != nil {
            VStack(alignment: .leading, spacing: 12) {
                if let host {
                    // The picked ram is the one going there: it carries the
                    // letter, so the choice is made and can't be undone here.
                    Toggle(isOn: $ridesWithExistingRam) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send with \(host.name)")
                                .font(.body)
                            Text("Already going to \(host.targetCity)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(Color.wax)
                    .disabled(isPickedRamGoingThere)
                }
            }
            .task(id: targetCoordinate?.latitude) {
                if dailySteps == nil {
                    dailySteps = await WalkingPaceService.averageDailySteps()
                }
                // No pen left: sharing a ram that's going there anyway is
                // the obvious way to send, so it starts switched on.
                if host != nil, !flockViewModel.hasFreeRamSlot {
                    ridesWithExistingRam = true
                }
            }
        }
    }

    // MARK: - Route preview

    /// Changes whenever the drawn trip should: ram, start (to ~100 m),
    /// destination, port. Empty while there is nothing to draw.
    private var previewSignature: String {
        guard !isCodeMode, let destination = targetCoordinate, let origin = currentCoordinate else { return "" }
        let port = needsHandoffCity ? handoffPlan?.gateway.coordinate : nil
        return [
            ramName.trimmed,
            String(format: "%.3f,%.3f", origin.latitude, origin.longitude),
            String(format: "%.5f,%.5f", destination.latitude, destination.longitude),
            port.map { String(format: "%.4f,%.4f", $0.latitude, $0.longitude) } ?? "-"
        ].joined(separator: "|")
    }

    private func syncRoutePreview() {
        guard !isCodeMode,
              let destination = targetCoordinate,
              let origin = currentCoordinate,
              !targetCity.trimmed.isEmpty
        else {
            if routePreview.wrappedValue != nil { routePreview.wrappedValue = nil }
            return
        }
        let plan = needsHandoffCity ? handoffPlan : nil
        let next = RoutePreview(
            ramName: ramName.trimmed,
            originName: currentCity.trimmed,
            origin: origin,
            destinationName: targetCity.trimmed,
            destination: destination,
            viaName: plan?.gateway.name,
            via: plan?.gateway.coordinate
        )
        if routePreview.wrappedValue != next { routePreview.wrappedValue = next }
    }

    // MARK: - Trip summary (under the destination)

    /// Right under the place: how far, how many steps, how long — and the
    /// choice to ride along with a ram already going there. These depend on
    /// the destination, so they sit with it.
    @ViewBuilder
    private var tripSummary: some View {
        if !isCodeMode, isDestinationConfirmed, let meters = estimatedWalkMeters {
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: tripFactsLine(meters: meters, riding: isRidingWithExistingRam))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                tripExtrasSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: targetCoordinate?.latitude) {
                if dailySteps == nil {
                    dailySteps = await WalkingPaceService.averageDailySteps()
                }
            }
        }
    }

    private func tripFactsLine(meters: Double, riding: Bool) -> String {
        var parts = [DistanceFormatter.string(forMeters: Int(meters))]
        parts.append(String(localized: "\(Int(meters).formatted(.number.locale(.appLanguage))) steps",
                            bundle: .appLanguage, locale: .appLanguage))
        if !riding, let days = paceDays {
            parts.append(String(localized: "About \(days) days", bundle: .appLanguage, locale: .appLanguage))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Delivery note

    /// Above Send: how the letter reaches the recipient, in one quiet line.
    @ViewBuilder
    private var ticketSection: some View {
        if let destination = targetCoordinate, !targetCity.trimmed.isEmpty {
            let host = isRidingWithExistingRam ? flockViewModel.ramHeading(to: destination) : nil
            let carrierName = host?.name ?? ramName.trimmed
            if let deliveryLine = ticketDeliveryLine(carrierName: carrierName) {
                Label(deliveryLine, systemImage: "tray.and.arrow.down")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// How the letter reaches the recipient once the ram gets there. Only
    /// with a post office to deliver it; without one the ticket says nothing
    /// new (the letter is handed over in person, as always).
    private func ticketDeliveryLine(carrierName: String) -> String? {
        // No ram free and not riding along: say so before Send, instead of
        // promising an arrival that cannot start yet.
        if !flockViewModel.hasFreeRamSlot, !isRidingWithExistingRam {
            return String(localized: "Every ram is out, so this letter will start later, as soon as one is free.", bundle: .appLanguage, locale: .appLanguage)
        }
        guard TelemetryService.isServerConfigured else { return nil }
        let to = recipientName.trimmed
        guard !to.isEmpty else { return nil }
        let carrier = carrierName.isEmpty ? String(localized: "the ram", bundle: .appLanguage, locale: .appLanguage) : carrierName
        if closure != .postcard, savedRecipientEntry != nil {
            return String(localized: "Lands in \(to)'s mailbag when \(carrier) arrives. Only \(to)'s phone can open it.", bundle: .appLanguage, locale: .appLanguage)
        }
        return String(localized: "Lands in \(to)'s mailbag when \(carrier) arrives.", bundle: .appLanguage, locale: .appLanguage)
    }

    /// A saved Shepherd ID under the recipient's name, if there is one.
    private var savedRecipientEntry: SavedRecipientCode? {
        let name = recipientName.trimmed
        guard !name.isEmpty else { return nil }
        return savedCodes.saved.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame
        }
    }

    /// Looks up the recipient's profile key for `recipientPublicKey`: the one
    /// cached on their saved code first, refreshed from the relay when it can
    /// be reached. Nothing found simply means the ear tag travels as before.
    private func resolveRecipientKey() async {
        recipientPublicKey = nil
        guard closure != .postcard, let entry = savedRecipientEntry else { return }
        let address = CourierCodeStore.address(from: entry.code)
        if let cached = entry.publicKey, let raw = Data(base64Encoded: cached),
           let key = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw) {
            recipientPublicKey = (address, key)
        }
        guard let relay, TelemetryService.isServerConfigured,
              let fetched = try? await relay.publicKey(ofAddress: address) else { return }
        savedCodes.cachePublicKey(fetched.rawRepresentation.base64EncodedString(), for: entry.id)
        recipientPublicKey = (address, fetched)
    }

    // MARK: - Starting location notice

    /// There's no "Starting From" field in this form anymore for the
    /// sender to fix this themselves — the starting city is always
    /// resolved silently from `LocationService`. So when there's nothing
    /// to resolve yet (no fix, or access denied), this is the one visible
    /// nudge that sending is currently blocked and why, with a way to
    /// actually do something about it, rather than `canSend` just quietly
    /// staying `false` with no explanation.
    @ViewBuilder
    private var startingLocationNotice: some View {
        if currentCoordinate == nil {
            if locationService.authorizationDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label("Location access is off, so there's no starting city yet — tap to turn it on in Settings.", systemImage: "location.slash")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            } else if locationService.isResolving {
                Label("Finding your starting location…", systemImage: "location.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    locationService.resolveCurrentLocation()
                } label: {
                    Label("Couldn't find your starting location yet — tap to try again.", systemImage: "location.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Clears only the destination (and anything derived from it — the
    /// handoff plan, route errors). The ram, recipient, message and seal
    /// stay exactly as typed, so re-picking a city never throws away a
    /// finished letter — before this, the chip's "x" reset the whole form.
    private func clearDestination() {
        withAnimation(.easeInOut(duration: 0.2)) {
            targetCity = ""
            targetCoordinate = nil
            droppedDestination.wrappedValue = nil
            resetHandoffState()
            resolutionError = nil
            requirementNotice = nil
        }
        // Collapsing the sheet is `cancelComposing`'s job; with a letter
        // still drafted the sheet stays where it is for the re-pick.
    }

    private func resetHandoffState() {
        needsHandoffCity = false
        handoffPlan = nil
        showsManualHandoffField = false
        handoffCity = ""
        handoffCoordinate = nil
    }

    private func cancelComposing() {
        // `currentCity`/`currentCoordinate` need no reset here — they're
        // computed straight from `LocationService`, not local draft
        // state, so there's nothing about a canceled draft for them to
        // carry over. A deliberately abandoned letter takes its draft
        // with it.
        resetForm()
        isCodeMode = false
        sentByCode = nil
        draftStore.clear()
        draftSavedNotice = false
        onCancel()
    }

    // MARK: - Send by code

    private func toggleCodeMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isCodeMode.toggle()
            sentByCode = nil
            resolutionError = nil
            requirementNotice = nil
            resetHandoffState()
        }
        if isCodeMode { onDestinationSelected() }
    }

    /// Fills the code field from a code a phone nearby is sharing, but only into an empty field: never over
    /// something the sender typed or picked.
    private func prefillFromNearby() {
        guard let nearby = nearbyProfileCode, CourierCodeStore.isAddress(nearby), !hasShepherdID else { return }
        shepherdID = CourierCodeStore.formatted(nearby)
        prefillRecipientName(forCode: shepherdID)
    }

    /// "Who is this for?" starts as the saved name for that code, if there is one. Only an empty field (or
    /// one still holding another saved name) is replaced, so it stays editable and typing is never lost.
    private func prefillRecipientName(forCode code: String) {
        guard let entry = savedCodes.entry(forCode: code) else { return }
        let current = recipientName.trimmed
        if current.isEmpty || savedCodes.saved.contains(where: { $0.name == current }) {
            recipientName = entry.name
        }
    }

    private func applyShepherdIDRequest(_ id: String?) {
        guard let id else { return }
        shepherdID = CourierCodeStore.formatted(id)
        prefillRecipientName(forCode: shepherdID)
        withAnimation { isCodeMode = true; sentByCode = nil }
        shepherdIDRequest.wrappedValue = nil
        onDestinationSelected()
    }

    /// The destination, as a code: the recipient's Shepherd ID (optional).
    private var shepherdIDField: some View {
        shepherdIDFieldContent
            .onAppear {
                onListenForNearbyCode(true)
                prefillFromNearby()
            }
            .onDisappear { onListenForNearbyCode(false) }
            .onChange(of: nearbyProfileCode) { prefillFromNearby() }
    }

    private var shepherdIDFieldContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !savedCodes.saved.isEmpty {
                savedCodeChips
            }

            HStack(spacing: 8) {
                Image(systemName: "number")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Their Shepherd ID (optional)", text: $shepherdID)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($isShepherdIDFocused)
                    .onChange(of: shepherdID) { _, new in
                        let formatted = CourierCodeStore.formatted(new)
                        if formatted != new { shepherdID = formatted }
                    }
                    .onChange(of: isShepherdIDFocused) { _, focused in
                        if focused { onDestinationSelected() }
                    }
                if hasShepherdID {
                    Button { shepherdID = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
                // Save this code for next time — only once it's a whole,
                // valid Shepherd ID, and only offered once (a code
                // already on file shows a filled bookmark instead).
                if hasShepherdID, shepherdIDIsValid {
                    let alreadySaved = savedCodes.entry(forCode: shepherdID) != nil
                    Button {
                        if !alreadySaved { isSavingCode = true }
                    } label: {
                        Image(systemName: alreadySaved ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(alreadySaved)
                    .accessibilityLabel(alreadySaved ? "Already saved" : "Save this code")
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(.thinMaterial, in: Capsule())
        }
        .sheet(isPresented: $isSavingCode) {
            SaveRecipientCodeSheet(code: CourierCodeStore.formatted(shepherdID), suggestedName: recipientName.trimmed) { name, locationName, locationCoordinate, notes in
                savedCodes.add(
                    name: name,
                    code: shepherdID,
                    locationName: locationName,
                    locationCoordinate: locationCoordinate.map { RamCoordinate(latitude: $0.latitude, longitude: $0.longitude) },
                    notes: notes
                )
            }
        }
    }

    /// Saved Shepherd IDs as a horizontal row of chips. Tapping one just
    /// fills the field with that code — it never opens or navigates
    /// anywhere else; picking a saved recipient is still "send by code".
    private var savedCodeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(savedCodes.saved) { entry in
                    Button {
                        shepherdID = entry.code
                        isShepherdIDFocused = false
                        prefillRecipientName(forCode: entry.code)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(.secondary)
                            Text(entry.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            CourierCodeStore.address(from: shepherdID) == CourierCodeStore.address(from: entry.code)
                                ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                                : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            editingSavedCode = entry
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            pendingSavedCodeRemoval = entry
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .sheet(item: $editingSavedCode) { entry in
            SaveRecipientCodeSheet(code: entry.code, existing: entry) { name, locationName, locationCoordinate, notes in
                var updated = entry
                updated.name = name.trimmed.isEmpty ? entry.name : name.trimmed
                updated.locationName = locationName
                updated.locationCoordinate = locationCoordinate.map { RamCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
                updated.notes = notes
                savedCodes.update(updated)
            }
        }
        .alert("Remove this saved code?", isPresented: Binding(
            get: { pendingSavedCodeRemoval != nil },
            set: { if !$0 { pendingSavedCodeRemoval = nil } }
        ), presenting: pendingSavedCodeRemoval) { entry in
            Button("Remove", role: .destructive) {
                savedCodes.remove(entry)
                pendingSavedCodeRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingSavedCodeRemoval = nil }
        } message: { entry in
            Text("\(entry.name) is removed from your saved codes. Their Shepherd ID still works if you type it in.")
        }
    }

    /// What the sender sees when a letter is held for its recipient's gate —
    /// right here, in the sheet. (With a known gate the ram simply sets out
    /// and the journey takes over the panel, like any letter.)
    private func codeSentCard(_ result: SentByCode) -> some View {
        VStack(spacing: 16) {
            RamPortraitView(name: result.ramName, diameter: 64)

            VStack(spacing: 6) {
                Text("\(result.ramName) is ready to set out")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(result.isAddressed
                     ? "As soon as \(result.recipientName)'s phone says where their gate is, \(result.ramName) walks there on your steps."
                     : "Send \(result.recipientName) the link. When they open it, \(result.ramName) walks to their gate on your steps.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = result.shareMessage {
                ShareLink(item: message) {
                    Label("Share tracking link", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(Color.accentColor)
            }

            Text("It waits under Outgoing until then, and keeps its pen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Write another") {
                withAnimation { sentByCode = nil }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Code mode's ticket: whose steps, and where to.
    @ViewBuilder
    private var codeTicketSection: some View {
        let carrier = ramName.trimmed
        let to = recipientName.trimmed
        if !carrier.isEmpty, !to.isEmpty {
            Label(
                hasShepherdID
                    ? String(localized: "\(carrier) walks to \(to)'s gate on your steps. It lands in their mailbag when it gets there.", bundle: .appLanguage, locale: .appLanguage)
                    : String(localized: "\(carrier) sets out when \(to) opens your link, then walks to their gate on your steps.", bundle: .appLanguage, locale: .appLanguage),
                systemImage: "figure.walk"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Code mode, under the same rule as every letter: the sender's ram walks
    /// it to the recipient's gate. A Shepherd ID says where that gate is; an
    /// ear tag (or an ID whose phone hasn't set a gate yet) holds the letter
    /// until the recipient's phone does, and the ram sets out then.
    private func sendByCode() async {
        guard let relay, TelemetryService.isServerConfigured else {
            resolutionError = "Sending by Shepherd ID needs the post office, and it isn't reachable right now."
            sendAttemptWarningTick += 1
            return
        }
        guard flockViewModel.hasFreeRamSlot else {
            setAsideForLackOfRam()
            return
        }
        guard let origin = await awaitCurrentCoordinate() else {
            withAnimation {
                resolutionError = locationService.authorizationDenied
                    ? "Location access is off, so there's no starting point. Turn it on in Settings, then try again."
                    : "Couldn't find your starting location. Move somewhere with a clearer signal and try again."
            }
            sendAttemptWarningTick += 1
            return
        }

        isSendingByCode = true
        resolutionError = nil
        defer { isSendingByCode = false }

        // A Shepherd ID: their key (so only their phone opens it) and their gate.
        recipientPublicKey = nil
        var gate: LetterGate?
        if hasShepherdID {
            let address = CourierCodeStore.address(from: shepherdID)
            do {
                let info = try await relay.addressInfo(address)
                recipientPublicKey = (address, info.publicKey)
                gate = info.gate
                if let entry = savedCodes.entry(forCode: address) {
                    savedCodes.cachePublicKey(info.publicKey.rawRepresentation.base64EncodedString(), for: entry.id)
                }
            } catch RelayError.notFound {
                resolutionError = "Nobody has that Shepherd ID. Check it and try again."
                sendAttemptWarningTick += 1
                return
            } catch {
                resolutionError = LocalizedStringKey((error as? LocalizedError)?.errorDescription
                    ?? String(localized: "The post office couldn't be reached. Try again.", bundle: .appLanguage, locale: .appLanguage))
                sendAttemptWarningTick += 1
                return
            }
        }

        let letter = makeLetter()
        guard letter.relayTicket != nil else {
            SealKeyVault.remove(for: letter.id)
            resolutionError = "The post office couldn't accept that. Try again."
            sendAttemptWarningTick += 1
            return
        }
        let carrier = ramName.trimmed
        let originCity = currentCity.trimmed.isEmpty
            ? String(localized: "Somewhere", bundle: .appLanguage, locale: .appLanguage)
            : currentCity.trimmed

        if let gate {
            // The gate is known: plan the road and set out now, like any letter.
            do {
                let ram = try await RamRoutePlanner.makeRam(
                    name: carrier, letter: letter, origin: origin, originCity: originCity,
                    destination: gate.coordinate, destinationCity: gate.city
                )
                dispatch(ram)
            } catch RamRoutePlanner.PlanError.noRoute {
                SealKeyVault.remove(for: letter.id)
                resolutionError = "\(gate.city) can't be reached from here by road or packet yet. Try again from somewhere else."
                sendAttemptWarningTick += 1
            } catch {
                SealKeyVault.remove(for: letter.id)
                resolutionError = "Couldn't resolve a route right now. Check your connection and try again."
                sendAttemptWarningTick += 1
            }
            return
        }

        // No gate yet: hold the letter; its ram sets out once the gate is known.
        LetterTracker.shared.hold(letter, ramName: carrier, origin: origin, originCity: originCity)
        Task { await NotificationManager.shared.requestAuthorizationIfNeeded() }
        SoundEffectPlayer.shared.play(.dispatchWhoosh)
        SharingInvitation.noteLetterSent()
        let to = recipientName.trimmed
        let wasAddressed = hasShepherdID
        draftStore.clear()
        resetForm()
        withAnimation {
            sentByCode = SentByCode(
                recipientName: to,
                ramName: carrier,
                shareMessage: letter.awaitingGateShareMessage(ramName: carrier),
                isAddressed: wasAddressed
            )
        }
    }

    // MARK: - Sending

    private func send() async {
        // The form's own completeness comes first: a letter that's still
        // missing something is told so, whatever the pasture looks like.
        if let missingRequirement {
            withAnimation { requirementNotice = missingRequirement }
            sendAttemptWarningTick += 1
            return
        }
        requirementNotice = nil

        // By Shepherd ID or ear tag: the same sender-walks rule, with the
        // destination coming from the recipient's gate (see `sendByCode`).
        if isCodeMode {
            await sendByCode()
            return
        }

        await resolveRecipientKey()

        // A ram is already going there: the letter rides in its mailbag.
        if ridesWithExistingRam, let destination = targetCoordinate,
           let host = flockViewModel.ramHeading(to: destination) {
            let letter = makeLetter()
            flockViewModel.bundle(letter, into: host.id)
            startTracking(letter, ramName: host.name, city: host.targetCity, expectedBy: host.expectedArrival)
            SoundEffectPlayer.shared.play(.dispatchWhoosh)
            SharingInvitation.noteLetterSent()
            draftStore.clear()
            draftSavedNotice = false
            resetForm()
            onRodeAlong(host)
            return
        }

        // A finished letter with no ram free to carry it: keep it, whole,
        // and open "Expand the Pasture" — never a dead slider, never a
        // lost letter. The route isn't resolved first; there's nothing
        // to walk it yet.
        guard flockViewModel.hasFreeRamSlot else {
            setAsideForLackOfRam()
            return
        }
        guard let finalDestination = targetCoordinate else { return }

        // The starting point comes from the sender's real location. If it
        // hasn't landed yet, wait for it here — with the button showing
        // that's what it's doing — rather than refusing the tap.
        guard let origin = await awaitCurrentCoordinate() else {
            withAnimation {
                resolutionError = locationService.authorizationDenied
                    ? "Location access is off, so there's no starting point. Turn it on in Settings, then try again."
                    : "Couldn't find your starting location. Move somewhere with a clearer signal and try again."
            }
            sendAttemptWarningTick += 1
            return
        }

        isResolvingRoute = true
        resolutionError = nil
        defer { isResolvingRoute = false }

        do {
            if needsHandoffCity {
                if let handoffPlan, !showsManualHandoffField {
                    // The app already picked the port and resolved the
                    // road leg to it — dispatch straight away.
                    dispatchViaHandoff(
                        origin: origin,
                        handoffCity: handoffPlan.gateway.name,
                        leg: handoffPlan.leg,
                        finalDestination: finalDestination
                    )
                } else {
                    guard let handoff = handoffCoordinate else {
                        resolutionError = "Pick a handoff city from the search suggestions."
                        return
                    }
                    try await sendViaHandoff(origin: origin, handoff: handoff, finalDestination: finalDestination)
                }
            } else {
                try await sendDirect(origin: origin, finalDestination: finalDestination)
            }
        } catch RouteResolutionError.noDrivableRoute {
            if needsHandoffCity {
                // The handoff city itself isn't reachable by road either —
                // ask for a different one rather than dispatching a ram
                // that can never move.
                let city = handoffCity.trimmed.isEmpty ? String(localized: "That city", bundle: .appLanguage, locale: .appLanguage) : handoffCity.trimmed
                let origin = currentCity.trimmed
                resolutionError = "\(city) isn't reachable by road from \(origin) either. Try a different handoff city."
            } else {
                // No road to the destination: pick the port for the
                // sender, then show the plan for them to confirm with a
                // second tap of Send — the button shows what it's doing
                // meanwhile, so it never reads as "nothing happened".
                isPlanningHandoff = true
                let plan = await HandoffGatewayService.plan(from: origin, toward: finalDestination)
                isPlanningHandoff = false

                withAnimation(.easeInOut(duration: 0.2)) {
                    needsHandoffCity = true
                    handoffPlan = plan
                    showsManualHandoffField = plan == nil
                    handoffCity = plan?.gateway.name ?? ""
                    handoffCoordinate = plan?.gateway.coordinate
                }
                resolutionError = nil
            }
        } catch RouteResolutionError.requestFailed {
            resolutionError = "Couldn't resolve a route right now. Check your connection and try again."
        } catch {
            resolutionError = "Something went wrong resolving the route. Try again."
        }
    }

    /// Returns the sender's coordinate as soon as `LocationService` has
    /// one, kicking off a resolve if needed and waiting up to ~25 s for
    /// it (the service's own fix timeout plus a little slack). `nil`
    /// means it never came — permission denied or no fix at all.
    private func awaitCurrentCoordinate() async -> CLLocationCoordinate2D? {
        if let coordinate = currentCoordinate { return coordinate }

        isAwaitingLocation = true
        defer { isAwaitingLocation = false }

        locationService.resolveCurrentLocation()
        let deadline = ContinuousClock.now + .seconds(25)
        while ContinuousClock.now < deadline {
            if let coordinate = currentCoordinate { return coordinate }
            if locationService.authorizationDenied { return nil }
            try? await Task.sleep(for: .milliseconds(250))
            if !locationService.isResolving, currentCoordinate == nil {
                // The service gave up (timed out); one more nudge, then
                // let the loop's own deadline decide.
                locationService.resolveCurrentLocation()
            }
        }
        return currentCoordinate
    }

    /// The full letter's-true-destination is directly drivable in one leg.
    private func sendDirect(
        origin: CLLocationCoordinate2D,
        finalDestination: CLLocationCoordinate2D
    ) async throws {
        let leg = try await RouteService.drivingRoute(from: origin, to: finalDestination)

        let originNode = RouteNode(
            cityName: currentCity.trimmed,
            latitude: origin.latitude,
            longitude: origin.longitude,
            carrierName: ramName.trimmed,
            stepsContributed: 0
        )

        let letter = makeLetter()

        let ram = Ram(
            name: ramName.trimmed,
            totalStepsRequired: leg.distanceMeters,
            currentCity: currentCity.trimmed,
            targetCity: targetCity.trimmed,
            legDestinationCity: targetCity.trimmed,
            routeHistory: [originNode],
            routeCoordinates: leg.coordinates,
            requiresHandoffAtLegEnd: false,
            letter: letter,
            finalDestinationCoordinate: RamCoordinate(finalDestination)
        )

        dispatch(ram)
    }

    /// Only the leg to an intermediate handoff city is drivable; the ram
    /// will wait there for someone else to carry the letter the rest of
    /// the way.
    /// A manually named handoff city: resolve the road leg to it first.
    private func sendViaHandoff(
        origin: CLLocationCoordinate2D,
        handoff: CLLocationCoordinate2D,
        finalDestination: CLLocationCoordinate2D
    ) async throws {
        let leg = try await RouteService.drivingRoute(from: origin, to: handoff)
        dispatchViaHandoff(
            origin: origin,
            handoffCity: handoffCity.trimmed,
            leg: leg,
            finalDestination: finalDestination
        )
    }

    /// Dispatches a ram whose first leg ends at a handoff city — the
    /// letter's true destination is carried along for whoever picks it
    /// up on the far side to resolve the next leg from.
    private func dispatchViaHandoff(
        origin: CLLocationCoordinate2D,
        handoffCity: String,
        leg: ResolvedRoute,
        finalDestination: CLLocationCoordinate2D
    ) {
        let originNode = RouteNode(
            cityName: currentCity.trimmed,
            latitude: origin.latitude,
            longitude: origin.longitude,
            carrierName: ramName.trimmed,
            stepsContributed: 0
        )

        let letter = makeLetter()

        let ram = Ram(
            name: ramName.trimmed,
            totalStepsRequired: leg.distanceMeters,
            currentCity: currentCity.trimmed,
            targetCity: targetCity.trimmed,
            legDestinationCity: handoffCity,
            routeHistory: [originNode],
            routeCoordinates: leg.coordinates,
            requiresHandoffAtLegEnd: true,
            letter: letter,
            finalDestinationCoordinate: RamCoordinate(finalDestination)
        )

        dispatch(ram)
    }

    /// The letter as the sender closed it: wax-sealed and encrypted, or
    /// an open postcard. `send()` never gets here with `closure == nil`
    /// (`missingRequirement` catches that), so the fallback is the
    /// private one.
    private func makeLetter() -> Letter {
        var letter = makeUnpapered()
        if closure != .postcard {
            letter.paper = paper
            letter.paperCustomHex = customPaperHex
        }
        let code = SealKeyVault.code(for: letter.id)
        // Followed by the post office when there is one (see `LetterTracker`).
        letter.relayTicket = LetterTracker.ticketIfConfigured(forCode: code)
        // Sealed to the recipient's profile: their phone opens it by itself.
        if letter.isEncrypted, let code, let recipient = recipientPublicKey,
           let key = RecipientKeyring.key(forCode: code, address: recipient.address, publicKey: recipient.key) {
            letter.recipientKeys = [key]
        }
        return letter
    }

    /// Hands a letter that just left to the post office and offers the
    /// tracking link to send the recipient.
    private func startTracking(_ letter: Letter, ramName: String, city: String, expectedBy: Date?) {
        LetterTracker.shared.track(letter)
        // The first letter out is the moment notifications start to matter.
        Task { await NotificationManager.shared.requestAuthorizationIfNeeded() }
        guard let message = letter.trackingShareMessage(ramName: ramName, city: city, expectedBy: expectedBy) else { return }
        NotificationCenter.default.post(name: .letterReadyToShare, object: nil, userInfo: ["message": message])
    }

    /// Under "Who is this for?": make the name a real condition, not just a label.
    private var nameMatchToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Only this name can open it", isOn: $requiresNameMatch)
                .font(.subheadline.weight(.semibold))
                .tint(Color.wax)
            Text("They need a name that matches \(recipientName.trimmed). Without this, the ear tag code alone opens the letter.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private func makeUnpapered() -> Letter {
        switch closure {
        case .postcard:
            let postcard = Letter.writeOpen(
                senderName: senderName,
                recipientName: recipientName.trimmed,
                messageBody: messageBody.trimmed,
                attachment: attachedPhoto?.jpegData(compressionQuality: 0.6)
            )
            // A postcard needs no key, but the post office still needs an ear
            // tag to follow it by.
            if TelemetryService.isServerConfigured {
                SealKeyVault.store(LetterCode.generate(), for: postcard.id)
            }
            return postcard
        case .sealed, .none:
            var letter = Letter.write(
                senderName: senderName,
                recipientName: recipientName.trimmed,
                messageBody: messageBody.trimmed,
                sealColor: sealColor,
                attachment: attachedPhoto?.jpegData(compressionQuality: 0.6),
                unlockAt: composedUnlockAt,
                geofence: composedGeofence,
                scratchSecret: composedScratchSecret
            ).letter
            letter.requiresNameMatch = requiresNameMatch && !recipientName.trimmed.isEmpty
            return letter
        }
    }

    private func dispatch(_ ram: Ram) {
        guard flockViewModel.dispatch(ram) else {
            // The slot was taken between the check in `send()` and now
            // (an AirDrop landing mid-route-resolve) — same answer.
            setAsideForLackOfRam()
            return
        }
        if let letter = ram.letter {
            startTracking(letter, ramName: ram.name, city: ram.targetCity, expectedBy: ram.expectedArrival)
        }
        SoundEffectPlayer.shared.play(.dispatchWhoosh)
        SharingInvitation.noteLetterSent()
        // Tell the root a letter just left; it decides whether this is
        // the first one and, if so, shows the payoff moment.
        NotificationCenter.default.post(
            name: .firstLetterDispatched,
            object: nil,
            userInfo: [
                "recipient": recipientName.trimmed,
                "ramName": ram.name,
                "targetCity": ram.targetCity,
                "meters": ram.totalStepsRequired
            ]
        )
        // The letter is on the road: nothing left to restore, and the
        // form is cleared for the next one. `trackedRam` in `JourneyView`
        // becomes non-nil immediately and its panel shows the journey on
        // its own — no callback needed.
        draftStore.clear()
        draftSavedNotice = false
        resetForm()
    }

    // MARK: - Drafts

    /// The "Slide to Dispatch" fallback when no ram is free: the form is
    /// persisted as a `LetterDraft` first, then the paywall is presented.
    /// Order matters — the sheet stays up behind the paywall with the
    /// form untouched, and if the app is killed with the paywall open the
    /// letter is still on disk for the next launch.
    private func setAsideForLackOfRam() {
        draftStore.save(currentDraft(wasSetAsideAtDispatch: true))
        withAnimation { draftSavedNotice = true }
        sendAttemptWarningTick += 1
        startsLaterAlertPresented = true
    }

    /// A form with something in it, kept across the panel's page switches
    /// and re-presentations without any notice — it was never slid.
    private func autosaveDraftIfNeeded() {
        let draft = currentDraft(wasSetAsideAtDispatch: draftStore.draft?.wasSetAsideAtDispatch ?? false)
        if draft.hasContent {
            draftStore.save(draft)
        }
    }

    private func currentDraft(wasSetAsideAtDispatch: Bool) -> LetterDraft {
        LetterDraft(
            targetCity: targetCity.trimmed,
            targetLatitude: targetCoordinate?.latitude,
            targetLongitude: targetCoordinate?.longitude,
            ramName: ramName.trimmed,
            recipientName: recipientName.trimmed,
            messageBody: messageBody,
            sealColor: sealColor,
            closure: closure.map { $0 == .sealed ? LetterDraft.Closure.sealed : .postcard },
            wasSetAsideAtDispatch: wasSetAsideAtDispatch,
            savedAt: Date()
        )
    }

    /// Puts a saved draft back into an otherwise empty form. Never
    /// overwrites something the sender has already started typing in
    /// this view's lifetime.
    private func restoreDraftIfNeeded() {
        guard let draft = draftStore.draft, draft.hasContent else { return }
        guard targetCoordinate == nil, recipientName.trimmed.isEmpty, messageBody.trimmed.isEmpty else { return }

        targetCity = draft.targetCity
        targetCoordinate = draft.targetCoordinate
        ramName = draft.ramName
        recipientName = draft.recipientName
        messageBody = draft.messageBody
        // A wax the person no longer has (a lapsed subscription) falls back
        // to crimson rather than quietly sending a locked colour.
        sealColor = (draft.sealColor.isIncludedFree || entitlementService.hasPastureExpansion) ? draft.sealColor : .crimson
        // Every letter is encrypted now; a draft saved as an open postcard restarts at the seal.
        closure = draft.closure == .sealed ? LetterClosure.sealed : nil
        // Only a letter that was actually slid and turned away gets the
        // "Saved to Drafts" notice back — and only while that's still
        // the situation.
        draftSavedNotice = draft.wasSetAsideAtDispatch && !flockViewModel.hasFreeRamSlot

        if targetCoordinate != nil {
            locationService.resolveCurrentLocation()
            onDestinationSelected()
        }
    }

    /// Everything in the form back to blank, without touching the sheet.
    private func resetForm() {
        targetCity = ""
        targetCoordinate = nil
        resetHandoffState()
        ramName = ""
        recipientName = ""
        requiresNameMatch = false
        shepherdID = ""
        messageBody = ""
        attachedPhoto = nil
        paper = .cream
        customPaperHex = nil
        sealColor = .crimson
        closure = nil
        resolutionError = nil
        requirementNotice = nil
        ridesWithExistingRam = false
    }
}

/// How a letter is closed before it travels — see `closure`.
private enum LetterClosure {
    case sealed
    case postcard
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedOrNil: String? { trimmed.isEmpty ? nil : trimmed }
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

#Preview {
    ComposeLetterView(onDestinationSelected: {}, onCancel: {}, isPanelExpanded: false)
        .environment(FlockViewModel.preview)
        .environment(EntitlementService())
        .environment(LocationService())
}
