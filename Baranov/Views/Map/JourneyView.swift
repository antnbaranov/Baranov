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

    @Environment(FlockViewModel.self) private var flockViewModel
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

    init(telemetryService: TelemetryService, carrierUserId: UUID, isPasturePresented: Binding<Bool>) {
        self.telemetryService = telemetryService
        self.carrierUserId = carrierUserId
        _isPasturePresented = isPasturePresented
        // Reads from the same ACIT3855 receiver this view already posts
        // ram hops to, so there is exactly one telemetry host to point at.
        _flockPulse = State(initialValue: FlockPulseService(baseURL: telemetryService.baseURL))
    }

    /// Whether Pasture's modal sheet is up — owned by `RootView` (see the
    /// header doc), passed down purely so `isDockedPanelPresented` below
    /// can hide this view's own docked panel while it's showing.
    @Binding var isPasturePresented: Bool

    @State private var panelDetent: PresentationDetent = .height(88)

    /// Whether the floating "You are here"/"Ram is away" pill is
    /// currently shown — auto-dismissed a few seconds after it appears
    /// (see `revealReturnToMePill`) so it doesn't sit indefinitely over
    /// the progress step cards.
    @State private var isReturnToMePillVisible = true
    @State private var returnToMePillDismissTask: Task<Void, Never>?

    /// Which of the docked panel's pages is showing while a ram is out.
    /// With nothing on the road there is only the compose page and the
    /// dots don't appear; the moment a ram sets out the panel gains a
    /// second page for the journey and lands on it. Composing therefore
    /// stays reachable during a walk (a letter can be written and even
    /// slid to dispatch with the one free ram already out — that's what
    /// sends it to Drafts and opens "Expand the Pasture").
    private enum PanelPage: Hashable {
        case delivery
        case compose
    }

    @State private var panelPage: PanelPage = .compose

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

    /// The docked panel's collapsed height: just the search field while
    /// composing; while a ram is out, room for the compact dispatch card
    /// plus the page dots under it.
    private var collapsedPanelHeight: CGFloat {
        trackedRam == nil ? 88 : 132
    }

    private var isPanelCollapsed: Bool {
        panelDetent == .height(collapsedPanelHeight)
    }

    /// The ram this tab is currently tracking real-world steps for: the one
    /// actively walking, or — if none is — the most recently dispatched ram
    /// still waiting to set out.
    private var trackedRam: Ram? {
        flockViewModel.activeRams.first { $0.status == .walking }
            ?? flockViewModel.activeRams.first { $0.status == .grazing }
            // Nothing is walking, but something may still be moving: a ram
            // aboard the packet crosses on the clock, and the map is the
            // one place that progress is legible. Ranked last so a ram
            // that needs the person's steps always wins the screen.
            ?? flockViewModel.activeRams.first { $0.status == .atSea }
            ?? flockViewModel.activeRams.first { $0.status == .waitingForHandoff }
    }

    /// The docked panel is Journey's own UI — it should disappear while
    /// Pasture's modal sheet is up, and reappear the moment it's
    /// dismissed, rather than floating above it. It also steps aside
    /// while Look Around is expanded (split or full screen), exactly as
    /// Apple Maps drops its place card when Look Around takes the top of
    /// the screen: the bottom half is then a clean map with the marker
    /// and its heading cone, not a map with a sheet over it. The floating
    /// preview card, by contrast, never touches the sheet.
    private var isDockedPanelPresented: Binding<Bool> {
        Binding(
            get: { !isPasturePresented && !lookAround.layout.isExpanded },
            set: { newValue in
                if !lookAround.layout.isExpanded {
                    isPasturePresented = !newValue
                }
            }
        )
    }

    var body: some View {
        ZStack {
            NavigationStack {
                mapContent
                    .navigationTitle("Journey")
                    .navigationBarTitleDisplayMode(.inline)
                    // Look Around in split/full screen owns the top of
                    // the screen; the bar slides away with the same
                    // transaction as the panel's spring.
                    .toolbar(lookAround.layout.isExpanded ? .hidden : .visible, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                isPasturePresented = true
                            } label: {
                                Image(systemName: "pawprint.fill")
                            }
                            .accessibilityLabel("Pasture")
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
                    .environment(locationService)
                    .presentationDetents([.height(collapsedPanelHeight), .medium, .large], selection: $panelDetent)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            }
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
            .onChange(of: flockViewModel.activeRams.count) { oldCount, newCount in
                // A second ram dispatched from the compose page while
                // the first is still walking doesn't change `trackedRam`
                // (the walking one keeps priority), so the page switch
                // above never fires — do it here for any ram admitted
                // while one is already out.
                guard newCount > oldCount, trackedRam != nil else { return }
                withAnimation {
                    panelPage = .delivery
                    panelDetent = .medium
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
            .onChange(of: trackedRam?.id) { _, newValue in
                withAnimation {
                    // A ram setting out lands the panel on its journey
                    // page; the last ram arriving folds it back to the
                    // search field. `collapsedPanelHeight` has already
                    // changed with `trackedRam`, so the height read here
                    // is the right one for the new state.
                    panelPage = newValue != nil ? .delivery : .compose
                    panelDetent = newValue != nil ? .medium : .height(collapsedPanelHeight)
                }
            }
            .task {
                // Independent of `trackedRam`/the .task(id:) above: this
                // runs once for the view's lifetime and just keeps a live
                // "steps today" readout going regardless of whether a ram
                // is currently being tracked. Idempotent, so it's safe if
                // SwiftUI ever re-invokes it.
                stepTracker.startTrackingToday()
            }
            .onAppear {
                // Continuous location + compass heading for as long as the
                // map is on screen: this is what moves the marker as the
                // person walks and turns its heading indicator. Stopped
                // below so the radio isn't left on behind a dismissed map;
                // `resolveCurrentLocation()` still works independently.
                locationService.startLiveTracking()
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
            let hostFrame = proxy.frame(in: .global)
            let metrics = LookAroundLayoutMetrics(
                safeSize: proxy.size,
                topInset: max(0, hostFrame.minY - windowFrameGlobal.minY),
                bottomInset: max(0, windowFrameGlobal.maxY - hostFrame.maxY),
                dockTopY: mapDockTopGlobalY - hostFrame.minY
            )
            // With the sheet dragged to `.large` there is no map left
            // above it to preview; the card simply isn't shown then.
            let previewFits = metrics.frame(for: .preview).minY > 44

            if lookAround.layout.isVisible, lookAround.layout.isExpanded || previewFits {
                LookAroundPanel(
                    session: lookAround,
                    metrics: metrics,
                    title: "Look Around",
                    subtitle: lookAroundSubtitle,
                    onExpand: expandLookAround,
                    onCollapse: collapseLookAround,
                    onToggleFullscreen: toggleLookAroundFullscreen
                )
                .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            (proxy.size.height * LookAroundLayoutMetrics.splitHeightFraction).rounded()
        } action: { splitInset in
            lookAroundSplitInset = splitInset
        }
        .animation(LookAroundLayoutMetrics.transitionSpring, value: lookAround.layout)
    }

    /// Where the imagery is of: the tracked ram's spot on its road, or
    /// the person's own.
    private var lookAroundSubtitle: String? {
        if let ram = trackedRam {
            return "Where \(ram.name) is now"
        }
        if let city = locationService.currentCityName, !city.isEmpty, city != "Current Location" {
            return "Near you · \(city)"
        }
        return "Near you"
    }

    // MARK: - Docked panel

    /// The single panel docked at the bottom. Its content switches with
    /// `trackedRam` and `panelPage`; the sheet itself is never dismissed, only
    /// resized, so it always reads as one persistent surface rather than
    /// separate screens popping in and out.
    private var dockedPanel: some View {
        Group {
            if let ram = trackedRam {
                // A real `TabView` in `.page` style rather than a manual
                // `Group` swap: this is what makes the horizontal swipe
                // between "Delivery" and "New Letter" actually work. Its
                // drag recognizer only claims horizontal motion, so it
                // never fights the vertical `ScrollView`s inside either
                // page — the same coexistence Apple's own paged photo
                // viewers rely on. The dots below stay as an explicit,
                // always-visible second way to switch pages (VoiceOver in
                // particular doesn't get a good swipe gesture from the
                // hidden system page control), so the built-in index
                // display is turned off to avoid showing two sets of dots.
                TabView(selection: $panelPage) {
                    deliveryPage(for: ram)
                        .tag(PanelPage.delivery)
                    composePage
                        .tag(PanelPage.compose)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            } else {
                composePage
                    .transition(.opacity)
            }
        }
        // Sending a letter flips `trackedRam` from nil to the freshly
        // dispatched ram in the very same beat the sheet's own detent
        // grows to `.medium` (see `onChange(of: trackedRam?.id)` below) —
        // without an explicit transition/animation here, the whole
        // compose form was replaced by the tracking view in one instant,
        // uncoordinated frame, which is what read as the sheet "loading
        // strangely" right after tapping Send. A plain cross-fade tied to
        // the same value change keeps that swap looking like one
        // deliberate transition instead of a jump cut.
        .animation(.easeInOut(duration: 0.25), value: trackedRam?.id)
        .animation(.easeInOut(duration: 0.2), value: isPanelCollapsed)
        // The onboarding-style dots, only once there are two pages to
        // show. A `safeAreaInset` rather than a `VStack` so the compose
        // form's own scroll view keeps its content clear of them.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if trackedRam != nil {
                PanelPageControl(
                    items: [
                        .init(page: .delivery, title: "Delivery"),
                        .init(page: .compose, title: "New Letter"),
                    ],
                    selection: $panelPage
                )
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .transition(.opacity)
            }
        }
    }

    /// The compose form, on its own page. Sliding a finished letter to
    /// dispatch with no ram free is what `ComposeLetterView` turns into a
    /// saved draft plus the paywall — nothing here needs to gate it.
    private var composePage: some View {
        ComposeLetterView(
            onDestinationSelected: {
                withAnimation {
                    panelDetent = .medium
                }
            },
            onCancel: {
                withAnimation {
                    panelDetent = .height(collapsedPanelHeight)
                }
            },
            isPanelExpanded: !isPanelCollapsed
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
                isMoving: ram.status == .walking && isPersonMoving
            ) {
                withAnimation {
                    panelDetent = .medium
                }
            }
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

    /// See `globeViewDistanceThresholdMeters` for why this isn't just a
    /// fixed `.standard(elevation: .flat)`.
    private var currentMapStyle: MapStyle {
        // `cameraPosition`'s own `.camera` reflects the live camera as the
        // person pans/zooms (no separate tracked-camera state needed) —
        // falls back to the default tracking distance for `.automatic`/
        // `.region` positions, where there's no `MapCamera` to read yet.
        let distance = camera.currentDistance
        if distance > globeViewDistanceThresholdMeters {
            return .hybrid(elevation: .flat, showsTraffic: false)
        }
        return .standard(elevation: .flat)
    }

    private var mapContent: some View {
        @Bindable var camera = camera

        return Map(position: $camera.position, bounds: MapCameraBounds(maximumDistance: globeDistanceMeters)) {
            // The system's own pulsing blue dot, always — it is a
            // MapKit content item, not view chrome, so it survives every
            // sheet detent, page switch and Look Around stage without
            // any bookkeeping here. While a ram is out it is the one
            // fixed point of orientation ("this is me, the ram is over
            // there"); while idle the ram sprite stands on top of it.
            // MapKit shows it only once location access is granted.
            UserAnnotation()

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
                        ramMarker(
                            bearingDegrees: ram.currentBearingDegrees ?? ram.originBearingDegrees ?? 0,
                            motionState: motionState(for: ram)
                        )
                    }
                }
            } else if let homeCoordinate = locationService.currentCoordinate {
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

                    if flockPulse.hasPulse {
                        flockPulseBadge
                    }
                }
                .padding(.top, 8)
                .padding(.trailing, 12)
                .animation(.snappy, value: flockPulse.hasPulse)
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
            Color.clear.frame(height: reservedBottomInset)
        }
    }

    /// How much bottom space to reserve so MapKit's own attribution stays
    /// clear of the docked panel, matched to the panel's actual current
    /// detent rather than a single fixed height.
    private var reservedBottomInset: CGFloat {
        // No docked sheet while Look Around is expanded (see
        // `isDockedPanelPresented`), so nothing to keep clear of.
        if lookAround.layout.isExpanded { return 0 }
        switch panelDetent {
        case .large:
            return 700
        case .medium:
            return 420
        default:
            return collapsedPanelHeight
        }
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
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
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
    private func ramMarker(bearingDegrees: Double, motionState: RamMotionState) -> some View {
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
                markerSize: 52
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
            if trackedRam != nil {
                mapControlButton(
                    systemImage: "scope",
                    accessibilityLabel: "Find Ram",
                    tint: camera.isFollowingRam ? .primary : .accentColor,
                    action: returnToRam
                )
            }

            mapControlButton(
                systemImage: "location.fill",
                accessibilityLabel: "My Location",
                tint: camera.focus == .user ? .accentColor : .primary,
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
                Circle()
                    .fill(.regularMaterial)

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
                    Text(ram.remainingSteps.formatted(.number.grouping(.automatic)))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
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

            if ram.status == .grazing || ram.status == .walking || ram.status == .waitingForHandoff {
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
            return "\(recipient) is waiting"
        }
        if let passenger = ram.passengerLetters.first?.recipientName.trimmingCharacters(in: .whitespacesAndNewlines),
           !passenger.isEmpty {
            return "\(passenger) is waiting"
        }
        return "On the way to \(ram.targetCity)"
    }

    private func nextLandmarkRow(_ landmark: NextLandmarkService.Landmark, for ram: Ram) -> some View {
        let stepsAway = max(0, Int(landmark.metersAlongRoute.rounded()) - ram.stepsWalked)

        return HStack(spacing: 8) {
            Image(systemName: landmark.kind.symbolName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\(stepsAway.formatted(.number.grouping(.automatic))) steps to \(landmark.name)")
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

            Text("\(stamp.kind.caption) \(stamp.placeName)")
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
            routeStop(label: "Start", city: ram.currentCity, stage: .completed)

            routeArrow(isActive: true)

            routeStop(
                label: ram.requiresHandoffAtLegEnd ? "Handoff" : "Now",
                city: ram.legDestinationCity,
                stage: .active
            )

            routeArrow(isActive: false)

            routeStop(label: "Final", city: ram.targetCity, stage: .upcoming)
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
        lastAppliedStepCount = 0
        stepTracker.startTracking(from: Date()) { _ in }
    }

    private func applyStepDelta(_ cumulativeSteps: Int) {
        guard let ram = trackedRam else { return }
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
            let firstLine = isViewingUser ? "Ram is \(distance) away" : "You are here\(city)"
            let secondLine = isViewingUser ? "Tap to view" : "\(distance) away • Tap to view"

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
        isPasturePresented: $isPasturePresented
    )
    .environment(FlockViewModel.preview)
    .environment(LocationService())
}
