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

    @Environment(FlockViewModel.self) private var flockViewModel
    @Environment(EntitlementService.self) private var entitlementService
    @Environment(\.openURL) private var openURL

    /// The sender's own name, captured once in `OnboardingView`. There is
    /// no field for it in this form — it's used as-is when dispatching.
    @AppStorage("com.baranov.carrierDisplayName") private var storedDisplayName = ""

    @Environment(LocationService.self) private var locationService

    @State private var targetCity = ""
    @State private var targetCoordinate: CLLocationCoordinate2D?
    @State private var handoffCity = ""
    @State private var handoffCoordinate: CLLocationCoordinate2D?

    @State private var ramName = ""
    @State private var showsCustomRamName = false
    @State private var recipientName = ""
    @State private var messageBody = ""
    /// The wax the letter will be sealed with — crimson for everyone,
    /// the rest with the pasture expansion (see `SealColor`).
    @State private var sealColor: SealColor = .crimson
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
    @State private var resolutionError: String?
    @State private var isPasturePaywallPresented = false

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
    private static let fallbackRamNameOptions = [
        "Basalt", "Juniper", "Nimbus", "Clove", "Marrow", "Suede", "Thistle", "Ember",
    ]

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

        for ram in flockViewModel.activeRams {
            add(ram.name)
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
        isDestinationConfirmed || isPanelExpanded
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
    private var missingRequirement: String? {
        if targetCoordinate == nil { return "Pick a destination from the suggestions." }
        if ramName.trimmed.isEmpty { return "Choose a ram to carry it." }
        if recipientName.trimmed.isEmpty { return "Say who the letter is for." }
        if messageBody.trimmed.isEmpty { return "Write a message." }
        if closure == nil { return "Seal the letter with wax, or send it open as a postcard." }
        if needsHandoffCity, handoffPlan == nil, handoffCoordinate == nil {
            return "Pick a handoff city from the suggestions."
        }
        return nil
    }

    private var canSend: Bool {
        missingRequirement == nil
    }

    /// The name stamped on the letter as its sender. Onboarding captures
    /// it once; if that ever comes back empty (a cleared install, a
    /// skipped step), sending still works under a generic name rather
    /// than blocking the whole form on a field it doesn't contain.
    private var senderName: String {
        let trimmed = storedDisplayName.trimmed
        return trimmed.isEmpty ? "A Shepherd" : trimmed
    }

    /// Shown under Send while a tap is waiting on the location fix.
    @State private var isAwaitingLocation = false

    /// What a Send tap found still missing (see `missingRequirement`) —
    /// shown under the button until the form changes.
    @State private var requirementNotice: String?

    var body: some View {
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
        ScrollView {
            VStack(spacing: 0) {
                destinationRow

                if isExpanded {
                    expandedFields
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .onChange(of: missingRequirement) { _, _ in
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
        .task {
            restoreDraftIfNeeded()
        }
        .onDisappear {
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

    // MARK: - Destination

    private var destinationRow: some View {
        Group {
            if isDestinationConfirmed {
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
                    }
                )
            }
        }
        .padding(.horizontal, 20)
        // A bit more breathing room above the destination field — it sits
        // right under the sheet's own drag indicator, and 10pt read as
        // too tight against it.
        .padding(.top, 20)
        .padding(.bottom, isExpanded ? 6 : 0)
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
            .layoutPriority(1)
        }
        .pillFieldBackground()
    }

    // MARK: - Expanded form

    private var expandedFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            fieldSection("Choose Your Ram") {
                ramPicker
            }

            fieldSection("The Letter") {
                VStack(spacing: 10) {
                    ContactSuggestionField(placeholder: "Who is this for?", text: $recipientName) { addressText, coordinate in
                        // Only settles the destination from the
                        // recipient's address when there isn't one
                        // already — a destination the sender explicitly
                        // picked (and is now looking at, confirmed, at
                        // the top of the sheet) should never get silently
                        // swapped out just because they tapped an address
                        // suggestion under the recipient field.
                        guard targetCoordinate == nil else { return }
                        targetCity = addressText
                        targetCoordinate = coordinate
                        locationService.resolveCurrentLocation()
                        onDestinationSelected()
                    }
                    if closure != .sealed {
                        messageField
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }
                }
            }

            fieldSection(closureSectionTitle) {
                closureSection
            }

            if needsHandoffCity {
                handoffSection
            }

            startingLocationNotice

            if let resolutionError {
                Label(resolutionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if let requirementNotice {
                Label(requirementNotice, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            sendButton

            if draftSavedNotice {
                draftSavedRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: draftSavedNotice)
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
        SlideToActionControl(
            title: needsHandoffCity && handoffPlan != nil && !showsManualHandoffField
                ? "Slide to Dispatch via \(handoffCity.trimmed)"
                : "Slide to Dispatch",
            role: .dispatch,
            isBusy: isResolvingRoute || isAwaitingLocation,
            busyTitle: isAwaitingLocation ? "Finding Your Location…"
                : isPlanningHandoff ? "Finding a Port…"
                : "Finding a Route…",
            isReady: canSend
        ) {
            Task { await send() }
        }
        .sensoryFeedback(.warning, trigger: sendAttemptWarningTick)
    }

    @State private var sendAttemptWarningTick = 0

    private func fieldSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - Message (with dictation)

    /// A sheet of paper, not a form field. Serif type (the system's own
    /// New York), a "Dear —," line that fills in as soon as the recipient
    /// is known, today's date and where the letter is being written, room
    /// for a real letter, and a rotating prompt for the blank-page moment.
    /// Nothing here is decoration for its own sake — every part of it is
    /// what a page you'd actually write on has.
    private var messageField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(recipientName.trimmed.isEmpty ? "Dear —," : "Dear \(recipientName.trimmed),")
                    .font(.system(.body, design: .serif).italic())
                    .foregroundStyle(recipientName.trimmed.isEmpty ? .tertiary : .primary)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: recipientName)
                Spacer()
                Text(letterDateline)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            ZStack(alignment: .topLeading) {
                if messageBody.isEmpty {
                    Text(museNudge ?? writingPrompts[promptIndex % writingPrompts.count])
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .allowsHitTesting(false)
                        .id(promptIndex)
                        .transition(.opacity)
                }

                TextField("", text: $messageBody, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(3)
                    .lineLimit(6...16)
                    .focused($isMessageFocused)
            }
            .animation(.easeInOut(duration: 0.25), value: promptIndex)

            HStack(spacing: 14) {
                Text(letterFooter)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: messageWordCount)

                Spacer()

                if messageBody.isEmpty {
                    Button {
                        withAnimation { promptIndex += 1 }
                        promptTick += 1
                        Task { await refreshMuseNudge(force: true) }
                    } label: {
                        HStack(spacing: 4) {
                            if muse.isThinking {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: museNudge == nil ? "arrow.trianglehead.2.clockwise" : "sparkles")
                            }
                            Text("Another nudge")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show another writing prompt")
                }

                Button {
                    messageDictationService.toggleRecording(appendingTo: messageBody)
                } label: {
                    Image(systemName: messageDictationService.isRecording ? "mic.fill" : "mic")
                        .font(.footnote)
                        .foregroundStyle(messageDictationService.isRecording ? Color.red : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dictate Message")
            }
        }
        .padding(14)
        // No stroke/border here anymore — a hard-edged rectangle around
        // a page of handwriting read as a form field, not a letter. The
        // material's own edge plus a hair more elevation while focused
        // is enough to show it's active, without a harsh outline.
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
    }

    @FocusState private var isMessageFocused: Bool
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
    private let writingPrompts: [String] = [
        "Tell them what the light is like where you are right now.",
        "Something you'd never say in a text, because it needs a whole page.",
        "What you were doing an hour ago, in enough detail that they can see it.",
        "A thing they said once that you still think about.",
        "By the time this reaches you, the weather will have changed. Describe today's.",
        "The smallest good thing that happened this week.",
        "Ask them one real question and leave room for the answer.",
        "What you'd want them to know if the ram took a year to arrive.",
    ]

    private var messageWordCount: Int {
        messageBody.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var letterFooter: String {
        let words = messageWordCount
        if words == 0 { return "Sealed in \(sealColor.displayName.lowercased()) wax when it goes." }
        let noun = words == 1 ? "word" : "words"
        return "\(words) \(noun) · sealed in \(sealColor.displayName.lowercased()) wax"
    }

    /// "Burnaby, 16 September" — where and when the letter is being
    /// written, like the top-right corner of a real one.
    private var letterDateline: String {
        let date = Date().formatted(.dateTime.day().month(.wide))
        let place = currentCity.trimmed
        return place.isEmpty || place == "Current Location" ? date : "\(place), \(date)"
    }

    // MARK: - Ram picker

    /// One full-width row, the same pill surface and height as the
    /// destination chip above it and the recipient field below — the way
    /// every row in Apple Maps' directions sheet is the same shape
    /// regardless of what it holds. Tapping it opens a system `Menu` of
    /// the sender's real ram names (plus "Custom Name…"); the row itself
    /// always shows the current pick, so there's no separate chip strip
    /// at a different size.
    private var ramPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Menu {
                ForEach(ramPickerOptions, id: \.self) { name in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            ramName = name
                            showsCustomRamName = false
                        }
                    } label: {
                        if !showsCustomRamName, ramName == name {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }

                Divider()

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showsCustomRamName = true
                        ramName = ""
                    }
                } label: {
                    Label("Custom Name…", systemImage: "pencil")
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "pawprint.circle.fill")
                        .foregroundStyle(.tint)

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
                .pillFieldBackground()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ram")
            .accessibilityValue(ramRowTitle)

            if showsCustomRamName {
                TextField("Ram's Name", text: $ramName)
                    .textFieldStyle(.plain)
                    .pillFieldBackground()
                    .transition(.opacity)
            }
        }
        .onAppear {
            guard ramName.trimmed.isEmpty, !showsCustomRamName,
                  let defaultName = ramPickerOptions.first
            else { return }
            ramName = defaultName
        }
    }

    private var ramRowTitle: String {
        if showsCustomRamName {
            return ramName.trimmed.isEmpty ? "Custom Name" : ramName.trimmed
        }
        return ramName.trimmed.isEmpty ? "Choose a Ram" : ramName.trimmed
    }

    // MARK: - Closing the letter (seal or postcard)

    private var closureSectionTitle: String {
        switch closure {
        case .none: return "Close the Letter"
        case .sealed: return "Sealed"
        case .postcard: return "Open Postcard"
        }
    }

    /// The sender's own signet — the first letter of their name, pressed
    /// into the wax on both ends of the journey.
    private var monogram: String { senderName.sealMonogram }

    private var addressee: String {
        recipientName.trimmed.isEmpty ? "the recipient" : recipientName.trimmed
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

    /// Pick a wax, hold the seal, watch the signet come down. Or don't,
    /// and send it open.
    private var sealingRitual: some View {
        VStack(spacing: 16) {
            waxPicker

            WaxSealPressView(wax: sealColor, monogram: monogram) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    closure = .sealed
                }
            }
            .padding(.top, 4)

            // One atmospheric line instead of a paragraph explaining
            // encryption — the ritual itself (hold, watch the signet
            // drop) already tells the sender this letter is sealed.
            Text("Hold to seal & dispatch")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    closure = .postcard
                }
            } label: {
                Label("Send it open, as a postcard", systemImage: "envelope.open")
                    .font(.footnote.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Which wax to press the signet into. Crimson comes with the app;
    /// the other five come with "Expand the Pasture" — a lock on the chip
    /// says so, tapping one opens the paywall, and nothing here ever
    /// blocks sending.
    private var waxPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Wax")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(sealColor.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(sealColor.color)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 12) {
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
                                    .frame(width: 36, height: 36)
                            }
                            WaxBlobShape()
                                .fill(wax.color.gradient)
                                .frame(width: 28, height: 28)
                                .opacity(isUnlocked ? 1 : 0.45)
                            if !isUnlocked {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isUnlocked ? "\(wax.displayName) wax" : "\(wax.displayName) wax, with Expand the Pasture")
                }
                Spacer()
            }
            .sensoryFeedback(.selection, trigger: waxPickTick)

            if !entitlementService.hasPastureExpansion {
                Text("Crimson is yours. The other waxes come with Expand the Pasture — the colour is the only thing that changes; every seal locks the letter the same way.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The letter has gone into its envelope. The message field above is
    /// hidden while sealed — breaking the seal brings it back.
    private var sealedEnvelopeCard: some View {
        VStack(spacing: 14) {
            SealedEnvelopeView(wax: sealColor, monogram: monogram, addressee: addressee, width: 240)
                .padding(.top, 4)

            VStack(spacing: 3) {
                Label("Sealed in \(sealColor.displayName.lowercased()) wax", systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                Text("Encrypted for the whole journey. \(addressee.capitalizedFirst) opens it at the gate with the receiving code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                sealBrokenTick += 1
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    closure = nil
                }
            } label: {
                Label("Break the seal to edit", systemImage: "seal")
                    .font(.footnote.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .sensoryFeedback(.impact(flexibility: .rigid), trigger: sealBrokenTick)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// No wax: the letter goes as it is.
    private var postcardCard: some View {
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

                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        closure = nil
                    }
                } label: {
                    Label("Seal it instead", systemImage: "seal.fill")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .padding(.top, 2)
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
                HStack(spacing: 12) {
                    Image(systemName: "ferry.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Handoff at \(handoffPlan.gateway.name)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("\(DistanceFormatter.string(forMeters: handoffPlan.leg.distanceMeters)) on foot to the dock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Change") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsManualHandoffField = true
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }

                Text("No road reaches \(targetCity.trimmed) from here — there's water or a closed border in between. \(ramName.trimmed.isEmpty ? "Your ram" : ramName.trimmed) will walk to \(handoffPlan.gateway.name), the nearest port on the way, and board the next packet across. If you find someone crossing sooner, hand the ram to them there and it skips the wait.")
                    .font(.caption)
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
                             ? "No road reaches \(targetCity.trimmed) from here, and none of the nearby ports could be reached by road either. Name a city \(ramName.trimmed.isEmpty ? "your ram" : ramName.trimmed) can walk to; it will look for a crossing from there, or wait for a carrier heading onward."
                             : "\(ramName.trimmed.isEmpty ? "Your ram" : ramName.trimmed) will walk to this city and look for a crossing from there — a scheduled packet, or anyone heading onward.")
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
                        .foregroundStyle(.orange)
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
        draftStore.clear()
        draftSavedNotice = false
        onCancel()
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
                resolutionError = "\(handoffCity.trimmed.isEmpty ? "That city" : handoffCity.trimmed) isn't reachable by road from \(currentCity.trimmed) either. Try a different handoff city."
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
        switch closure {
        case .postcard:
            return Letter.writeOpen(
                senderName: senderName,
                recipientName: recipientName.trimmed,
                messageBody: messageBody.trimmed
            )
        case .sealed, .none:
            return Letter.write(
                senderName: senderName,
                recipientName: recipientName.trimmed,
                messageBody: messageBody.trimmed,
                sealColor: sealColor
            ).letter
        }
    }

    private func dispatch(_ ram: Ram) {
        guard flockViewModel.dispatch(ram) else {
            // The slot was taken between the check in `send()` and now
            // (an AirDrop landing mid-route-resolve) — same answer.
            setAsideForLackOfRam()
            return
        }
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
        isPasturePaywallPresented = true
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
            usesCustomRamName: showsCustomRamName,
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
        showsCustomRamName = draft.usesCustomRamName
        ramName = draft.ramName
        recipientName = draft.recipientName
        messageBody = draft.messageBody
        sealColor = draft.sealColor
        closure = draft.closure.map { $0 == .sealed ? LetterClosure.sealed : .postcard }
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
        showsCustomRamName = false
        recipientName = ""
        messageBody = ""
        sealColor = .crimson
        closure = nil
        resolutionError = nil
        requirementNotice = nil
    }
}

/// How a letter is closed before it travels — see `closure`.
private enum LetterClosure {
    case sealed
    case postcard
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
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
