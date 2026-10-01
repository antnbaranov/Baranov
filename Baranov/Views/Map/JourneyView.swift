//
//  JourneyView.swift
//  Baranov
//
//  The app's single root screen: the live map of the flock's currently-
//  traveling ram, plus the entry point for drafting and dispatching a new
//  letter. Real-world steps recorded here (via StepTrackerService) advance
//  whichever ram is currently walking or freshly dispatched — this is the
//  "Overland Travel" mechanic made visible, not a separate screen bolted
//  on afterward.
//
//  The ram's marker follows `routeCoordinates`, the real road-following
//  polyline `RouteService` resolved for the current leg, interpolated by
//  meters walked — it moves like a car tracing real streets, never a
//  diagonal line to the destination. The camera stays close and re-centers
//  on the ram as it moves rather than sitting zoomed out over a country.
//
//  There is no tab bar. The map is always full-screen behind a single
//  persistent panel docked at the bottom — the same "search card" pattern
//  Apple Maps uses. Collapsed, it's just a destination search field
//  (picking a place is the entire entry point into composing a letter, no
//  separate "open" step). While a ram is actually out walking, that same
//  panel gains a second page — its live progress, a compact floating card
//  when collapsed — with onboarding-style dots to switch between the
//  journey and a fresh letter, so composing never waits on the walk. Pasture is reached via
//  the pawprint button in the toolbar — presented as a modal sheet by
//  `RootView` (not pushed onto this view's own navigation stack, which
//  already has an always-on `.sheet` of its own for the docked panel
//  below; two `.sheet`s competing for the same slot is exactly what broke
//  Look Around once before, so Pasture's sheet lives one level up instead).
//  `isPasturePresented` is owned by `RootView` and just passed down here so
//  the docked panel still knows to hide itself while Pasture is up.
//
//  Three things on this screen exist to answer "why would I walk any
//  further today," and all three deliberately avoid competition with
//  strangers:
//
//  1. The docked panel leads with the person waiting — a named recipient
//     and the steps still between them and their letter — rather than a
//     distance to a city, because an obligation to someone real is what
//     actually gets shoes on.
//  2. `NextLandmarkService` resolves the next real, named place on the
//     road ahead, so there is always a target reachable *today* under the
//     one that is 1,800 km away; walking past it mints a `JourneyStamp`
//     in the ram's passport (a haptic, no interruption).
//  3. `FlockPulseService` shows everyone else as a count and, zoomed out,
//     as per-region counts — never as points. A ram's polyline runs from a
//     real sender's door to a real recipient's, so individual rams are not
//     something this app will ever put on a shared map.
//

import CoreLocation
import MapKit
import SwiftUI

struct JourneyView: View {
    let telemetryService: TelemetryService
    let carrierUserId: UUID
    private let onManualHoofbeat: () -> Void
    private let onNearbySender: () -> Void
    private let onHandOverToNearby: ((NearbyCourier) -> Void)?
    private let onSendLetterToNearby: ((NearbyCourier) -> Void)?

    @Environment(FlockViewModel.self) private var flockViewModel
    @Environment(CarrierPresenceService.self) private var presence
    @Environment(LetterInbox.self) private var letterInbox
    @Environment(ProximityCodeDiscovery.self) private var proximity
    @Environment(NearbyCourierService.self) private var nearbyCouriers
    @Environment(SavedCourierStore.self) private var savedCouriers
    /// The courier whose card is open on the map (see `NearbyCourierCard`).
    @State private var selectedNearbyCourier: NearbyCourier?
    @Environment(EntitlementService.self) private var entitlementService
    @AppStorage("com.baranov.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(AppLanguagePickerView.storageKey) private var selectedLanguageCode = Locale.current.language.languageCode?.identifier ?? "en"
    @AppStorage(AppAppearance.storageKey) private var appAppearanceRawValue = AppAppearance.system.rawValue

    private var currentLocale: Locale {
        Locale(identifier: selectedLanguageCode)
    }

    private var appAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRawValue) ?? .system
    }

    @State private var stepTracker = StepTrackerService()
    /// The map camera and its follow/flyover behaviour — see
    /// `JourneyCameraController`. The `Map` binds to `camera.position`.
    @State private var camera = JourneyCameraController()
    @State private var lastAppliedStepCount = 0

    /// Which ram the pedometer session currently belongs to. Tracking is
    /// torn down and restarted whenever this changes, so a new ram never
    /// inherits the step baseline of the last one — the way a freshly
    /// dispatched ram could otherwise be credited with steps walked
    /// before it existed and appear partway down its route.
    @State private var trackingRamId: UUID?
    /// Which of the sender's own rams the map and panel follow; nil = the default pick.
    @State private var selectedRamId: UUID?

    /// Rams this view has already flown the dispatch camera over — once
    /// per ram per view lifetime, so re-tracking (a tab away and back, a
    /// handoff resume) settles straight onto the ram instead of replaying
    /// the lift-off.
    @State private var flownOverRamIds: Set<UUID> = []

    /// Origin / halfway / destination names for the in-transit strip —
    /// see `RouteWaypointService` for the halfway de-duplication rule.
    @State private var waypointService = RouteWaypointService()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Whether the shepherd is walking *right now* — flipped on the
    /// moment a step delta lands and back off once
    /// `StepTrackerService.movingGracePeriod` passes with no new steps.
    /// This, not `Ram.status == .walking`, is what puts the marker into
    /// its galloping frames: a ram mid-journey whose shepherd has sat
    /// down stands and sways instead of running on the spot.
    @State private var isSenderMoving = false
    @State private var senderIdleTask: Task<Void, Never>?

    /// The near-term target: the next real, named place on the road ahead
    /// (see `NextLandmarkService`). "1,800 km to Frankfurt" is not
    /// something anyone can act on today; "2,340 steps to the Fraser
    /// River" is, and passing it is what earns a passport stamp.
    @State private var nextLandmarkService = NextLandmarkService()

    /// Bumped every time a stamp is actually earned, purely as a
    /// `sensoryFeedback` trigger — the haptic is the acknowledgement,
    /// there's no interruption or modal for it.
    @State private var stampsEarnedTick = 0

    /// Anonymous, aggregate presence of everyone else out walking right
    /// now — counts and coarse regions, never other people's rams as
    /// points on the map. See `FlockPulseService` for why.
    @State private var flockPulse: FlockPulseService

    init(telemetryService: TelemetryService, carrierUserId: UUID, isPasturePresented: Binding<Bool>, isProfilePresented: Binding<Bool> = .constant(false), isEnterCodePresented: Binding<Bool> = .constant(false), sendToShepherdID: Binding<String?> = .constant(nil), isDestinationPickerPresented: Binding<Bool> = .constant(false), pickedDestination: Binding<DroppedDestination?> = .constant(nil), letterRam: Binding<Ram?>, bagRam: Binding<Ram?> = .constant(nil), relay: LetterRelayService? = nil, onOpenByCode: @escaping (Ram, String) -> Void = { _, _ in }, onManualHoofbeat: @escaping () -> Void = {}, onNearbySender: @escaping () -> Void = {}, onHandOverToNearby: ((NearbyCourier) -> Void)? = nil, onSendLetterToNearby: ((NearbyCourier) -> Void)? = nil) {
        self.relay = relay
        self.onHandOverToNearby = onHandOverToNearby
        self.onSendLetterToNearby = onSendLetterToNearby
        self.onOpenByCode = onOpenByCode
        self.telemetryService = telemetryService
        self.carrierUserId = carrierUserId
        _isPasturePresented = isPasturePresented
        _isProfilePresented = isProfilePresented
        _isEnterCodePresented = isEnterCodePresented
        _sendToShepherdID = sendToShepherdID
        _isDestinationPickerPresented = isDestinationPickerPresented
        _pickedDestination = pickedDestination
        _letterRam = letterRam
        _bagRam = bagRam
        self.onManualHoofbeat = onManualHoofbeat
        self.onNearbySender = onNearbySender
        // Reads from the same ACIT3855 receiver this view already posts
        // ram hops to, so there is exactly one telemetry host to point at.
        _flockPulse = State(initialValue: FlockPulseService(baseURL: telemetryService.baseURL))
    }

    /// Whether Pasture's modal sheet is up — owned by `RootView` (see the
    /// header doc), passed down purely so `isDockedPanelPresented` below
    /// can hide this view's own docked panel while it's showing.
    @Binding var isPasturePresented: Bool
    /// A destination marked by pressing and holding on the map; read by Compose.
    @State private var droppedDestination: DroppedDestination?

    /// The trip Compose is planning, drawn on the map while it is being
    /// planned — see `RoutePreview`.
    @State private var routePreview: RoutePreview?
    /// 0…1 along the preview, from `RoutePreviewClock`.
    @State private var previewProgress: Double = 0
    /// The ram being tracked when the preview started, so backing out can
    /// tell "cancelled" from "dispatched" (which has its own flyover).
    @State private var previewBaselineRamId: Ram.ID?

    /// Whether the profile sheet is up — owned by `RootView`, like Pasture.
    @Binding var isProfilePresented: Bool
    /// Whether the "Enter Code" sheet is up — also owned by `RootView`;
    /// like the others it hides the docked panel while showing.
    @Binding var isEnterCodePresented: Bool
    /// A Shepherd ID picked up from a phone nearby: handed to the compose page,
    /// which sends by code right there — there is no separate screen for it.
    @Binding var sendToShepherdID: String?
    /// The "Choose on Map" destination picker (owned by `RootView`) and the
    /// spot it returns, which is forwarded to Compose as a dropped pin.
    @Binding var isDestinationPickerPresented: Bool
    @Binding var pickedDestination: DroppedDestination?
    /// The letter relay and what to do with a receiving code that opens a
    /// letter — the Enter Code page inside the docked panel needs both.
    private let relay: LetterRelayService?
    private let onOpenByCode: (Ram, String) -> Void

    /// The ram whose letter is being inspected or opened — owned by
    /// `RootView`, which presents `LetterDetailView` for it (same
    /// one-owner-per-modal rule as Pasture). Set from the courier dock
    /// and by tapping the ram on the map.
    @Binding var letterRam: Ram?
    /// The ram whose bag is open (owned by `RootView`, like `letterRam`).
    @Binding var bagRam: Ram?

    /// The person's own default ram, shown in the dock even when no
    /// letter is out, so the courier is always on the main screen.
    @State private var ramCompanionStore = RamCompanionStore()

    // Starts on the shortest of the sheet's real detents (the tiny peek
    // size, with the page title above one row) — a stale 152 matched none of them, which
    // made the sheet look short while the code treated it as open.
    @State private var panelDetent: PresentationDetent = CommandLine.arguments.contains("-screenshotMap") ? .height(JourneyView.tinyPanelHeight) : (CommandLine.arguments.contains("-screenshotCompose") ? .large : .height(JourneyView.tinyPanelHeight))

    /// Whether the floating "You are here"/"Ram is away" pill is
    /// currently shown — auto-dismissed a few seconds after it appears
    /// (see `revealReturnToMePill`) so it doesn't sit indefinitely over
    /// the progress step cards.
    @State private var isReturnToMePillVisible = !CommandLine.arguments.contains("-demoMode")
    @State private var returnToMePillDismissTask: Task<Void, Never>?

    /// The docked panel has exactly two pages: writing a letter (always the
    /// first, and where the app opens) and the mailbag of everything in
    /// transit. Codes are typed in the small field along the bottom of both.
    private enum PanelPage: Hashable {
        case compose
        case mailbag
    }

    @State private var panelPage: PanelPage = CommandLine.arguments.contains("-screenshotCompose") ? .compose : (CommandLine.arguments.contains("-demoMode") ? .mailbag : .compose)
    @State private var codeDraft = ""
    @State private var mailbagSection: MailbagSection = CommandLine.arguments.contains("-demoMode") ? .outgoing : .incoming
    /// What is pushed inside the mailbag page (a ram's bag, a letter). Held
    /// here rather than in the page so it survives the page being recycled
    /// by the horizontal pager.
    @State private var mailbagPath: [MailbagRoute] = []
    @State private var collapseTask: Task<Void, Never>?
    @State private var archiveQuery = ""
    @State private var codeFocusTick = 0
    /// The ear tag field has the cursor: the bottom strip rides on the keyboard,
    /// so it must not carry the home-indicator offset then.
    @State private var codeFieldFocused = false

    // Following / programmatic-vs-manual camera bookkeeping moved into
    // `JourneyCameraController` (`camera.isFollowingRam`,
    // `camera.noteCameraChangeEnded()`).

    /// Resolves the carrier's own real-world position for the idle state
    /// (no ram currently walking/grazing) — by default the map should show
    /// the ram standing at wherever the person actually is right now, the
    /// same way Apple Maps defaults to your own blue dot, rather than
    /// showing nothing or a generic world view.
    @Environment(LocationService.self) private var locationService

    // Look Around ("binoculars") — the same street-level feature Apple
    // Maps' binoculars button opens, scoped to the tracked ram's current
    // position (or the carrier's own while idle). All of its state lives
    // in `LookAroundSession`: the resolved scene, which of the three
    // Apple-Maps stages it's in (floating preview card at the top-trailing
    // corner → split screen over the top of the map → full screen), and
    // the estimated camera heading/FOV the marker's radar cone mirrors.
    // Availability is simple: the preview card doesn't appear until a
    // real scene resolves, so there is never a "Look Around unavailable"
    // failure to surface (the card is the only entry point; there is no
    // separate binoculars button drawing the same feature twice) —
    // and nothing here is a modal presentation, so nothing can fight the
    // always-on docked sheet for its presentation slot.
    @State private var lookAround = LookAroundSession()
    @State private var isResolvingLookAround = false

    /// The window's frame in `.global` space (the `NavigationStack` fills
    /// it), measured live. Compared against the Look Around host's own
    /// frame this yields the real status-bar / Dynamic-Island and
    /// home-indicator heights — see `lookAroundOverlay`.
    @State private var windowFrameGlobal: CGRect = .zero

    /// Y in `.global` space of the map's usable bottom edge — the top of
    /// whatever the docked panel is currently covering (its live detent
    /// is reserved as the map's bottom safe area). The Look Around
    /// preview card is pinned just above this, so it floats directly
    /// over the sheet's top edge rather than over the map controls or
    /// under the sheet.
    @State private var mapDockTopGlobalY: CGFloat = 0

    /// The split-screen panel height minus the status-bar inset, for the
    /// current window — measured by the panel's host overlay (see
    /// `lookAroundOverlay`), which is the only view here that knows the
    /// true window height. Applied to the map via `lookAroundMapTopInset`.
    @State private var lookAroundSplitInset: CGFloat = 0

    /// Extra top safe-area inset the map takes while Look Around is in
    /// split screen, so the map's visible region — and its camera
    /// center, which MapKit keeps inside the safe area — moves into the
    /// bottom half rather than being covered. Zero in every other stage
    /// (full screen covers the map entirely; the preview card floats).
    private var lookAroundMapTopInset: CGFloat {
        lookAround.layout == .split ? lookAroundSplitInset : 0
    }

    // Follow camera altitude/tilt (350 m, 65°) live on
    // `JourneyCameraController.followDistanceMeters` / `followPitchDegrees`.

    /// `.standard` never actually renders MapKit's spherical 3D globe once
    /// the camera pulls back far enough — a known SwiftUI/MapKit
    /// limitation where it just keeps shrinking as a flat rectangle no
    /// matter how far out you zoom, while `.hybrid`/`.imagery` do
    /// transition into the real globe view
    /// (https://developer.apple.com/forums/thread/760542). So the map
    /// style below swaps to `.hybrid` once the camera is pulled back past
    /// this distance — kept low (a few hundred km, "looking at a country or
    /// region") rather than continent-scale, so a normal pinch-zoom-out
    /// reaches it comfortably instead of needing to pinch unrealistically
    /// far before the switch ever kicks in.
    private let globeViewDistanceThresholdMeters: CLLocationDistance = 800_000

    /// The farthest a pinch-to-zoom-out gesture is allowed to pull the
    /// camera back to — far enough to read as pulling back from the whole
    /// planet, not just a continent. SwiftUI's `Map` otherwise enforces its
    /// own, much tighter implicit ceiling well short of "planet" distance,
    /// which is what made globe view unreachable by pinch alone; passing
    /// this as `MapCameraBounds(maximumDistance:)` below raises that
    /// ceiling instead of relying on a separate one-tap "jump to globe"
    /// button to get there.
    private let globeDistanceMeters: CLLocationDistance = 20_000_000

    /// Where regional presence markers start appearing — see
    /// `isRegionOverviewVisible`. Roughly "looking at a province or a
    /// small country," well below the globe-style switch above.
    private let regionOverviewDistanceThresholdMeters: CLLocationDistance = 120_000

    /// The docked panel's collapsed height. One height for BOTH pages, so
    /// swiping between New Letter and Mailbag never resizes the sheet — the
    /// only exception is a letter waiting at the gate, whose "Break the
    /// Seal" button needs the extra room — on both pages alike.
    private func collapsedHeight(for page: PanelPage) -> CGFloat {
        trackedRam?.status == .arrivedAtGate ? 340 : 310
    }

    private var collapsedPanelHeight: CGFloat { collapsedHeight(for: panelPage) }

    /// The shortest sheet, on the New Letter page only: destination, the
    /// current ram's progress and the page dots.
    private static let compactComposeHeight: CGFloat = 240

    /// Smaller still: on New Letter only "Where is this letter going?", on
    /// the Mailbag one slim courier row; "Expand" and the dots below.
    private static let tinyPanelHeight: CGFloat = 148


    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private var isPanelTiny: Bool {
        panelDetent == .height(Self.tinyPanelHeight)
    }

    private var isPanelCompact: Bool {
        panelDetent == .height(Self.compactComposeHeight)
    }

    /// Open only at the two tall detents; every height detent — including a
    /// stale one left over from a page or status change — is a short sheet.
    private var isPanelCollapsed: Bool {
        panelDetent != .dockMedium && panelDetent != .large
    }

    private var panelDetents: [PresentationDetent] {
        // Three sizes on both pages: the sheet stays exactly where the
        // person left it when they swipe to the other page. Neither the
        // old 240pt stop nor the old collapsedPanelHeight stop are
        // offered anymore — both sat between tiny and dockMedium showing
        // a couple of fields with a big empty gap under them and nothing
        // else, which read as a broken, near-empty sheet.
        [.height(Self.tinyPanelHeight), .dockMedium, .large]
    }

    /// The ram this tab is currently tracking real-world steps for: the one
    /// actively walking, or — if none is — the most recently dispatched ram
    /// still waiting to set out.
    /// The sender's own rams that are out with a letter.
    private var sentRams: [Ram] {
        flockViewModel.ownRams.filter {
            $0.status == .walking || $0.status == .grazing
                || $0.status == .waitingForHandoff || $0.status == .atSea
        }
    }

    /// Switches to the next of the sender's own rams and looks at it.
    private func showNextSentRam() {
        let rams = sentRams
        guard rams.count > 1 else { return }
        let index = rams.firstIndex(where: { $0.id == trackedRam?.id }) ?? -1
        let next = rams[(index + 1) % rams.count]
        selectedRamId = next.id
        camera.resumeFollowing(ramCoordinate: next.currentCoordinate ?? next.originCoordinate, animated: true)
    }

    private var trackedRam: Ram? {
        let own: [Ram] = flockViewModel.ownRams
        let active: [Ram] = flockViewModel.activeRams

        #if DEBUG
        if CommandLine.arguments.contains("-screenshotLetterOpen") || CommandLine.arguments.contains("-screenshotLetterOpened") {
            return active.first
        }
        #endif
        if let id = selectedRamId, let ram = sentRams.first(where: { $0.id == id }) { return ram }
        // The person's own ram first: guests ride along on its steps.
        if let ram = own.first(where: { $0.status == .walking }) { return ram }
        if let ram = own.first(where: { $0.status == .grazing }) { return ram }
        if let ram = active.first(where: { $0.status == .walking }) { return ram }
        if let ram = active.first(where: { $0.status == .grazing }) { return ram }
        // A ram at the recipient's gate owns the dock next: the letter
        // waiting to be opened is the payoff of the whole walk, and the
        // dock is now the only way to reach it (the Satchel is gone).
        // Ranked below walking/grazing because those need the
        // pedometer, which follows `trackedRam`.
        if let ram = active.first(where: { $0.status == .arrivedAtGate }) { return ram }
        // Nothing is walking, but something may still be moving: a ram
        // aboard the packet crosses on the clock, and the map is the
        // one place that progress is legible. Ranked last so a ram
        // that needs the person's steps always wins the screen.
        if let ram = active.first(where: { $0.status == .atSea }) { return ram }
        return active.first(where: { $0.status == .waitingForHandoff })
    }

    /// The docked panel is Journey's own UI — it should disappear while
    /// Pasture's modal sheet is up, and reappear the moment it's
    /// dismissed, rather than floating above it. It also steps aside
    /// while Look Around is expanded (split or full screen), exactly as
    /// Apple Maps drops its place card when Look Around takes the top of
    /// the screen: the bottom half is then a clean map with the marker
    /// and its heading cone, not a map with a sheet over it. The floating
    /// preview card, by contrast, never touches the sheet.
    /// Whether one of the app's other modal sheets (owned by `RootView`)
    /// is up over the map.
    private var isAnotherSheetUp: Bool {
        isPasturePresented || isProfilePresented
            || isDestinationPickerPresented || letterRam != nil || bagRam != nil
    }

    /// Held `false` for a beat after another sheet closes. The docked
    /// panel used to come back in the same frame the closing sheet was
    /// still sliding down, so two sheets animated over each other — the
    /// "weird" close. Waiting out the dismissal (about 0.45 s) lets the
    /// sheet finish leaving before the panel rises again.
    @State private var isDockedPanelAllowed = true

    private var isDockedPanelPresented: Binding<Bool> {
        Binding(
            get: { isDockedPanelAllowed && !isAnotherSheetUp && !lookAround.layout.isExpanded },
            set: { newValue in
                if !lookAround.layout.isExpanded, letterRam == nil {
                    isPasturePresented = !newValue
                }
            }
        )
    }

    var body: some View {
        ZStack {
            journeyStack
        }
        // Deliberately NOT a `.fullScreenCover` or `.sheet`: this view
        // already has an always-on `.sheet` for the docked panel above,
        // and a second real modal presentation competing for that same
        // slot is what once caused "Look Around does nothing" and the
        // docked sheet vanishing afterward. The panel is plain view
        // composition in an overlay — it morphs between its card, split
        // and full-screen frames in place and is never presented.
        .overlay {
            lookAroundOverlay
        }
    }


    // MARK: - Body parts
    // One long modifier chain made the type-checker time out; each part
    // below is type-checked on its own.

    private var journeyBase: some View {
            NavigationStack {
                mapWithPreview
                    .navigationTitle("Journey")
                    .navigationBarTitleDisplayMode(.inline)
                    // Look Around in split/full screen owns the top of
                    // the screen; the bar slides away with the same
                    // transaction as the panel's spring.
                    .toolbar(lookAround.layout.isExpanded ? .hidden : .visible, for: .navigationBar)
                    .toolbar {
                        // Profile on the left, Pasture (the shepherd's screen and
                        // settings) on the right. Codes are typed in the panel.
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                isProfilePresented = true
                            } label: {
                                Image(systemName: "person.crop.circle")
                            }
                            .accessibilityLabel("Profile")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                isPasturePresented = true
                            } label: {
                                Label("Pasture", systemImage: "pawprint.fill")
                                    .labelStyle(.titleAndIcon)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .accessibilityLabel("Pasture and Settings")
                        }
                    }
            }
            .sheet(isPresented: isDockedPanelPresented) {
                dockedPanel
                    // Belt-and-suspenders explicit re-injection, matching
                    // every other `.sheet`/`.fullScreenCover` in this app
                    // (see `RootView`/`PastureView`) — environment values
                    // set on an ancestor don't reliably survive into a
                    // `.sheet`'s content in this codebase (that's exactly
                    // what crashed opening Pasture with "No Observable
                    // object of type LocationService found" until it was
                    // explicitly re-added there), so `ComposeLetterView`
                    // gets the same explicit copy rather than trusting
                    // inheritance alone.
                    .environment(flockViewModel)
                    .environment(letterInbox)
                    .environment(entitlementService)
                    .environment(locationService)
                    .environment(\.locale, currentLocale)
                    .preferredColorScheme(appAppearance.colorScheme)
                    .presentationDetents(Set(panelDetents), selection: $panelDetent)
                    .presentationBackgroundInteraction(.enabled(upThrough: .dockMedium))
                    // No explicit `.presentationBackground` here on purpose:
                    // iOS 26 gives a `.sheet` its Liquid Glass chrome for
                    // free, and any explicit background (a color, or a plain
                    // `.regularMaterial`) opts the sheet OUT of that and back
                    // into a flat classic-Material fill instead — which is
                    // exactly the "painted, not glass" look this panel kept
                    // getting when one was set. Leave this alone even if the
                    // panel looks momentarily flat in Xcode's canvas/preview;
                    // it renders as real Liquid Glass on-device on iOS 26.
                    // A phone-shaped card on iPad too: the form width, and
                    // the medium detent capped (see `dockMedium`).
                    .presentationSizing(.form)
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            }
            .onChange(of: isEnterCodePresented) { _, requested in
                // Other parts of the app still ask for "Enter Code" through
                // this flag (the nearby-sender marker); it now means "show
                // the Code page", never a separate sheet.
                guard requested else { return }
                isEnterCodePresented = false
                showCodePage()
            }
            .onChange(of: isAnotherSheetUp) { _, isUp in
                if isUp {
                    isDockedPanelAllowed = false
                } else {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        if !isAnotherSheetUp { isDockedPanelAllowed = true }
                    }
                }
            }
    }

    private var journeyTracking: some View {
        journeyBase
            .task(id: trackedRam?.id) {
                beginTrackingIfNeeded()
                if let ram = trackedRam {
                    if let origin = ram.originCoordinate, !flownOverRamIds.contains(ram.id) {
                        // A ram just set out (or is being looked at for
                        // the first time): lift off wherever the camera
                        // was — the person's own spot, which may be a
                        // different city — frame the leg, and settle on
                        // `routeCoordinates[0]` in the follow camera.
                        flownOverRamIds.insert(ram.id)
                        camera.flyover(
                            route: ram.routeCoordinates.map(\.clLocationCoordinate),
                            origin: ram.stepsWalked == 0 ? origin : (ram.currentCoordinate ?? origin),
                            reduceMotion: reduceMotion
                        )
                    } else {
                        camera.resumeFollowing(
                            ramCoordinate: ram.currentCoordinate ?? ram.originCoordinate,
                            animated: false
                        )
                    }
                } else {
                    waypointService.clear()
                    locationService.resolveCurrentLocation()
                    camera.centerOnUser(locationService.currentCoordinate, animated: false)
                }
                refreshLookAroundAvailability()
                await advanceLandmarkAndStamps()
                if let ram = trackedRam {
                    await waypointService.refreshIfNeeded(for: ram)
                }
            }
            .task {
                // Polls the anonymous aggregate for as long as the map is
                // on screen; SwiftUI cancels it on disappear, so there's
                // no timer left running behind a dismissed view.
                await flockPulse.poll()
            }
            .onChange(of: flockViewModel.activeRams) { _, rams in
                // The write side of the same aggregate the badge reads:
                // without this, `flock-pulse` would have nothing to count.
                // A snapshot of this carrier's own flock, nothing about
                // any individual letter, recipient or position.
                let active = rams.filter { $0.status == .walking || $0.status == .grazing }.count
                let delivered = rams.filter { $0.status == .delivered }.count
                Task {
                    try? await telemetryService.sendFlockMetric(
                        carrierUserId: carrierUserId,
                        activeRamsCount: active,
                        totalDelivered: delivered
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .firstLetterDispatched)) { _ in
                // A letter this person just sent belongs under Outgoing,
                // not Incoming, where the mailbag opens by default.
                mailbagSection = .outgoing
            }
            .onChange(of: flockViewModel.activeRams.count) { oldCount, newCount in
                // A second ram dispatched from the compose page while
                // the first is still walking doesn't change `trackedRam`
                // (the walking one keeps priority), so the page switch
                // above never fires — do it here for any ram admitted
                // while one is already out.
                guard newCount > oldCount, trackedRam != nil else { return }
                withAnimation {
                    panelPage = .mailbag
                    panelDetent = .dockMedium
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .composeLetterRequested)) { _ in
                // "Send a letter" from the passport: the compose page, not
                // whichever page the panel was last left on.
                mailbagPath.removeAll()
                withAnimation {
                    panelPage = .compose
                    panelDetent = .dockMedium
                }
            }
            .onChange(of: sendToShepherdID) { _, id in
                // A nearby Shepherd ID: open the compose page, in code mode.
                guard id != nil else { return }
                withAnimation {
                    panelPage = .compose
                    panelDetent = .dockMedium
                }
            }
            .onChange(of: pickedDestination) { _, pin in
                // A spot marked in the map picker: hand it to Compose the
                // same way a long-press drop does.
                guard let pin else { return }
                droppedDestination = pin
                pickedDestination = nil
                withAnimation {
                    panelPage = .compose
                    panelDetent = .dockMedium
                }
            }
            .onChange(of: stepTracker.liveStepCount) { _, newValue in
                applyStepDelta(newValue)
            }
            .onChange(of: locationService.currentCoordinate.map { "\($0.latitude),\($0.longitude)" }) { _, _ in
                // Fires on every fix while live tracking (and the moment a
                // one-shot resolve lands). Follows the person only while
                // `isFollowingRam` is still on — a manual pan/zoom turns
                // it off, and "My Location" turns it back on — otherwise
                // a fix every second would snap the camera back and make
                // the map impossible to browse. Never stomps on an
                // in-progress journey's own camera behavior.
                if trackedRam == nil {
                    camera.followUserIfNeeded(locationService.currentCoordinate, animated: true)
                }
                refreshLookAroundAvailability()
            }
    }

    private var journeyStack: some View {
        journeyTracking
            .onChange(of: panelDetent) { _, detent in
                // A ram's bag or letter is pushed inside the mailbag page;
                // once the sheet is dragged back down to a short size there
                // is no room for it, so it folds away to the list.
                if detent != .dockMedium && detent != .large, !mailbagPath.isEmpty {
                    // Next turn of the run loop, never inside the sheet's own
                    // resize pass.
                    Task { @MainActor in
                        if panelDetent != .dockMedium && panelDetent != .large { mailbagPath.removeAll() }
                    }
                }
            }
            .onChange(of: collapsedPanelHeight) { old, new in
                // The short height depends on the tracked ram (a letter at
                // the gate needs more room). Keep a resting sheet glued to it.
                guard panelDetent == .height(old) else { return }
                withAnimation(.snappy) { panelDetent = .height(new) }
            }
            .onChange(of: trackedRam?.status) { old, new in
                // A ram reaching its gate grows the panel so the seal
                // button is right there, not hidden behind a drag.
                guard new == .arrivedAtGate, old != nil else { return }
                withAnimation { panelDetent = .dockMedium }
            }
            .onChange(of: trackedRam?.id) { _, newValue in
                #if DEBUG
                if CommandLine.arguments.contains("-screenshotCompose") {
                    panelPage = .compose
                    panelDetent = .large
                    return
                } else if CommandLine.arguments.contains("-screenshotMap") {
                    panelPage = .mailbag
                    panelDetent = .height(Self.tinyPanelHeight)
                    return
                }
                #endif
                withAnimation {
                    // A ram setting out lands the panel on the mailbag,
                    // where its card now is (the journey page is one swipe
                    // away); the last ram arriving folds it back to the
                    // shortest peek — collapsedPanelHeight is no longer a
                    // real stop, so there's nothing taller-but-short to
                    // rest on instead.
                    panelPage = newValue != nil ? .mailbag : .compose
                    panelDetent = .height(Self.tinyPanelHeight)
                }
            }
            .task {
                // Independent of `trackedRam`/the .task(id:) above: this
                // runs once for the view's lifetime and just keeps a live
                // "steps today" readout going regardless of whether a ram
                // is currently being tracked. Idempotent, so it's safe if
                // SwiftUI ever re-invokes it.
                guard hasCompletedOnboarding else { return }
                stepTracker.startTrackingToday()
            }
            .onAppear {
                #if DEBUG
                if CommandLine.arguments.contains("-screenshotCompose") {
                    panelPage = .compose
                    panelDetent = .large
                } else if CommandLine.arguments.contains("-screenshotMap") {
                    panelPage = .mailbag
                    panelDetent = .height(Self.tinyPanelHeight)
                } else if CommandLine.arguments.contains("-demoMode") {
                    panelPage = .mailbag
                    panelDetent = .dockMedium
                    mailbagSection = .outgoing
                }
                #endif
                // Continuous location + compass heading for as long as the
                // map is on screen: this is what moves the marker as the
                // person walks and turns its heading indicator. Stopped
                // below so the radio isn't left on behind a dismissed map;
                // `resolveCurrentLocation()` still works independently.
                guard hasCompletedOnboarding else { return }
                locationService.startLiveTracking()
            }
            .onChange(of: flockViewModel.activeRams.contains { $0.status == .walking }, initial: true) { _, walking in
                // HealthKit step wakes only while a ram is walking, so an
                // idle pasture never wakes the phone. (No background
                // location: steps keep counting without the app running.)
                BackgroundStepSync.shared.setWalking(walking)
            }
            .onChange(of: hasCompletedOnboarding) { _, completed in
                if completed {
                    locationService.startLiveTracking()
                    stepTracker.startTrackingToday()
                }
            }
            .onDisappear {
                stepTracker.stopTracking()
                locationService.stopLiveTracking()
            }
            // The navigation stack fills the window; its global frame is
            // the window's, which is what the Look Around host measures
            // its safe insets against.
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                windowFrameGlobal = frame
            }
    }
    // MARK: - Look Around host

    /// The coordinate space every Look Around frame is expressed in: a
    /// `GeometryReader` that RESPECTS the safe area, so its origin is the
    /// top-left of the safe region (just under the status bar / Dynamic
    /// Island) and any positive offset in it is tappable by construction.
    /// The status-bar and home-indicator heights are *measured* — the
    /// host's global frame against the window's (`windowFrameGlobal`) —
    /// never read from `safeAreaInsets`, which an overlay can report as
    /// zero; the split and full-screen frames then extend past the host
    /// by exactly those amounts so the imagery still runs edge to edge
    /// while the header and close button are padded back inside the
    /// safe region. The docked sheet's top edge arrives in `.global`
    /// (`mapDockTopGlobalY`) and is converted into host space so the
    /// preview card sits directly above it.
    ///
    /// `onGeometryChange` publishes the split inset back into `@State`
    /// for `mapContent`'s top `safeAreaInset` — the host's geometry is
    /// the window's safe region, so that write can't feed back into its
    /// own layout.
    private var lookAroundOverlay: some View {
        GeometryReader { proxy in
            // The host spans the whole window (it ignores the safe area,
            // below), so `hostFrame.minY` is the window's top and the
            // status-bar / Dynamic-Island / home-indicator heights come
            // from the window's own safe-area insets — a fixed number
            // read straight from UIKit, not a difference of two live
            // SwiftUI frames that can be momentarily stale or zero (which
            // is how the chrome used to slip under the status bar).
            let hostFrame = proxy.frame(in: .global)
            let insets = WindowSafeArea.insets
            let safeSize = CGSize(
                width: max(0, proxy.size.width - insets.left - insets.right),
                height: max(0, proxy.size.height - insets.top - insets.bottom)
            )
            let metrics = LookAroundLayoutMetrics(
                safeSize: safeSize,
                topInset: insets.top,
                bottomInset: insets.bottom,
                dockTopY: mapDockTopGlobalY - padOverlayLift - hostFrame.minY - insets.top
            )
            // With the sheet dragged to `.large` there is no map left
            // above it to preview; the card simply isn't shown then.
            let previewFits = metrics.frame(for: .preview).minY > 44

            if lookAround.layout.isVisible, lookAround.layout.isExpanded || previewFits {
                // `LookAroundLayoutMetrics` frames are in *safe-region*
                // space (origin just below the status bar). The panel
                // fills this window-sized host, so shifting it by the
                // safe insets puts that origin in the right place: the
                // split / full-screen frames' negative `-topInset` then
                // lands exactly on the physical top edge, and the header
                // and close button — padded by the same `topInset` —
                // land just below the Dynamic Island, never in it.
                LookAroundPanel(
                    session: lookAround,
                    metrics: metrics,
                    title: "Look Around",
                    subtitle: lookAroundSubtitle,
                    onExpand: expandLookAround,
                    onCollapse: collapseLookAround,
                    onToggleFullscreen: toggleLookAroundFullscreen
                )
                .offset(x: insets.left, y: insets.top)
                .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        // Host in window space: the panel's origin no longer depends on
        // whether an overlay happens to inherit a safe area.
        .ignoresSafeArea()
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { windowHeight in
            let insets = WindowSafeArea.insets
            let safeHeight = max(0, windowHeight - insets.top - insets.bottom)
            lookAroundSplitInset = (safeHeight * LookAroundLayoutMetrics.splitHeightFraction).rounded()
        }
        .animation(LookAroundLayoutMetrics.transitionSpring, value: lookAround.layout)
        .animation(.smooth(duration: 0.35), value: padOverlayLift)
    }

    /// Where the imagery is of: the tracked ram's spot on its road, or
    /// the person's own.
    private var lookAroundSubtitle: String? {
        if let ram = trackedRam {
            return String(localized: "Where \(ram.name) is now", bundle: .appLanguage, locale: .appLanguage)
        }
        if let city = locationService.currentCityName, !city.isEmpty, city != String(localized: "Current Location", bundle: .appLanguage, locale: .appLanguage) {
            return String(localized: "Near you · \(city)", bundle: .appLanguage, locale: .appLanguage)
        }
        return String(localized: "Near you", bundle: .appLanguage, locale: .appLanguage)
    }

    // MARK: - Docked panel

    /// The single panel docked at the bottom. Its content switches with
    /// `trackedRam` and `panelPage`; the sheet itself is never dismissed, only
    /// resized, so it always reads as one persistent surface rather than
    /// separate screens popping in and out.
    private var dockedPanel: some View {
        // A real `TabView` in `.page` style rather than a manual `Group`
        // swap: this is what makes the horizontal swipe between pages
        // actually work. Its drag recognizer only claims horizontal motion,
        // so it never fights the vertical `ScrollView`s inside a page — the
        // same coexistence Apple's own paged photo viewers rely on. The dots
        // below stay as an explicit, always-visible second way to switch
        // (VoiceOver in particular doesn't get a good swipe gesture from the
        // hidden system page control), so the built-in index display is off.
        //
        // Pages: the mailbag (always), the live journey of the tracked ram
        // (only while one is out), and the compose form.
        // A paging `ScrollView` rather than `TabView(.page)`: the page
        // TabView inside a resizing sheet could stay stuck a few points
        // off-axis after a swipe or a detent change, leaving margin on the
        // right and none on the left. Each page is pinned to the container's
        // exact width, so the insets are always symmetric.
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                composePage
                    .containerRelativeFrame(.horizontal)
                    .id(PanelPage.compose)
                mailbagPage
                    .containerRelativeFrame(.horizontal)
                    .id(PanelPage.mailbag)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: panelPageBinding)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .animation(.easeInOut(duration: 0.25), value: trackedRam?.id)
        // One strip along the bottom on both pages: the code field, and the
        // two page dots at its trailing edge.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The page dots are always there, collapsed or not, so the
            // other page is one tap away at every size.
            // Long sheet: the ear tag field gets its own full-width row right
            // above the page slider. Standard sheet: it shares the row with
            // the slider, as before. `AnyLayout` keeps the field's identity
            // across the switch, so it never loses the cursor mid-focus.
            let stripLayout = panelDetent == .large
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .bottom, spacing: 8))
            stripLayout {
                // Receiving belongs to the mailbag; on the compose page the
                // sheet is about where the letter is going, so the code
                // field stays out of the way there. The compact sheet is
                // just the single featured ram's row — the code field
                // doesn't belong there either, so it's the full Incoming
                // tab or nothing.
                if panelPage == .mailbag, !isPanelTiny, !isPanelCompact, mailbagPath.isEmpty,
                   mailbagSection == .incoming {
                    // `mailbagPath.isEmpty` keeps this to the mailbag's own
                    // top level: a pushed page (the idle bag's "Write a
                    // letter" CTA, a ram's bag, a letter) already has its
                    // own bottom bar, and this code field — irrelevant to
                    // any of those — was sitting underneath it too.
                    CodeEntryBar(
                        relay: relay,
                        code: $codeDraft,
                        focusRequest: codeFocusTick,
                        onOpen: { ram, code in onOpenByCode(ram, code) },
                        onNeedsRoom: {
                            // The keyboard needs the long sheet: at the
                            // standard height it covered the field.
                            if panelDetent != .large {
                                withAnimation { panelDetent = .large }
                            }
                        },
                        onFocusChange: { codeFieldFocused = $0 }
                    )
                    .onAppear {
                        proximity.setEntryListening(true)
                        prefillCodeFromNearby()
                    }
                    .onDisappear {
                        proximity.setEntryListening(false)
                        codeFieldFocused = false
                    }
                    .onChange(of: proximity.state) { prefillCodeFromNearby() }
                } else if isPanelCollapsed, panelPage == .compose || isPanelTiny {
                    // On the dots' own line, so it never steals height from
                    // the form above.
                    Button {
                        withAnimation { panelDetent = .dockMedium }
                    } label: {
                        Label("Expand", systemImage: "chevron.up")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the full letter form")
                } else {
                    // Pushes the dots to the trailing edge in the one-row
                    // strip; takes no room in the stacked long-sheet strip.
                    Color.clear
                        .frame(maxWidth: panelDetent == .large ? 0 : .infinity, maxHeight: 0)
                }
                PanelPageControl(items: panelPageItems, selection: $panelPage)
                    .frame(height: 40)
                    .frame(maxWidth: panelDetent == .large ? .infinity : nil, alignment: .trailing)
            }
            // The whole strip — Expand or the code field, and the dots —
            // sits lower, closer to the bottom edge, so the ram's progress
            // above it has the room.
            // On iPad the sheet has no home-indicator inset to hide in, so the
            // same offset pushed Expand and the dots out of the sheet.
            // Not while typing: the strip then sits on the keyboard, and the
            // offset would slide the field underneath it.
            .offset(y: isPad || codeFieldFocused ? 0 : 20)
            .padding(.horizontal, 16)
            .padding(.bottom, isPad ? 10 : 0)
            .padding(.top, 4)
        }
    }

    /// `scrollPosition(id:)` wants an optional binding; a nil write (which
    /// the scroll view makes transiently) never clears the page.
    private var panelPageBinding: Binding<PanelPage?> {
        Binding(
            get: { panelPage },
            set: { if let newValue = $0 { panelPage = newValue } }
        )
    }

    private var panelPageItems: [PanelPageControl<PanelPage>.Item] {
        [
            .init(page: .compose, title: String(localized: "New Letter", bundle: .appLanguage, locale: .appLanguage)),
            .init(page: .mailbag, title: String(localized: "Mailbag", bundle: .appLanguage, locale: .appLanguage)),
        ]
    }

    /// The mailbag, on its own page: every courier in transit. Tapping a
    /// row opens the ram's bag.
    private var mailbagPage: some View {
        MailbagDrawerView(
            isCollapsed: isPanelCollapsed,
            isCompact: isPanelCompact,
            isTiny: isPanelTiny,
            path: $mailbagPath,
            onShakeHandoff: onManualHoofbeat,
            idleName: ramCompanionStore.companion?.name ?? String(localized: "Your ram", bundle: .appLanguage, locale: .appLanguage),
            onExpand: {
                withAnimation { panelDetent = .dockMedium }
            },
            onWriteLetter: {
                mailbagPath.removeAll()
                withAnimation { panelPage = .compose }
            },
            onClose: {
                collapsePanelToTiny()
            },
            onCancelJourney: { ram in
                withAnimation(.easeInOut(duration: 0.25)) {
                    _ = flockViewModel.recall(ramId: ram.id)
                }
            },
            section: $mailbagSection,
            searchText: $archiveQuery
        )
    }

    /// Folds the docked sheet from any size to the shortest detent.
    ///
    /// The shortest detent, not the taller "collapsed browsing" one — that
    /// mid-height state often has nothing to show but the segmented picker
    /// (no featured courier for the selected tab), which read as a broken,
    /// near-empty sheet. The shortest detent always has content: the one
    /// courier row, or the resting ram.
    ///
    /// The keyboard is dropped first: with the code field focused (an iPad
    /// keeps it up far more readily than an iPhone) the system holds the
    /// sheet at the height the keyboard needs, so the detent change never
    /// visibly landed and Close looked dead.
    private func collapsePanelToTiny() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
        // Pop the pushed screens first and let that finish before the sheet
        // shrinks. Emptying the navigation path and swapping the list for
        // the one-row layout in the same frame, while the sheet is sliding
        // down, is what could take the app down.
        collapseTask?.cancel()
        let hasPushedScreens = !mailbagPath.isEmpty
        if hasPushedScreens { mailbagPath.removeAll() }
        collapseTask = Task { @MainActor in
            if hasPushedScreens { try? await Task.sleep(for: .milliseconds(380)) }
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.35)) { panelDetent = .height(Self.tinyPanelHeight) }
        }
    }

    /// "Enter a code" from elsewhere in the app (the nearby-sender marker):
    /// fill the field with the code a phone nearby is sharing, if any, and
    /// put the cursor in it.
    private func showCodePage() {
        if case .locked(let shared) = proximity.state { codeDraft = shared }
        panelPage = .mailbag
        mailbagSection = .incoming
        withAnimation { panelDetent = .dockMedium }
        codeFocusTick += 1
    }

    /// The compose form, on its own page. Sliding a finished letter to
    /// dispatch with no ram free is what `ComposeLetterView` turns into a
    /// saved draft plus the paywall — nothing here needs to gate it.
    private var composePage: some View {
        ComposeLetterView(
            onDestinationSelected: {
                if !CommandLine.arguments.contains("-screenshotCompose") {
                    withAnimation {
                        panelDetent = .dockMedium
                    }
                }
            },
            onCancel: {
                // Swap the page first, with no animation of its own, so the
                // content is already the mailbag while the sheet is still
                // tall; then let the sheet's own detent animation be the
                // only thing moving. Animating both at once made the
                // close stutter.
                var swap = Transaction()
                swap.disablesAnimations = true
                withTransaction(swap) { panelPage = .mailbag }
                // Back to the shortest detent, not the taller "collapsed
                // browsing" one — closing New Letter should read as
                // dismissing the sheet almost all the way, the same as
                // canceling anywhere else, not settling on a mid-height
                // sheet that looks like it's still half-open.
                panelDetent = .height(Self.tinyPanelHeight)
            },
            onRodeAlong: { ram in
                mailbagSection = .outgoing
                var swap = Transaction()
                swap.disablesAnimations = true
                withTransaction(swap) { panelPage = .mailbag }
                panelDetent = .height(Self.tinyPanelHeight)
                guard let origin = ram.currentCoordinate ?? ram.originCoordinate else { return }
                camera.flyover(
                    route: ram.routeCoordinates.map(\.clLocationCoordinate),
                    origin: origin,
                    reduceMotion: reduceMotion
                )
            },
            relay: relay,
            shepherdIDRequest: $sendToShepherdID,
            nearbyProfileCode: nearbyProfileCode,
            onListenForNearbyCode: { proximity.setEntryListening($0) },
            isPanelExpanded: !isPanelCollapsed,
            droppedDestination: $droppedDestination,
            onChooseOnMap: { isDestinationPickerPresented = true },
            isPanelCompact: isPanelCompact,
            isPanelTiny: isPanelTiny,
            routePreview: $routePreview
        )
    }

    /// The journey page: the compact floating card while the sheet is
    /// collapsed, the full follow view once it's dragged open.
    @ViewBuilder
    private func deliveryPage(for ram: Ram) -> some View {
        if isPanelCollapsed {
            DispatchStatusCard(
                ram: ram,
                headline: waitingHeadline(for: ram),
                isMoving: ram.status == .walking && isPersonMoving,
                onTap: {
                    withAnimation {
                        panelDetent = .dockMedium
                    }
                },
                onBreakSeal: { letterRam = ram }
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            // Scrollable for the same reason Compose is: the sheet's
            // height is a fixed detent, and with the page dots reserving
            // the bottom strip the full journey view no longer has a
            // guaranteed fit at `.medium` on every device.
            ScrollView {
                followContent(for: ram)
            }
        }
    }

    // MARK: - Map

    /// Switches between standard 3D realistic relief up close and hybrid globe view from orbit.
    private var currentMapStyle: MapStyle {
        #if DEBUG
        if CommandLine.arguments.contains("-screenshotMap") || CommandLine.arguments.contains("-screenshotCompose") {
            return .standard(elevation: .realistic)
        }
        #endif
        let distance = camera.currentDistance
        if distance > globeViewDistanceThresholdMeters {
            return .hybrid(elevation: .realistic, showsTraffic: false)
        }
        return .standard(elevation: .realistic)
    }

    /// The map plus the route preview's clock and camera.
    private var mapWithPreview: some View {
        mapContent
            .task(id: routePreview?.key) { await runRoutePreviewClock() }
            .onChange(of: routePreview?.key) { oldKey, newKey in
                handleRoutePreviewChange(oldKey: oldKey, newKey: newKey)
            }
    }

    private func runRoutePreviewClock() async {
        guard routePreview != nil else {
            previewProgress = 0
            return
        }
        if reduceMotion {
            previewProgress = 1
            return
        }
        while !Task.isCancelled {
            // Hold still while the drawing editor is open (see
            // `DoodleActivity`): no state change, no map re-evaluation.
            if !DoodleActivity.isOpen {
                previewProgress = RoutePreviewClock.progress(at: .now)
            }
            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    private func handleRoutePreviewChange(oldKey: String?, newKey: String?) {
        if let routePreview, newKey != nil {
            if oldKey == nil { previewBaselineRamId = trackedRam?.id }
            camera.showRoutePreview(routePreview.path, reduceMotion: reduceMotion)
        } else if oldKey != nil, trackedRam?.id == previewBaselineRamId {
            // Backed out of the letter: return the camera to where it lives.
            if let ram = trackedRam {
                camera.resumeFollowing(ramCoordinate: ram.currentCoordinate ?? ram.originCoordinate, animated: true)
            } else {
                camera.centerOnUser(locationService.currentCoordinate, animated: true)
            }
        }
    }

    /// The planned trip: a faint full path, the part the ram has run drawn
    /// over it, the destination, and the ram itself.
    @MapContentBuilder
    private func routePreviewContent(_ preview: RoutePreview) -> some MapContent {
        MapPolyline(coordinates: preview.path)
            .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 7]))

        MapPolyline(coordinates: preview.trail(upTo: previewProgress))
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

        if let via = preview.via {
            Annotation(preview.viaName ?? "", coordinate: via) {
                Image(systemName: "ferry.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(.regularMaterial, in: Circle())
            }
            .annotationTitles(.hidden)
        }

        Annotation(preview.destinationName, coordinate: preview.destination) {
            Image(systemName: "flag.checkered")
                .font(.callout)
                .foregroundStyle(.primary)
                .padding(8)
                .background(.regularMaterial, in: Circle())
        }
        .annotationTitles(.visible)

        Annotation("", coordinate: preview.point(at: previewProgress)) {
            RamSpriteMarkerView(
                bearingDegrees: preview.bearing(at: previewProgress),
                motionState: previewProgress < 1 ? .moving(speed: 0.7) : .idle,
                markerSize: 40
            )
            .allowsHitTesting(false)
        }
        .annotationTitles(.hidden)
    }

    private var mapContent: some View {
        @Bindable var camera = camera

        return MapReader { proxy in
        Map(position: $camera.position, bounds: MapCameraBounds(maximumDistance: globeDistanceMeters)) {
            // The system's own pulsing blue dot, always — it is a
            // MapKit content item, not view chrome, so it survives every
            // sheet detent, page switch and Look Around stage without
            // any bookkeeping here. While a ram is out it is the one
            // fixed point of orientation ("this is me, the ram is over
            // there"); while idle the ram sprite stands on top of it.
            // MapKit shows it only once location access is granted.
            UserAnnotation()

            // The pin the sender dropped by pressing and holding.
            if let pin = droppedDestination {
                // The system's own map marker — the same balloon Maps uses.
                Marker(pin.name, coordinate: pin.coordinate)
                    .tint(Color.accentColor)
            }

            // Rams that went on with another courier, at the spot they were
            // handed over — so a letter that left your hands is still on
            // your map, with the name of whoever took it.
            ForEach(flockViewModel.activeRams.filter { $0.status == .handedOff && presence.sighting(for: $0.id) == nil }) { ram in
                if let position = ram.currentCoordinate {
                    Annotation(handedOffLabel(for: ram), coordinate: position) {
                        Image(systemName: "figure.walk.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .padding(4)
                            .background(.regularMaterial, in: Circle())
                    }
                    .annotationTitles(.visible)
                }
            }

            // Couriers who said yes in Settings, carrying rams I handed on:
            // roughly where they are (about a kilometre), with who and what.
            ForEach(presence.sightings) { sighting in
                Annotation(sightingLabel(sighting), coordinate: sighting.coordinate) {
                    Image(systemName: "figure.walk.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white, .blue)
                        .padding(4)
                        .background(.regularMaterial, in: Circle())
                }
                .annotationTitles(.visible)
            }

            // Couriers in Bluetooth range right now (Profile's "Couriers
            // Nearby"): no real coordinates, so placed the same
            // deterministic way Profile's own map places them, inside the
            // in-range ring around you.
            if let here = locationService.currentCoordinate {
                // The ring is the honest part: "somewhere in here". The pins inside it are placed for
                // legibility, so they get a dashed halo instead of looking surveyed.
                if !nearbyCouriers.couriers.isEmpty {
                    MapCircle(center: here, radius: 100)
                        .foregroundStyle(.tint.opacity(0.10))
                        .stroke(.tint.opacity(0.6), lineWidth: 1)
                }
                ForEach(nearbyCouriers.couriers) { courier in
                    Annotation(courier.name, coordinate: courier.placed(around: here)) {
                        NearbyCourierMarker(courier: courier, diameter: 34) {
                            withAnimation(.snappy) { selectedNearbyCourier = courier }
                        }
                        .background {
                            Circle()
                                .strokeBorder(.tint.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                .frame(width: 46, height: 46)
                        }
                    }
                    .annotationTitles(.visible)
                }
            }

            // Someone close by is sharing a receiving code (Settings → Nearby).
            if isNearbySenderLocked, let here = locationService.currentCoordinate {
                Annotation("", coordinate: here) {
                    NearbySenderRadar(onTap: onNearbySender)
                }
            }

            if let preview = routePreview {
                routePreviewContent(preview)
            }

            if let ram = trackedRam {
                // While a ram is aboard the packet the leg it is travelling
                // is the crossing, not the road it walked to the quay — so
                // the map draws the sea course and the far port instead of
                // leaving the marker adrift beside a road it has left.
                let seaLeg = (ram.status == .atSea ? ram.voyage : nil)
                let routeCoordinates = (seaLeg?.seaRoute ?? ram.routeCoordinates)
                    .map(\.clLocationCoordinate)

                if routeCoordinates.count > 1 {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(RamMarkerPalette.routeTrail, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 8]))
                }

                if let legEnd = routeCoordinates.last {
                    Annotation(seaLeg?.arrivalPortName ?? ram.legDestinationCity, coordinate: legEnd) {
                        legEndMarker(for: ram)
                    }
                    .annotationTitles(.hidden)
                }

                if let landmark = nextLandmarkService.landmark {
                    Annotation(landmark.name, coordinate: landmark.coordinate.clLocationCoordinate) {
                        nextLandmarkMarker(landmark)
                    }
                    .annotationTitles(.hidden)
                }

                // A just-dispatched ram stands on the polyline's first
                // vertex facing along its first real street segment —
                // `currentBearingDegrees` skips zero-length leading
                // segments so frame 0 is never a north-facing default.
                if let position = ram.currentCoordinate ?? ram.originCoordinate {
                    Annotation("", coordinate: position) {
                        Group {
                            if ram.status == .atSea, let voyage = ram.voyage {
                                // Across the water the ram rides a ship, or
                                // flies when the crossing is an ocean wide.
                                SeaVesselMarker(
                                    isAirplane: voyage.usesAirplane,
                                    bearingDegrees: ram.currentBearingDegrees ?? voyage.bearingDegrees()
                                )
                            } else {
                                ramMarker(
                                    bearingDegrees: ram.currentBearingDegrees ?? ram.originBearingDegrees ?? 0,
                                    motionState: motionState(for: ram),
                                    color: RamColorStore.shared.color(for: ram.name)
                                )
                            }
                        }
                        // Tap the ram to look at the letter it carries.
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard ram.letter != nil else { return }
                            letterRam = ram
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(Text("\(ram.name), carrying a letter"))
                        .accessibilityHint(Text("Opens the letter"))
                    }
                }
            } else if routePreview == nil, let homeCoordinate = locationService.currentCoordinate {
                // No active journey: the ram *is* the person's own puck —
                // it stands at their live location, faces the way they're
                // facing (compass heading, or GPS course once moving), and
                // breaks into its stride whenever they do. `currentCoordinate`
                // is refreshed every fix while `startLiveTracking()` is on
                // (see the `.onAppear` below), so this annotation moves with
                // them instead of freezing on the first city-level fix.
                Annotation("", coordinate: homeCoordinate) {
                    ramMarker(
                        bearingDegrees: locationService.travelBearingDegrees ?? 0,
                        motionState: idleMarkerMotionState
                    )
                }
            }

            // Everyone else, at the only resolution that is anybody's
            // business: a named region and a count. Only while the camera
            // is pulled back far enough that a region genuinely is the
            // unit being looked at — up close it would be both meaningless
            // and misleading, since the marker sits on a region's center,
            // not on anyone in particular.
            if isRegionOverviewVisible {
                ForEach(flockPulse.regions) { region in
                    Annotation(region.name, coordinate: region.coordinate.clLocationCoordinate) {
                        flockRegionMarker(region)
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        // See `currentMapStyle`/`globeViewDistanceThresholdMeters`: this
        // switches to `.hybrid` once zoomed out past a few thousand km,
        // since `.standard` alone never renders the actual 3D globe no
        // matter how far out you pull the camera.
        .mapStyle(currentMapStyle)
        .overlay(alignment: .top) {
            if let courier = selectedNearbyCourier {
                NearbyCourierCard(
                    courier: courier,
                    isSaved: savedCouriers.isSaved(name: courier.name),
                    onToggleSave: { savedCouriers.toggle(courier, at: locationService.currentCoordinate) },
                    onHandOver: onHandOverToNearby.map { handOver in
                        { handOver(courier) }
                    },
                    onSendLetter: onSendLetterToNearby.map { sendLetter in
                        {
                            withAnimation(.snappy) { selectedNearbyCourier = nil }
                            sendLetter(courier)
                        }
                    },
                    onClose: { withAnimation(.snappy) { selectedNearbyCourier = nil } },
                    isConnecting: nearbyCouriers.handoverCourierID == courier.id
                )
                .padding(.top, 8)
            } else if let closest = nearbyCouriers.couriers.first {
                NearbyRangeBadge(count: nearbyCouriers.couriers.count) {
                    withAnimation(.snappy) { selectedNearbyCourier = closest }
                }
                .padding(.top, 8)
            }
        }
        .onChange(of: nearbyCouriers.handoverStartedTick) {
            // The handover has really begun: the banner takes over from the card.
            withAnimation(.snappy) { selectedNearbyCourier = nil }
        }
        .onChange(of: nearbyCouriers.couriers) { _, couriers in
            if let selected = selectedNearbyCourier, !couriers.contains(selected) {
                withAnimation(.snappy) { selectedNearbyCourier = nil }
            }
        }
        .simultaneousGesture(dropPinGesture(proxy))
        // Tells a person-driven pan/zoom/rotate apart from a camera move
        // this view made itself (via `isProgrammaticCameraUpdate`), so
        // only the former breaks `isFollowingRam` — otherwise the user
        // could never zoom out past the ram's tight tracking distance,
        // let alone all the way out to the globe.
        .onMapCameraChange(frequency: .onEnd) { _ in
            camera.noteCameraChangeEnded()
        }
        .overlay(alignment: .bottomLeading) {
            mapControlsOverlay
                .offset(y: -padOverlayLift)
                .animation(.smooth(duration: 0.35), value: padOverlayLift)
        }
        // Where the map's usable area ends at the bottom — the docked
        // sheet's top edge, since the sheet's live detent is reserved as
        // bottom safe area (the last modifier below) and overlays applied
        // inside it honour that. Measured in window coordinates; the
        // Look Around preview card is anchored just above it.
        .overlay(alignment: .bottomTrailing) {
            Color.clear
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .global).maxY
                } action: { maxY in
                    mapDockTopGlobalY = maxY
                }
        }
        .overlay(alignment: .top) {
            // "You are here (Burnaby) • Tap to view" — only while the
            // ram is somewhere the person isn't.
            if !lookAround.layout.isExpanded {
                returnToMePill
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
            }
        }
        .overlay(alignment: .topTrailing) {
            // The steps / flock readouts. While Look Around is expanded
            // they step out entirely, as all secondary map chrome does
            // in Apple Maps. (The Look Around preview card no longer
            // shares this corner — it floats above the docked sheet.)
            if !lookAround.layout.isExpanded {
                VStack(alignment: .trailing, spacing: 8) {
                    if stepTracker.hasStepSource {
                        stepsTodayBadge
                    }

                }
                .padding(.top, 8)
                .padding(.trailing, 12)
                .animation(LookAroundLayoutMetrics.transitionSpring, value: lookAround.layout)
            }
        }
        // Split screen: push the map's visible region into the bottom
        // half, under the Look Around panel. Animated with the panel's
        // own spring, so the camera glides down as the panel grows rather
        // than jumping once it has landed.
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: lookAroundMapTopInset)
                .animation(LookAroundLayoutMetrics.transitionSpring, value: lookAroundMapTopInset)
        }
        .sensoryFeedback(.success, trigger: stampsEarnedTick)
        // Reserves room for the docked search/compose panel at the bottom
        // of the screen so MapKit's own auto-placed UI — the Legal
        // attribution link included — keeps clear of it instead of
        // rendering underneath/overlapping the search card. Tracks the
        // sheet's actual current detent rather than always assuming the
        // collapsed height — otherwise, once the sheet is dragged open to
        // `.medium`/`.large`, the reserved strip stays sized for the
        // collapsed panel and the attribution ends up sitting underneath
        // the now-much-taller sheet instead of clear of it. Applied last,
        // after the round-button overlay above, so it only grows the
        // outer safe area MapKit reads and doesn't shift where those
        // buttons are already positioned.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Eased over the sheet's own settle time, so the map's reserved
            // area follows the sheet instead of snapping ahead of it.
            Color.clear
                .frame(height: reservedBottomInset)
                .animation(.smooth(duration: 0.35), value: reservedBottomInset)
        }
        // Whatever sits behind the map while it re-lays out must be the
        // system background, never the black window behind it.
        .background(Color(uiColor: .systemBackground))
        }
    }

    // MARK: - Dropped destination pin

    /// Press and hold anywhere on the map to mark it as the letter's
    /// destination. Simultaneous, so ordinary pan/zoom is untouched.
    private func dropPinGesture(_ proxy: MapProxy) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onEnded { value in
                guard case .second(true, let drag?) = value,
                      let coordinate = proxy.convert(drag.location, from: .local) else { return }
                dropPin(at: coordinate)
            }
    }

    private func dropPin(at coordinate: CLLocationCoordinate2D) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            let pin = await DroppedDestination.resolve(coordinate)
            droppedDestination = pin
            panelPage = .compose
            withAnimation { panelDetent = .dockMedium }
        }
    }

    /// The profile code a phone nearby is broadcasting, if that is what it is sharing.
    private var nearbyProfileCode: String? {
        if case .locked(let shared) = proximity.state, CourierCodeStore.isAddress(shared) { return shared }
        return nil
    }

    /// A letter code a phone nearby is broadcasting, ready for the Enter Code field.
    private var nearbyLetterCode: String? {
        if case .locked(let shared) = proximity.state, !CourierCodeStore.isAddress(shared) { return shared }
        return nil
    }

    private func prefillCodeFromNearby() {
        guard let shared = nearbyLetterCode, codeDraft.isEmpty else { return }
        codeDraft = shared
    }

    private var isNearbySenderLocked: Bool {
        if case .locked = proximity.state { return true }
        return false
    }

    private func sightingLabel(_ sighting: CarrierPresenceService.Sighting) -> String {
        let ramName = flockViewModel.activeRams.first { $0.id == sighting.ramID }?.name ?? ""
        let carrier = sighting.carrierName.isEmpty ? String(localized: "A courier", bundle: .appLanguage, locale: .appLanguage) : sighting.carrierName
        return ramName.isEmpty ? carrier : "\(carrier) · \(ramName)"
    }

    /// "with Anna" for a ram that was handed on to a named courier.
    private func handedOffLabel(for ram: Ram) -> String {
        let last = ram.stamps.last(where: { $0.kind == .handoff })?.placeName ?? ""
        let carrier = last.replacingOccurrences(of: "Handed to ", with: "")
        return carrier.isEmpty || carrier == "Handed on" ? ram.name : "\(ram.name) · \(carrier)"
    }

    /// How much bottom space to reserve so MapKit's own attribution stays
    /// clear of the docked panel, matched to the panel's actual current
    /// detent rather than a single fixed height.
    private var reservedBottomInset: CGFloat {
        // No docked sheet while Look Around is expanded (see
        // `isDockedPanelPresented`), so nothing to keep clear of.
        if lookAround.layout.isExpanded { return 0 }
        // iPad: the panel is a card, not a full-width bar, and resizing the
        // map's safe area with every detent made the map jump and re-centre
        // (worst when closing). One steady inset instead; the map stays put.
        // The floating map controls and the Look Around card follow the
        // sheet through `padOverlayLift` instead, which only moves overlays.
        if isPad { return collapsedPanelHeight }
        return livePanelHeight
    }

    /// The docked sheet's height at its current detent. Proportional to the
    /// actual window, never a fixed 700 / 420: on a shorter phone those
    /// exceeded the map's own height and squeezed it to nothing, which
    /// showed as the map resizing wildly and a black band under the sheet.
    private var livePanelHeight: CGFloat {
        let window = windowFrameGlobal.height
        guard window > 0 else { return collapsedPanelHeight }
        switch panelDetent {
        case .large:
            return max(collapsedPanelHeight, min(window * 0.85, window - 160))
        case .dockMedium:
            return max(collapsedPanelHeight, min(window * 0.48, dockMediumMaxHeight))
        default:
            return isPanelTiny ? Self.tinyPanelHeight : (isPanelCompact ? Self.compactComposeHeight : collapsedPanelHeight)
        }
    }

    /// How far, on iPad, the sheet's top edge is above (positive) or below
    /// (negative) the steady inset the map reserves there. The map controls
    /// and the Look Around preview card move by exactly this much, so they
    /// ride on the sheet's edge like they do on iPhone, without the map's
    /// own safe area changing (which made the camera jump).
    private var padOverlayLift: CGFloat {
        guard isPad, !lookAround.layout.isExpanded else { return 0 }
        return livePanelHeight - collapsedPanelHeight
    }

    /// A small, purely informational "steps today" readout — the spot
    /// just under the toolbar's Pasture button that a custom compass
    /// briefly occupied before being removed. Deliberately not a
    /// `Button`: it's a live display, not a control, per the explicit ask
    /// that it not be interactive.
    private var stepsTodayBadge: some View {
        VStack(spacing: 2) {
            Image(systemName: "figure.walk")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("\(stepTracker.liveStepsToday)")
                .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .contentTransition(.numericText(value: Double(stepTracker.liveStepsToday)))
                .animation(.snappy, value: stepTracker.liveStepsToday)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // A two-line pill (icon over count) rather than the two sitting
        // side by side on one line — same `.regularMaterial` capsule
        // family as the round map control buttons, just taller than wide
        // instead of a horizontal strip.
        .frame(minWidth: 44)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stepTracker.liveStepsToday) steps today")
    }

    /// Whether the camera is pulled back far enough that "a region" is
    /// the honest unit of what's on screen. Deliberately much lower than
    /// `globeViewDistanceThresholdMeters`: regional presence is worth
    /// seeing while looking at a province, long before the globe.
    private var isRegionOverviewVisible: Bool {
        guard flockPulse.hasPulse else { return false }
        return camera.currentDistance > regionOverviewDistanceThresholdMeters
    }

    /// The aggregate readout: how many rams are walking right now,
    /// everywhere. Sits under the steps badge and is styled as the same
    /// family of floating readout — shorter, because it's secondary to
    /// the person's own steps, and absent entirely when the honest answer
    /// is zero (see `FlockPulseService.hasPulse`).
    private var flockPulseBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("\(flockPulse.activeRams) walking now")
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(flockPulse.activeRams)))
                .animation(.snappy, value: flockPulse.activeRams)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(flockPulse.activeRams) rams walking right now, across everyone")
    }

    /// The next named place ahead, marked on the road itself so the
    /// near-term target is somewhere the person can actually see the ram
    /// approaching — not only a line of text in the panel.
    private func nextLandmarkMarker(_ landmark: NextLandmarkService.Landmark) -> some View {
        VStack(spacing: 4) {
            Image(systemName: landmark.kind.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(landmark.name)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
        }
    }

    /// A region's presence marker: a count, on a region's center. There is
    /// no tap target and nothing to drill into, because there is nothing
    /// further to show — this is the whole of what other people's
    /// participation ever reveals.
    private func flockRegionMarker(_ region: FlockPulseService.Region) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("\(region.activeRams)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(region.activeRams) rams walking in \(region.name)")
    }

    /// The ram marker, with the Look Around heading cone drawn under it
    /// while the imagery is open in split screen. Both live in one
    /// `ZStack` centered on the annotation's coordinate, so the cone's
    /// apex sits exactly on the marker with no offset bookkeeping; the
    /// cone is compensated for the map's own rotation so it stays true
    /// to north however the person has turned the map.
    private func ramMarker(bearingDegrees: Double, motionState: RamMotionState, color: RamColor = .white) -> some View {
        ZStack {
            if lookAround.layout.isExpanded {
                LookAroundHeadingCone(
                    headingDegrees: lookAround.headingDegrees,
                    fieldOfViewDegrees: lookAround.fieldOfViewDegrees,
                    mapHeadingDegrees: camera.currentHeadingDegrees
                )
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            }

            RamSpriteMarkerView(
                bearingDegrees: bearingDegrees,
                motionState: motionState,
                markerSize: 52,
                color: color
            )
        }
        .animation(LookAroundLayoutMetrics.transitionSpring, value: lookAround.layout.isExpanded)
    }

    private func legEndMarker(for ram: Ram) -> some View {
        VStack(spacing: 4) {
            Image(systemName: ram.requiresHandoffAtLegEnd ? "airplane.departure" : "flag.checkered")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(ram.legDestinationCity)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
        }
    }

    // MARK: - Map controls (Find Ram / My Location) and Look Around

    /// The anchor Look Around should preview: the tracked ram's live spot
    /// if one exists, otherwise the carrier's own idle location — so the
    /// preview card appears in both states, not just while tracking.
    private var lookAroundAnchorCoordinate: CLLocationCoordinate2D? {
        trackedRam?.currentCoordinate
            ?? trackedRam?.routeCoordinates.first?.clLocationCoordinate
            ?? locationService.currentCoordinate
    }

    /// The floating control stack docked above the panel, in the same
    /// spot Apple Maps docks its own Look Around/3D/location buttons.
    /// Always visible (not just while a ram is tracked) so "My Location"
    /// is always reachable. Reaching the globe view is now just a normal
    /// pinch-zoom-out (see `globeDistanceMeters`/`.mapCameraBounds` on
    /// `mapContent`), so there's no separate "jump to globe" button here.
    private var mapControlsOverlay: some View {
        VStack(spacing: 12) {
            // No binoculars button here: the floating Look Around
            // preview card (above the docked sheet) is the one entry
            // point, so the same feature is never drawn twice.
            // "Find Ram" only exists while a ram is tracked. With none, it
            // did exactly what "My Location" does — two buttons, one job.
            if trackedRam != nil {
                mapControlButton(
                    systemImage: "scope",
                    accessibilityLabel: String(localized: "Find Ram", bundle: .appLanguage, locale: .appLanguage),
                    tint: camera.isFollowingRam ? Color.primary : Color.accentColor,
                    action: { returnToRam() }
                )
            }

            if sentRams.count > 1 {
                mapControlButton(
                    systemImage: "arrow.triangle.2.circlepath",
                    accessibilityLabel: String(localized: "Next ram", bundle: .appLanguage, locale: .appLanguage),
                    action: { showNextSentRam() }
                )
            }

            mapControlButton(
                systemImage: "location.fill",
                accessibilityLabel: String(localized: "My Location", bundle: .appLanguage, locale: .appLanguage),
                tint: camera.focus == .user ? Color.accentColor : Color.primary,
                action: {
                    locationService.resolveCurrentLocation()
                    if trackedRam == nil {
                        camera.centerOnUser(locationService.currentCoordinate, animated: true)
                    } else {
                        // Looking back at the person while a ram is
                        // tracked elsewhere doesn't lose the ram — the
                        // pill / Find Ram bring the camera back.
                        camera.showUser(locationService.currentCoordinate, animated: true)
                    }
                }
            )
        }
        .padding(.leading, 12)
        // Extra clearance above the docked panel/MapKit's own attribution
        // link, which both sit in this same bottom-leading corner — 12pt
        // read as the "My Location" button sitting right on top of the
        // Apple Maps legal text instead of clear of it.
        .padding(.bottom, 28)
    }

    private func mapControlButton(
        systemImage: String,
        accessibilityLabel: String,
        isLoading: Bool = false,
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 44, height: 44)
            .liquidGlass(in: Circle(), fallbackMaterial: .regularMaterial)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Checked whenever the anchor coordinate's context changes (tracking
    /// starts/stops, or the idle location resolves) so the preview card
    /// can simply not appear at all when there's nothing to show,
    /// rather than appearing, getting tapped, and only then discovering
    /// there's no imagery here.
    private func refreshLookAroundAvailability() {
        guard let coordinate = lookAroundAnchorCoordinate else {
            withAnimation(.snappy) {
                lookAround.update(scene: nil, at: nil)
            }
            return
        }
        // Skipped while the panel is expanded (the person is looking at
        // it) and for moves too small to matter — otherwise every live
        // GPS fix would swap the imagery under them.
        guard lookAround.needsRefresh(for: coordinate), !isResolvingLookAround else { return }

        // MapKit raises an ObjC exception — a crash, not a thrown error —
        // for a request at an invalid coordinate; a ram with no route yet
        // or a stale (0, 0) fix must never get that far.
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        isResolvingLookAround = true
        Task {
            defer { isResolvingLookAround = false }
            let request = MKLookAroundSceneRequest(coordinate: coordinate)
            let scene = try? await request.scene
            // The preview card's appearance/disappearance is what's
            // animated here — the session decides which of those it is.
            withAnimation(.snappy) {
                lookAround.update(scene: scene, at: coordinate)
            }
        }
    }

    /// The heading the radar cone starts from when the panel opens: the
    /// direction the ram is walking, or the person's own travel bearing
    /// while idle — the most honest guess for where the imagery faces,
    /// since MapKit doesn't expose its Look Around camera (see
    /// `LookAroundSession`).
    private var initialLookAroundHeading: Double? {
        trackedRam?.currentBearingDegrees ?? locationService.travelBearingDegrees
    }

    /// Preview card → split screen. One spring drives everything that
    /// moves together: the panel's frame/corners, the map's top inset,
    /// the navigation bar, and the docked sheet stepping aside. The
    /// camera is then re-centered so the marker (and its new cone) lands
    /// inside the map's now-shorter visible region.
    private func expandLookAround() {
        guard lookAround.scene != nil, !lookAround.layout.isExpanded else { return }
        withAnimation(LookAroundLayoutMetrics.transitionSpring) {
            lookAround.expand(initialHeading: initialLookAroundHeading)
        }
        recenterAfterLookAroundLayoutChange()
    }

    /// Split/full screen → preview card, reversing the same transaction.
    private func collapseLookAround() {
        guard lookAround.layout.isExpanded else { return }
        withAnimation(LookAroundLayoutMetrics.transitionSpring) {
            lookAround.collapse()
        }
        recenterAfterLookAroundLayoutChange()
    }

    private func toggleLookAroundFullscreen() {
        withAnimation(LookAroundLayoutMetrics.transitionSpring) {
            lookAround.toggleFullscreen()
        }
    }

    /// The map's safe area just changed shape under the camera. Re-center
    /// on whatever the marker is (ram or self) so it — and the cone — sit
    /// in the visible half, and flag the resulting camera motion as ours
    /// so `onMapCameraChange` doesn't read it as a manual pan and switch
    /// following off.
    private func recenterAfterLookAroundLayoutChange() {
        if let ram = trackedRam {
            camera.recenter(on: ram.currentCoordinate ?? ram.originCoordinate, animated: true)
        } else {
            camera.recenter(on: locationService.currentCoordinate, animated: true)
        }
    }

    // MARK: - Follow (tracking progress)

    private func followContent(for ram: Ram) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // The person, first. A number of kilometers is a fact; someone
            // waiting is a reason to put shoes on. The ram's own name and
            // status drop to the supporting line rather than leading.
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(waitingHeadline(for: ram))
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text("\(ram.name) • \(ram.status.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 0) {
                    Text(ram.remainingSteps.formatted(.number.grouping(.automatic).locale(.appLanguage)))
                        .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText(value: Double(ram.remainingSteps)))
                        .animation(.snappy, value: ram.remainingSteps)

                    Text("steps to go")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // The "Slide to Dispatch" control's in-transit form: the same
            // capsule, now a live strip of the leg with the ram sliding
            // between its origin and destination waypoints.
            TransitProgressStrip(
                progress: ram.progress,
                originLabel: waypointService.waypoints?.origin ?? ram.currentCity,
                midpointLabel: waypointService.waypoints?.midpoint,
                destinationLabel: waypointService.waypoints?.destination ?? ram.legDestinationCity,
                isMoving: ram.status == .walking && isPersonMoving,
                bearingDegrees: ram.currentBearingDegrees ?? ram.originBearingDegrees,
                endsAtHandoff: ram.requiresHandoffAtLegEnd
            )

            // The near-term target, when there is one. Sits directly under
            // the progress bar because it's the thing that's actually
            // reachable today, unlike either number above it.
            if let landmark = nextLandmarkService.landmark {
                nextLandmarkRow(landmark, for: ram)
            }

            routeSummary(for: ram)

            if let latest = ram.stamps.last {
                latestStampRow(latest)
            }

            Text("\(DistanceFormatter.string(forMeters: ram.remainingSteps)) remaining")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if ram.status == .arrivedAtGate {
                BreakSealButton { letterRam = ram }
                    .padding(.top, 4)
            } else if ram.letter != nil {
                Button {
                    letterRam = ram
                } label: {
                    Label("View Letter", systemImage: "envelope")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .padding(.top, 4)
            }

            // Another ram may be standing at a gate while this one is
            // still on the road; the dock shows one ram at a time, so say
            // so instead of leaving the letter unreachable.
            if let waiting = flockViewModel.activeRams.first(where: { $0.status == .arrivedAtGate && $0.id != ram.id }) {
                Button {
                    letterRam = waiting
                } label: {
                    Label("\(waiting.name) is at the gate", systemImage: "door.left.hand.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
            }

            if !ram.isGuest, ram.status == .grazing || ram.status == .walking || ram.status == .waitingForHandoff {
                // Withdrawing a letter is a full slide, never a tap: this
                // sheet gets dragged between detents constantly, and a
                // tappable "Cancel" here would eventually be hit by
                // accident. `FlockViewModel.recall` frees the slot and
                // forgets the seal's code.
                SlideToActionControl(title: "Slide to Recall", role: .recall) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        _ = flockViewModel.recall(ramId: ram.id)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    /// Who this walk is actually for. Falls back to the destination only
    /// when a ram genuinely has no letter yet (freshly dispatched, or
    /// carrying only passengers) — never invents a name.
    private func waitingHeadline(for ram: Ram) -> String {
        if let recipient = ram.letter?.recipientName.trimmingCharacters(in: .whitespacesAndNewlines),
           !recipient.isEmpty {
            return String(format: String(localized: "%@ is waiting", bundle: .appLanguage, locale: .appLanguage), recipient)
        }
        if let passenger = ram.passengerLetters.first?.recipientName.trimmingCharacters(in: .whitespacesAndNewlines),
           !passenger.isEmpty {
            return String(format: String(localized: "%@ is waiting", bundle: .appLanguage, locale: .appLanguage), passenger)
        }
        return String(format: String(localized: "On the way to %@", bundle: .appLanguage, locale: .appLanguage), ram.targetCity)
    }

    private func nextLandmarkRow(_ landmark: NextLandmarkService.Landmark, for ram: Ram) -> some View {
        let stepsAway = max(0, Int(landmark.metersAlongRoute.rounded()) - ram.stepsWalked)

        return HStack(spacing: 8) {
            Image(systemName: landmark.kind.symbolName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\(stepsAway.formatted(.number.grouping(.automatic).locale(.appLanguage))) steps to \(landmark.name)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stepsAway) steps to \(landmark.name)")
    }

    /// The most recent stamp this ram earned — the small, immediate payoff
    /// for the walking already done, kept in the same panel as the target
    /// still ahead. The full page lives in the ram's passport in Pasture.
    private func latestStampRow(_ stamp: JourneyStamp) -> some View {
        HStack(spacing: 6) {
            Image(systemName: stamp.kind.symbolName)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("\(stamp.kind.caption) \(stamp.displayPlaceName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    /// Always shows the full shape of the journey — where the ram set out
    /// from, where it's headed on this leg (a handoff stop, or the letter's
    /// true destination if this leg completes it), and the letter's actual
    /// final destination — so "how far to Gander" never hides "but this is
    /// ultimately going to Frankfurt".
    private func routeSummary(for ram: Ram) -> some View {
        HStack(spacing: 6) {
            routeStop(label: String(localized: "Start", bundle: .appLanguage, locale: .appLanguage), city: ram.currentCity, stage: .completed)

            routeArrow(isActive: true)

            routeStop(
                label: ram.requiresHandoffAtLegEnd ? String(localized: "Handoff", bundle: .appLanguage, locale: .appLanguage) : String(localized: "Now", bundle: .appLanguage, locale: .appLanguage),
                city: ram.legDestinationCity,
                stage: .active
            )

            routeArrow(isActive: false)

            routeStop(label: String(localized: "Final", bundle: .appLanguage, locale: .appLanguage), city: ram.targetCity, stage: .upcoming)
        }
    }

    /// One milestone in the leg: a completed waypoint reads as done and
    /// settled, the current one carries the accent color and the most
    /// weight (it's the thing actually being walked toward right now),
    /// and what's still ahead stays quiet — the same completed/active/
    /// upcoming contrast a checkout or onboarding progress rail uses.
    private enum RouteStopStage {
        case completed, active, upcoming

        var iconName: String {
            switch self {
            case .completed: return "checkmark.circle.fill"
            case .active: return "mappin.circle.fill"
            case .upcoming: return "flag.circle"
            }
        }

        var tint: Color {
            switch self {
            case .completed: return .secondary
            case .active: return .accentColor
            case .upcoming: return .secondary
            }
        }
    }

    private func routeStop(label: String, city: String, stage: RouteStopStage) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: stage.iconName)
                    .font(.system(size: stage == .active ? 13 : 11, weight: .semibold))
                    .foregroundStyle(stage.tint)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(stage == .active ? .primary : .secondary)
                    .textCase(.uppercase)
            }
            Text(city)
                .font(stage == .active ? .subheadline.weight(.bold) : .footnote.weight(.medium))
                .foregroundStyle(stage == .active ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func routeArrow(isActive: Bool) -> some View {
        Image(systemName: "arrow.right")
            .font(.caption.weight(isActive ? .bold : .regular))
            .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
    }

    // MARK: - Step tracking

    /// One pedometer session per tracked ram, started from *now*. If the
    /// tracked ram changes while a session is still running (a ram
    /// dispatched right after another arrived, a handoff import), the old
    /// session is torn down first — otherwise the new ram's first delta
    /// would be measured against the previous ram's baseline and it would
    /// appear partway down its route the moment it was dispatched.
    private func beginTrackingIfNeeded() {
        guard let ram = trackedRam, ram.status == .grazing || ram.status == .walking else {
            stepTracker.stopTracking()
            trackingRamId = nil
            return
        }
        if stepTracker.isTracking, trackingRamId == ram.id { return }

        stepTracker.stopTracking()
        trackingRamId = ram.id
        // Right after launch, pick up from the last saved baseline so steps
        // walked while iOS had terminated the app still reach the ram.
        let resume = BackgroundStepSync.shared.consumeLaunchResumePoint(for: ram)
        lastAppliedStepCount = resume?.alreadyApplied ?? 0
        stepTracker.startTracking(from: resume?.since ?? Date()) { _ in }
    }

    private func applyStepDelta(_ cumulativeSteps: Int) {
        // Steps only ever belong to the ram the tracker was started for.
        guard let ram = trackedRam, trackingRamId == ram.id else { return }
        let delta = max(0, cumulativeSteps - lastAppliedStepCount)
        guard delta > 0 else { return }
        lastAppliedStepCount = cumulativeSteps

        flockViewModel.addStepProgress(ramId: ram.id, steps: delta)
        noteSenderMoving()
        // Re-read after the mutation so the camera eases onto the ram's
        // *new* interpolated position. No-op unless following, and
        // deferred while the dispatch flyover is still in the air.
        camera.followIfNeeded(trackedRam?.currentCoordinate)

        Task {
            await advanceLandmarkAndStamps()
        }

        Task {
            try? await telemetryService.sendRamHop(ramId: ram.id, carrierUserId: carrierUserId, stepsTraveled: delta)
        }
    }

    // MARK: - Landmarks and stamps

    /// Two things, in order: award a stamp if the steps just recorded
    /// carried the ram past the place it was walking toward, then resolve
    /// whatever is next.
    ///
    /// Re-reads `trackedRam` between the two, rather than reusing the copy
    /// it started with — `recordStamp` mutates the flock, and resolving
    /// the next landmark against a pre-stamp copy is exactly how the same
    /// place would get picked as the target a second time.
    private func advanceLandmarkAndStamps() async {
        guard let ram = trackedRam else {
            nextLandmarkService.clear()
            return
        }

        if let landmark = nextLandmarkService.landmark,
           Double(ram.stepsWalked) >= landmark.metersAlongRoute {
            flockViewModel.recordStamp(
                ramId: ram.id,
                placeName: landmark.name,
                kind: landmark.kind,
                coordinate: landmark.coordinate.clLocationCoordinate
            )
            stampsEarnedTick += 1
        }

        guard let refreshedRam = trackedRam else {
            nextLandmarkService.clear()
            return
        }
        await nextLandmarkService.refreshIfNeeded(for: refreshedRam)
    }

    // MARK: - Camera

    /// "Find Ram" and the return pill's way back: following on, camera
    /// eased onto the ram.
    private func returnToRam() {
        guard let ram = trackedRam else { return }
        camera.resumeFollowing(ramCoordinate: ram.currentCoordinate ?? ram.originCoordinate, animated: true)
    }

    /// Meters between the person and the tracked ram's current spot —
    /// `nil` when either is unknown or no ram is tracked.
    private var userToRamOffsetMeters: CLLocationDistance? {
        guard let ram = trackedRam else { return nil }
        return JourneyCameraController.offsetMeters(
            from: locationService.currentCoordinate,
            to: ram.currentCoordinate ?? ram.originCoordinate
        )
    }

    /// The floating "You are here" pill: shown only while a ram is being
    /// tracked somewhere meaningfully away from the person (more than
    /// half a kilometre — a ram dispatched from where they stand needs
    /// no such reminder). Reads the person's city from `LocationService`
    /// and the offset from `userToRamOffsetMeters`. Tapping it looks at
    /// the person; while the camera is there, the same pill offers the
    /// way back to the ram, so it never strands the map on either side.
    @ViewBuilder
    private var returnToMePill: some View {
        if let offset = userToRamOffsetMeters, offset > 500 {
            let isViewingUser = camera.focus == .user
            let city = locationService.currentCityName.map { " (\($0))" } ?? ""
            let distance = DistanceFormatter.string(forMeters: Int(offset.rounded()))
            // Two short lines instead of one long, easily-truncated one:
            // "who/where" leads, "how far, tap to view" trails — this is
            // what stopped the pill's text from colliding with the
            // progress step cards underneath on compact screens.
            let firstLine = isViewingUser ? String(localized: "Ram is \(distance) away", bundle: .appLanguage, locale: .appLanguage) : String(localized: "You are here\(city)", bundle: .appLanguage, locale: .appLanguage)
            let secondLine = isViewingUser ? String(localized: "Tap to view", bundle: .appLanguage, locale: .appLanguage) : String(localized: "\(distance) away • Tap to view", bundle: .appLanguage, locale: .appLanguage)

            Button {
                if isViewingUser {
                    returnToRam()
                } else {
                    camera.showUser(locationService.currentCoordinate, animated: true)
                }
                revealReturnToMePill()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isViewingUser ? "pawprint.fill" : "location.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(firstLine)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(secondLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .opacity(isReturnToMePillVisible ? 1 : 0)
            .allowsHitTesting(isReturnToMePillVisible)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.snappy, value: isViewingUser)
            .animation(.easeOut(duration: 0.25), value: isReturnToMePillVisible)
            .accessibilityLabel(isViewingUser
                                ? "Return to the ram, \(distance) away"
                                : "Return to my location\(city), \(distance) from the ram")
            .onAppear { revealReturnToMePill() }
            .onChange(of: isViewingUser) { _, _ in revealReturnToMePill() }
            .onChange(of: offset) { _, _ in revealReturnToMePill() }
        }
    }

    /// Shows the "You are here"/"Ram is away" pill and (re)arms the timer
    /// that fades it out after a few seconds of nobody touching it. Tapping
    /// the pill, or a significant state change (switching who's being
    /// viewed, the ram/person moving enough to change the distance), calls
    /// this again so the tooltip comes back rather than staying dismissed
    /// forever.
    private func revealReturnToMePill() {
        #if DEBUG
        if CommandLine.arguments.contains("-demoMode") {
            isReturnToMePillVisible = false
            return
        }
        #endif
        withAnimation(.easeOut(duration: 0.2)) {
            isReturnToMePillVisible = true
        }
        returnToMePillDismissTask?.cancel()
        returnToMePillDismissTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                isReturnToMePillVisible = false
            }
        }
    }

    /// Steps just landed: mark the shepherd as moving and (re)arm the
    /// idle timer that clears it after a quiet stretch. Each new delta
    /// restarts the countdown, so the gallop holds steadily through the
    /// pedometer's normal ~2–3 s reporting gaps while walking.
    private func noteSenderMoving() {
        if !isSenderMoving {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSenderMoving = true
            }
        }
        senderIdleTask?.cancel()
        senderIdleTask = Task {
            try? await Task.sleep(for: .seconds(StepTrackerService.movingGracePeriod))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isSenderMoving = false
            }
        }
    }

    /// Whether the person is moving *right now*, from either signal: the
    /// pedometer (a step delta landed within `movingGracePeriod`) or the
    /// GPS stream (`LocationService.isMovingByLocation`). The pedometer
    /// alone was the bug: its first callback can trail the first real
    /// steps by several seconds — and never fires at all on a Simulator
    /// or while driving — so the marker sat in its idle frames while the
    /// person was plainly moving. GPS speed catches both cases.
    private var isPersonMoving: Bool {
        isSenderMoving || locationService.isMovingByLocation
    }

    /// Normalized 0…1 pace for `RamMotionState.moving(speed:)`: step
    /// cadence when we have it (2.5 steps/s ≈ a brisk walk), otherwise
    /// GPS ground speed (2.5 m/s ≈ a jog). Floor of 0.2 so a slow stroll
    /// still visibly runs.
    private var normalizedMovingSpeed: Double {
        let fromCadence = stepTracker.recentCadence / 2.5
        let fromLocation = locationService.currentSpeedMetersPerSecond / 2.5
        return min(1, max(0.2, max(fromCadence, fromLocation)))
    }

    /// Sprite state for the idle-map marker (no ram on a journey): run
    /// while the person moves, stand when they stop.
    private var idleMarkerMotionState: RamMotionState {
        isPersonMoving ? .moving(speed: normalizedMovingSpeed) : .idle
    }

    private func motionState(for ram: Ram) -> RamMotionState {
        switch ram.status {
        case .grazing, .waitingForHandoff, .handedOff, .delivered:
            return .idle
        case .atSea:
            // Aboard the packet: the ram is moving, but not on anyone's
            // legs — it stands on deck while the ship does the work.
            return .idle
        case .walking:
            // Gallop only while the person is actually moving (steps or
            // GPS); otherwise the ram stands at its current point on the
            // route rather than running on the spot.
            guard isPersonMoving else { return .idle }
            return .moving(speed: normalizedMovingSpeed)
        case .arrivedAtGate:
            return .arrived
        }
    }
}

#Preview {
    @Previewable @State var isPasturePresented = false
    JourneyView(
        telemetryService: TelemetryService(),
        carrierUserId: UUID(),
        isPasturePresented: $isPasturePresented,
        letterRam: .constant(nil)
    )
    .environment(FlockViewModel.preview)
    .environment(LocationService())
}

// MARK: - Docked panel detents

/// Tallest the medium detent gets (only iPad ever reaches it).
private let dockMediumMaxHeight: CGFloat = 500

/// Half the screen on a phone; on iPad half the screen would be an enormous
/// card, so the same "medium" is capped to what a tall phone shows.
private struct DockMediumDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        min(context.maxDetentValue * 0.48, dockMediumMaxHeight)
    }
}

extension PresentationDetent {
    /// The docked panel's middle-tall size: the system medium on iPhone, a
    /// capped equivalent on iPad.
    @MainActor static var dockMedium: PresentationDetent {
        UIDevice.current.userInterfaceIdiom == .pad ? .custom(DockMediumDetent.self) : .medium
    }
}
