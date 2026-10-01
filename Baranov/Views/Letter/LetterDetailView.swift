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

    /// The letter is addressed to any of this person's active names
    /// (name, nickname, pen name — see `NameProfile`).
    private var recipientNameMatches: Bool {
        guard let letter else { return false }
        return NameProfile.matches(letter.recipientName)
    }

    /// Precise Geo Drop: only when the sender switched it on in the letter
    /// sheet. Standard letters never trap the recipient in a radius.
    private var isPreciseDrop: Bool { letter?.geofence != nil }

    /// Whether this phone is inside the sender's chosen spot. Always true
    /// for a letter without a Precise Geo Drop.
    private var isAtPreciseSpot: Bool {
        guard let letter, letter.geofence != nil else { return true }
        return !letter.isOutsideGeofence(of: locationService.currentCoordinate)
    }

    /// The ear tag is the real key: a complete code typed here opens the
    /// seal whatever the names say. The writer's own pre-filled code doesn't
    /// turn the sender into the recipient.
    private var codeUnlocks: Bool {
        isEncrypted && hasCompleteCode && !liveRam.isSentByThisPhone
            && !(letter?.requiresNameMatch ?? false)
    }

    /// Who may break the seal: the post office's own delivery, a name match,
    /// or the code. A Precise Geo Drop additionally needs the spot.
    private var passesIdentity: Bool {
        liveRam.addressedToThisPhone || recipientNameMatches || codeUnlocks
    }

    private var isVerifiedRecipient: Bool {
        passesIdentity && isAtPreciseSpot
    }

    /// Someone looking at a letter that's at somebody else's gate: its
    /// sender, or a courier who brought it there.
    private var isDeliverer: Bool {
        !liveRam.addressedToThisPhone && !recipientNameMatches
    }

    private var sealInteraction: HoldToBreakSeal.Interaction {
        guard isAtGate, !isSealBroken else { return .display }
        return isVerifiedRecipient && canBreak ? .hold : .locked
    }

    private var lockedHint: LocalizedStringKey {
        isVerifiedRecipient
            ? "Enter your ear tag to unlock the seal"
            : "Enter the ear tag code to open this seal, or sign in with a name the letter is addressed to."
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
                    VStack(spacing: 20) {
                        envelopeSection

                        if isRevealed, let letter {
                            LetterPaperCard(letter: letter, ram: liveRam, paper: paperStyle)
                                .id("letter")
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        travelLog
                        handoffSection
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
            .background {
                // Embedded in the mailbag sheet, the sheet's glass shows
                // through; the linen only backs the standalone screen.
                if !isEmbedded { LinenSurface().ignoresSafeArea() }
            }
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
                // The writer's phone, and a phone the letter was sealed to by key, already
                // hold the ear tag. Anyone else types it (from the message the sender
                // sent), even when the phone happens to have it stored from a link.
                if enteredCode.isEmpty, let known = letter?.receivingCode,
                   liveRam.isSentByThisPhone || liveRam.addressedToThisPhone || (letter.map(RecipientKeyring.isAddressedToMe) ?? false) {
                    enteredCode = known
                    holdsCode = true
                }
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
            } else if passesIdentity, isPreciseDrop {
                preciseDropNotice
            } else if isDeliverer, let letter {
                VStack(spacing: 14) {
                    gateDeliveryCard(for: letter)
                    codeOverride
                }
            } else {
                LetterGateNoticeView(ram: liveRam, onVerified: {})
            }
        } else if liveRam.status == .handedOff, liveRam.wasDeliveredInPerson,
                  liveRam.isSentByThisPhone, let letter {
            // Handed over in person: the archived copy shows the
            // delivered stamp.
            gateDeliveryCard(for: letter)
        } else {
            transitPill
        }
    }

    // MARK: - Code as master key, Precise Geo Drop

    @State private var showsCodeOverride = false
    @State private var confirmsReceived = false

    /// Not addressed to any of this person's names? The ear tag still opens it.
    @ViewBuilder
    private var codeOverride: some View {
        if letter?.requiresNameMatch == true, !liveRam.isSentByThisPhone {
            Label("The sender made this letter for \(letter?.recipientName ?? "") only. A matching name is needed to open it.", systemImage: "person.badge.key")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if isEncrypted, !liveRam.isSentByThisPhone {
            if showsCodeOverride {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Enter the ear tag code to open this letter.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    codeEntry
                    if let wrongCodeMessage {
                        Label(wrongCodeMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            } else {
                Button { withAnimation(.snappy) { showsCodeOverride = true } } label: {
                    Label("I have the code", systemImage: "key.fill")
                }
                .buttonStyle(ShareCodeGlassButtonStyle(expands: true))
            }
        }
    }

    /// The sender chose a precise spot: the recipient, by name or code, has to be there.
    private var preciseDropNotice: some View {
        let remaining = letter?.geofenceDistanceRemaining(from: locationService.currentCoordinate)
        return VStack(alignment: .leading, spacing: 8) {
            Label("Left at a precise spot", systemImage: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
            if locationService.currentCoordinate == nil {
                Text("Finding where you are…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let remaining {
                Text("Walk to the spot the sender chose. \(DistanceFormatter.string(forMeters: Int(remaining))) to go.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Walk to the spot the sender chose to open it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task { if locationService.currentCoordinate == nil { locationService.resolveCurrentLocation() } }
    }

    // MARK: - Delivering at the gate

    private enum GateDelivery {
        /// The post office is taking it; this phone hasn't reached it yet.
        case handingOver
        /// The relay holds it for the recipient.
        case atPostOffice
        /// The recipient's phone has it.
        case collected
        /// No post office: it's up to the sender or courier.
        case byHand
    }

    private func gateDelivery(for letter: Letter) -> GateDelivery {
        let tracker = LetterTracker.shared
        guard TelemetryService.isServerConfigured, tracker.isTracked(letter) else { return .byHand }
        if tracker.state(for: letter.id) == .collected { return .collected }
        return tracker.wasHandedToPostOffice(letter) ? .atPostOffice : .handingOver
    }

    /// The ram is at the recipient's gate. Once the letter is received
    /// (the post office confirmed it, or the sender marked it handed
    /// over) there is nothing left to do: a stamp replaces the actions.
    @ViewBuilder
    private func gateDeliveryCard(for letter: Letter) -> some View {
        if gateDelivery(for: letter) == .collected || liveRam.status == .handedOff {
            deliveredStamp
        } else {
            gateActionCard(for: letter)
        }
    }

    /// A postmark-style badge: outlined, slightly off-square, low colour.
    private var deliveredStamp: some View {
        Label("Delivered to Recipient", systemImage: "checkmark.seal")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.secondary, lineWidth: 1.5)
            }
            .rotationEffect(.degrees(-3))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
    }

    /// What to do now the ram is at the gate: hand the letter over in
    /// person, or dispatch it through the share sheet. The recipient's name
    /// is already on the envelope above, so it is not repeated here.
    private func gateActionCard(for letter: Letter) -> some View {
        let recipient = letter.recipientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = recipient.isEmpty ? String(localized: "the recipient", bundle: .appLanguage, locale: .appLanguage) : recipient
        let delivery = gateDelivery(for: letter)
        let title: String
        let detail: String
        let symbol: String
        switch delivery {
        case .handingOver:
            title = String(localized: "Handing it to the post office", bundle: .appLanguage, locale: .appLanguage)
            detail = String(localized: "It goes into their mailbag as soon as this phone is online.", bundle: .appLanguage, locale: .appLanguage)
            symbol = "arrow.up.circle"
        case .atPostOffice, .collected:
            title = String(localized: "In their mailbag", bundle: .appLanguage, locale: .appLanguage)
            detail = String(localized: "It lands on their phone the next time Baranov is open.", bundle: .appLanguage, locale: .appLanguage)
            symbol = "tray.and.arrow.down.fill"
        case .byHand:
            title = String(localized: "Ram has arrived at the gate", bundle: .appLanguage, locale: .appLanguage)
            detail = String(localized: "Trek completed. Hand over the letter in person or dispatch via share sheet.", bundle: .appLanguage, locale: .appLanguage)
            symbol = "flag.checkered"
        }

        return VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if delivery != .byHand {
                Text("Meeting them first? You can hand it over yourself.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // The sender keeps both ways of getting the letter across, as
            // the app's glass buttons.
            VStack(spacing: 10) {
                ShareLink(
                    item: LetterTracker.deliveryPackage(of: liveRam, carrying: letter),
                    preview: SharePreview(
                        String(localized: "\(letter.senderName)'s letter for \(to)", bundle: .appLanguage, locale: .appLanguage),
                        image: Image(systemName: "envelope.fill")
                    )
                ) {
                    Label("Share Letter", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(ShareCodeGlassButtonStyle(tint: .accentColor, expands: true))

                if onShakeHandoff != nil {
                    Button { shakeHandoff() } label: {
                        Label("Hand Off Nearby", systemImage: "iphone.gen3.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ShareCodeGlassButtonStyle(expands: true))
                }

                // The code (or tracking link) stays shareable from the archive.
                if let message = liveRam.senderShareMessage(for: letter) ?? liveRam.shareMessage(for: letter) {
                    ShareLink(item: message) {
                        if letter.relayTicket != nil {
                            Label("Share tracking link", systemImage: "link")
                        } else {
                            Label("Share code", systemImage: "number")
                        }
                    }
                    .buttonStyle(ShareCodeGlassButtonStyle(expands: true))
                }
            }

            Button {
                confirmsReceived = true
            } label: {
                Label("Mark as received", systemImage: "checkmark.circle")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.primary)
            .buttonStyle(.borderless)
            .alert("Mark as received?", isPresented: $confirmsReceived) {
                Button("Cancel", role: .cancel) {}
                Button("Mark as received") {
                    flockViewModel.markHandedOff(ramId: ram.id, to: recipient.isEmpty ? nil : recipient)
                }
            } message: {
                Text("Only do this once the recipient has the letter. It moves to your archive and can't be undone.")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
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

    // MARK: - Travel log

    /// Route, progress bar and the three stats in one grouped card.
    private var travelLog: some View {
        LetterTravelLog(
            originName: originName,
            destinationName: liveRam.targetCity,
            progress: journeyProgress,
            stats: stats
        )
    }

    private var stats: [LetterStatsBar.Stat] {
        let walked = liveRam.journeyStepsSoFar
        return [
            .init(id: "walked", symbol: "figure.walk",
                  value: DistanceFormatter.string(forMeters: walked), caption: "walked"),
            .init(id: "steps", symbol: "shoeprints.fill",
                  value: walked.formatted(.number.grouping(.automatic).locale(.appLanguage)), caption: "steps"),
            .init(id: "togo", symbol: "flag.checkered",
                  value: liveRam.remainingSteps > 0 ? DistanceFormatter.string(forMeters: liveRam.remainingSteps) : "0",
                  caption: "to go"),
        ]
    }

    // MARK: - Handoff (port / sea)

    @ViewBuilder
    private var handoffSection: some View {
        if liveRam.hasWaterAhead {
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
        if !isRevealed, let message = liveRam.senderShareMessage {
            ShareLink(item: message) {
                if liveRam.letter?.relayTicket != nil {
                    Label("Share tracking link", systemImage: "square.and.arrow.up")
                } else {
                    Label("Share Code", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(ShareCodeGlassButtonStyle(tint: .accentColor, expands: true))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
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
            try flockViewModel.openDeliveredLetter(
                ramId: ram.id,
                receivingCode: enteredCode,
                currentCoordinate: locationService.currentCoordinate
            )
        } catch {
            wrongCodeTick += 1
            sealResetToken += 1
            withAnimation(.easeOut(duration: 0.2)) {
                wrongCodeMessage = String(localized: "That code doesn't fit this seal. Check the message from \(letter.senderName).", bundle: .appLanguage, locale: .appLanguage)
            }
            return
        }

        // The sender hears about it: a push "… broke the seal" when the post
        // office knows this letter (queued if offline).
        ExpectedLetterStore.shared.noteOpened(letter)

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
