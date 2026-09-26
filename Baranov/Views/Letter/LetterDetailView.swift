//
//  LetterDetailView.swift
//  Baranov
//
//  One letter, as an object. An envelope on a linen tabletop carries the
//  names, a stamp and a postmark; the wax seal on its flap is the only
//  control. Where the ram is decides what the seal does:
//
//  - Still travelling: an intact seal and a small pill with the
//    estimated arrival. Nothing to press.
//  - At the gate, recipient verified: hold the wax for 1.5 s. Haptics
//    build from rigid to heavy, the seal cracks and shatters, the flap
//    swings up, the sheet slides out and unfolds below with the journey
//    passport.
//  - At the gate, not the recipient (or not at the right gate): the seal
//    stays dimmed and the reason is spelled out beneath it.
//
//  This replaces both the Satchel card and `LetterArrivalView` as the
//  place a letter is inspected and opened. It is presented from the
//  courier dock, from a tap on the ram on the map, and by the proximity
//  code flow (`prefilledCode`), always through `RootView`'s single
//  `letterRam` sheet.
//
//  System materials and semantic styles for chrome; physical materials
//  (paper, wax, ink) live in `LetterStationery`.
//

import CoreLocation
import SwiftUI

struct LetterDetailView: View {
    let ram: Ram
    /// A receiving code found nearby (see `ProximityCodeDiscovery`).
    var prefilledCode: String?
    /// Starts the shake handoff (owned by `RootView`, which holds the
    /// relay). Both people then shake; nobody types a name.
    var onShakeHandoff: (() -> Void)? = nil
    /// Pushed inside another `NavigationStack` (the ram's bag): no stack or
    /// close button of its own — the parent's back button does the job.
    var isEmbedded = false

    @Environment(\.dismiss) private var dismiss
    @Environment(FlockViewModel.self) private var flockViewModel
    @Environment(LocationService.self) private var locationService

    @AppStorage("com.baranov.carrierDisplayName") private var storedDisplayName = ""

    // Receiving code
    @State private var enteredCode = ""
    @State private var wrongCodeMessage: String?
    @State private var wrongCodeTick = 0
    @State private var sealResetToken = 0
    @State private var lockedTick = 0
    @FocusState private var isCodeFieldFocused: Bool
    @State private var nearbyCouriers = NearbyCourierService()

    // Opening sequence
    @State private var isSealBroken = false
    @State private var isFlapOpen: Bool
    @State private var isLetterRisen: Bool
    @State private var isSealGone: Bool
    @State private var isRevealed: Bool
    @State private var revealTask: Task<Void, Never>?

    init(ram: Ram, prefilledCode: String? = nil, onShakeHandoff: (() -> Void)? = nil, isEmbedded: Bool = false) {
        self.ram = ram
        self.prefilledCode = prefilledCode
        self.onShakeHandoff = onShakeHandoff
        self.isEmbedded = isEmbedded
        // A letter already read on this device opens straight to its
        // opened state — no replaying the ritual.
        let alreadyOpen = ram.status == .delivered && (ram.letter?.isReadable ?? false)
        _isFlapOpen = State(initialValue: alreadyOpen)
        _isLetterRisen = State(initialValue: alreadyOpen)
        _isSealGone = State(initialValue: alreadyOpen)
        _isRevealed = State(initialValue: alreadyOpen)
    }

    // MARK: - Derived state

    /// The flock's live copy — `ram` is only the value the sheet opened
    /// with, and opening the letter mutates the flock, not that copy.
    private var liveRam: Ram {
        flockViewModel.activeRams.first { $0.id == ram.id } ?? ram
    }

    private var letter: Letter? { liveRam.letter }
    private var isAtGate: Bool { liveRam.status == .arrivedAtGate }
    private var isDelivered: Bool { liveRam.status == .delivered }
    private var isEncrypted: Bool { letter?.isEncrypted ?? true }
    private var hasCompleteCode: Bool { LetterCode.isUsableKey(enteredCode) }
    /// Whether this phone already holds the letter's code, so there is nothing to type.
    @State private var holdsCode = false
    private var canBreak: Bool { !isEncrypted || hasCompleteCode }

    private var paperStyle: PaperStyle {
        PaperStyle(paper: letter?.paper ?? .cream, customHex: letter?.paperCustomHex)
    }

    private var recipientNameMatches: Bool {
        guard let letter else { return false }
        return !storedDisplayName.gateNormalized.isEmpty
            && letter.recipientName.gateNormalized == storedDisplayName.gateNormalized
    }

    /// How far this phone is from the spot where the letter was left;
    /// `nil` while there is no location fix yet.
    private var distanceToGate: CLLocationDistance? {
        guard let here = locationService.currentCoordinate else { return nil }
        return liveRam.distanceToGate(from: here)
    }

    /// Whether the recipient is physically at the pick-up spot — the
    /// letter can only be collected by walking there. `nil` while the
    /// location is still resolving.
    private var isAtPickupSpot: Bool? {
        distanceToGate.map { $0 <= Ram.pickupRadiusMeters }
    }

    private var isVerifiedRecipient: Bool { recipientNameMatches && isAtPickupSpot == true }

    private var sealInteraction: HoldToBreakSeal.Interaction {
        guard isAtGate, !isSealBroken else { return .display }
        return isVerifiedRecipient && canBreak ? .hold : .locked
    }

    private var lockedHint: LocalizedStringKey {
        isVerifiedRecipient
            ? "Enter your ear tag to unlock the seal"
            : "The seal can only be broken by the recipient, standing where the letter was left."
    }

    /// The whole journey, across handoffs, as 0…1.
    private var journeyProgress: Double {
        if isAtGate || isDelivered { return 1 }
        if liveRam.status == .atSea { return liveRam.progress }
        let walked = Double(liveRam.journeyStepsSoFar)
        let total = walked + Double(liveRam.remainingSteps)
        return total > 0 ? min(1, walked / total) : 0
    }

    private var originName: String {
        liveRam.stamps.first { $0.kind == .setOut }?.placeName ?? liveRam.currentCity
    }

    // MARK: - Body

    var body: some View {
        if isEmbedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
        Group {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        envelopeSection
                        routeSection
                        LetterStatsBar(stats: stats)
                        handoffSection

                        if isRevealed, let letter {
                            LetterPaperCard(letter: letter, ram: liveRam, paper: paperStyle)
                                .id("letter")
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: isRevealed) { _, revealed in
                    guard revealed else { return }
                    withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo("letter", anchor: .top) }
                }
            }
            .background { LinenSurface().ignoresSafeArea() }
            .navigationTitle(liveRam.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isEmbedded {
                    ToolbarItem(placement: .topBarLeading) {
                        CloseToolbarButton { dismiss() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { shareCodeBar }
            .sensoryFeedback(.error, trigger: wrongCodeTick)
            .sensoryFeedback(.warning, trigger: lockedTick)
            .sensoryFeedback(.impact(weight: .light), trigger: isLetterRisen)
            .animation(.snappy, value: isAtGate)
            .animation(.snappy, value: isVerifiedRecipient)
            .animation(.snappy, value: hasCompleteCode)
            .task {
                if locationService.currentCoordinate == nil {
                    locationService.resolveCurrentLocation()
                }
                if enteredCode.isEmpty, let found = prefilledCode { enteredCode = found }
                if enteredCode.isEmpty, let known = letter?.receivingCode { enteredCode = known; holdsCode = true }
            }
            .onDisappear { revealTask?.cancel() }
        }
    }

    // MARK: - Envelope

    private var envelopeSection: some View {
        VStack(spacing: 18) {
            if let letter {
                LetterEnvelopeView(
                    senderName: letter.senderName,
                    recipientName: letter.recipientName,
                    paper: paperStyle,
                    sentDate: letter.createdAt,
                    distanceText: DistanceFormatter.string(forMeters: liveRam.journeyStepsSoFar),
                    isOpen: isFlapOpen,
                    isLetterRisen: isLetterRisen
                ) {
                    if !isSealGone { seal(for: letter) }
                }
                .frame(maxWidth: 400)
            } else {
                ContentUnavailableView("Letter Missing", systemImage: "envelope.badge.exclamationmark")
            }

            prompt
        }
    }

    private func seal(for letter: Letter) -> some View {
        HoldToBreakSeal(
            kind: isEncrypted
                ? .wax(letter.sealColor, monogram: letter.senderName.sealMonogram)
                : .postcard,
            interaction: sealInteraction,
            diameter: 62,
            isBroken: isSealBroken,
            resetToken: sealResetToken,
            ringColor: paperStyle.ink,
            lockedHint: lockedHint,
            onLockedTap: lockedSealTapped,
            onBroken: breakSeal
        )
    }

    // MARK: - Prompt under the envelope

    @ViewBuilder
    private var prompt: some View {
        if isDelivered || isSealBroken {
            EmptyView()
        } else if isAtGate {
            if isVerifiedRecipient {
                VStack(spacing: 16) {
                    Text(holdPrompt)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(canBreak ? .primary : .secondary)
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)

                    if isEncrypted { if holdsCode { codeOnPhoneNote } else { codeEntry } } else { postcardNote }

                    if let wrongCodeMessage {
                        Label(wrongCodeMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.accentColor)
                            .transition(.opacity)
                    }
                }
            } else {
                LetterGateNoticeView(ram: liveRam, onVerified: {})
            }
        } else {
            transitPill
        }
    }

    private var holdPrompt: LocalizedStringKey {
        if !isEncrypted { return "Hold to lift the postcard out" }
        return hasCompleteCode
            ? "Hold the wax to read the letter"
            : "Enter your ear tag to unlock the seal"
    }

    private var postcardNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "envelope.open")
                .foregroundStyle(.secondary)
            Text("This one travelled open, as a postcard — no seal, no code. Just lift it out.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var codeOnPhoneNote: some View {
        Label("Your ear tag is on this phone.", systemImage: "key.fill")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ear tag")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .foregroundStyle(.secondary)
                TextField("XXXX-XXXX-XXXX", text: $enteredCode)
                    .font(.title3.weight(.semibold).monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)
                    .focused($isCodeFieldFocused)
                    .onChange(of: enteredCode) {
                        if wrongCodeMessage != nil {
                            withAnimation { wrongCodeMessage = nil }
                        }
                    }
                if hasCompleteCode {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("The ram carried only ciphertext. The ear tag you were given is the key.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - In transit

    private var transitPill: some View {
        Label {
            transitPillText
        } icon: {
            Image(systemName: liveRam.status.symbolName)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var transitPillText: some View {
        switch liveRam.status {
        case .walking, .grazing:
            if let arrival = estimatedArrival {
                if liveRam.requiresHandoffAtLegEnd {
                    Text("Next handoff \(arrival, format: .dateTime.month(.abbreviated).day())")
                } else {
                    Text("Estimated arrival \(arrival, format: .dateTime.month(.abbreviated).day())")
                }
            } else {
                Text(LocalizedStringKey(liveRam.status.displayName))
            }
        case .atSea:
            if let voyage = liveRam.voyage {
                Text("In port \(voyage.arrivesAt, format: .relative(presentation: .named))")
            } else {
                Text(LocalizedStringKey(liveRam.status.displayName))
            }
        default:
            Text(LocalizedStringKey(liveRam.status.displayName))
        }
    }

    /// A pace-based guess: the journey's own average steps per day once
    /// there is enough of it to mean something, a typical day's walk
    /// before that. Only offered while the ram is on someone's feet.
    private var estimatedArrival: Date? {
        let remaining = Double(liveRam.remainingSteps)
        guard remaining > 0 else { return nil }
        var stepsPerDay = 6_000.0
        if let start = letter?.createdAt {
            let days = Date.now.timeIntervalSince(start) / 86_400
            let walked = Double(liveRam.journeyStepsSoFar)
            if days >= 0.25, walked >= 500 {
                stepsPerDay = min(30_000, max(1_000, walked / days))
            }
        }
        return Date.now.addingTimeInterval(remaining / stepsPerDay * 86_400)
    }

    // MARK: - Route and stats

    private var routeSection: some View {
        LetterRouteIndicator(
            originName: originName,
            destinationName: liveRam.targetCity,
            progress: journeyProgress
        )
        .padding(.horizontal, 4)
    }

    private var stats: [LetterStatsBar.Stat] {
        let walked = liveRam.journeyStepsSoFar
        return [
            .init(id: "walked", symbol: "figure.walk",
                  value: DistanceFormatter.string(forMeters: walked), caption: "walked"),
            .init(id: "steps", symbol: "shoeprints.fill",
                  value: walked.formatted(.number.grouping(.automatic)), caption: "steps"),
            .init(id: "togo", symbol: "flag.checkered",
                  value: liveRam.remainingSteps > 0 ? DistanceFormatter.string(forMeters: liveRam.remainingSteps) : "0",
                  caption: "to go"),
        ]
    }

    // MARK: - Handoff (port / sea)

    @ViewBuilder
    private var handoffSection: some View {
        if liveRam.status == .waitingForHandoff || liveRam.status == .atSea {
            VStack(alignment: .leading, spacing: 12) {
                PassageNoticeView(ram: liveRam)

                if liveRam.status == .waitingForHandoff {
                    nearbyCouriersList
                    VStack(alignment: .leading, spacing: 8) {
                        if onShakeHandoff != nil {
                            Button { shakeHandoff() } label: {
                                Label("Shake to Hand Off", systemImage: "iphone.gen3.radiowaves.left.and.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.accentColor)
                        }
                        HStack(spacing: 10) {
                            ShareLink(
                                item: RamTransitPackage(ram: liveRam),
                                preview: SharePreview(
                                    "\(liveRam.name) → \(liveRam.legDestinationCity)",
                                    image: Image(systemName: "pawprint.circle.fill")
                                )
                            ) {
                                Label("AirDrop", systemImage: "airplane.departure")
                            }
                            Button("It went with someone", systemImage: "checkmark.circle") {
                                flockViewModel.markHandedOff(ramId: ram.id, to: nil)
                            }
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            .transition(.opacity)
            .task { nearbyCouriers.start(announce: nil) }
            .onDisappear { nearbyCouriers.stop() }
        }
    }

    /// Couriers standing close by, the ones heading the same way first.
    /// AirDrop cannot address a person, so this just says who to ask.
    @ViewBuilder
    private var nearbyCouriersList: some View {
        let sorted = nearbyCouriers.couriers.sorted {
            ($0.isGoingSameWay(as: liveRam) ? 0 : 1) < ($1.isGoingSameWay(as: liveRam) ? 0 : 1)
        }
        if !sorted.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Couriers Nearby", systemImage: "person.2.wave.2")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(sorted) { courier in
                    let sameWay = courier.isGoingSameWay(as: liveRam)
                    Button { shakeHandoff() } label: {
                    HStack(spacing: 10) {
                        CourierAvatarView(image: nil, name: courier.name, diameter: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(courier.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(courier.tripCity.isEmpty
                                 ? LocalizedStringKey("Open to carry")
                                 : LocalizedStringKey("Heading to \(courier.tripCity)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if sameWay {
                            Text("Same way")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.vertical, 3)
                                .padding(.horizontal, 8)
                                .background(.thinMaterial, in: Capsule())
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Starts a handoff. You both shake your phones."))
                }
                Text("Tap a courier or Shake to Hand Off, then you both shake your phones.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .sensoryFeedback(.selection, trigger: sorted.count)
        }
    }

    private func shakeHandoff() {
        dismiss()
        onShakeHandoff?()
    }

    // MARK: - Share code (secondary)

    /// The sender can still hand the receiving code over out of band, but
    /// it is a small bordered button at the foot of the screen, not the
    /// headline. Only the writer's own device holds the code.
    @ViewBuilder
    private var shareCodeBar: some View {
        if !isRevealed, let message = letter?.shareMessage(carrierName: liveRam.name) {
            ShareLink(item: message) {
                Label("Share Code", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    // MARK: - Actions

    private func lockedSealTapped() {
        if isAtGate, isVerifiedRecipient, !canBreak {
            isCodeFieldFocused = true
        } else {
            lockedTick += 1
        }
    }

    /// The letter is ciphertext until this moment and the ram never
    /// carried the key: a wrong code leaves the seal intact and buzzes.
    /// Success runs the reveal in four beats, each waiting for the last —
    /// shatter, flap, sheet slides out, sheet unfolds below.
    private func breakSeal() {
        guard canBreak, let letter else {
            isCodeFieldFocused = true
            sealResetToken += 1
            return
        }
        do {
            try flockViewModel.openDeliveredLetter(ramId: ram.id, receivingCode: enteredCode)
        } catch {
            wrongCodeTick += 1
            sealResetToken += 1
            withAnimation(.easeOut(duration: 0.2)) {
                wrongCodeMessage = String(localized: "That code doesn't fit this seal. Check the message from \(letter.senderName).")
            }
            return
        }

        isCodeFieldFocused = false
        withAnimation { wrongCodeMessage = nil }
        withAnimation(.easeOut(duration: 0.2)) { isSealBroken = true }
        SoundEffectPlayer.shared.play(.waxShatter)

        let isPostcard = !isEncrypted
        revealTask?.cancel()
        revealTask = Task {
            try? await Task.sleep(for: .milliseconds(isPostcard ? 150 : 450))
            guard !Task.isCancelled else { return }
            SoundEffectPlayer.shared.play(.paperRustle)
            isFlapOpen = true

            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            isLetterRisen = true

            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            isSealGone = true
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { isRevealed = true }
        }
    }
}

private extension String {
    /// Case-, diacritic- and whitespace-insensitive form for comparing a
    /// stored display name or city against another — the same
    /// normalization the gate check uses.
    var gateNormalized: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

#Preview {
    LetterDetailView(ram: FlockViewModel.preview.activeRams[0])
        .environment(FlockViewModel.preview)
        .environment(LocationService())
}
