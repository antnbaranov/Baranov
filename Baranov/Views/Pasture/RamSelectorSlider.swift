//
//  RamSelectorSlider.swift
//  Baranov
//
//  The ram selector: one big card at a time, one slot per swipe —
//  `FlockViewModel.pastureCapacity` slots total, not just however many
//  rams are actually active. A slot past `unlockedSlots` is real and
//  swipeable too, just locked: a padlock, and a transparent Liquid
//  Glass "Let Them Graze" button (`.buttonStyle(.glass)` on iOS 26+,
//  falling back to a plain thinMaterial capsule before that) that opens
//  the same
//  RevenueCat paywall the slot-indicator row's own lock marks do — so
//  the person can actually see what they'd be unlocking, not just a dot.
//
//  Switching slots (by tapping a slot-indicator dot, or swiping) plays a
//  fixed, one-directional walk, regardless of which way the swipe or tap
//  went: whichever slot is currently on screen slides off to the right —
//  frame by frame through \`RamSpriteFrameSets.walkCycle\` for a real
//  ram/companion, and — for now, same sprite — a locked slot too, so a
//  locked pasture reads as "another ram waiting to be let in," not a
//  dead end; only a genuinely empty (unlocked, unused) slot has nothing to
//  animate and just slides — until it's off the card; the newly selected
//  slot then enters the same way from the left, and turns to face the
//  person once centered (\`RamSpriteFrameSets.faceCameraFrame\`) unless
//  it's the empty slot. That's why \`RamSelectorStage\`
//  below never gets torn down and recreated on a switch the way a
//  `.transition`-driven view would: it stays mounted for the life of the
//  card and drives its own offset/frame state across the whole
//  walk-out → swap → walk-in sequence, which is also what lets the
//  *outgoing* ram visibly keep walking as it leaves instead of just
//  sliding off already-frozen in its resting pose.
//
//  A locked slot's ram has no identity yet, so tapping its portrait
//  doesn't bleat and there's no name underneath — just the "Locked" label
//  and the (now bigger, two-line) "Let Them Graze" button underneath that,
//  which opens the RevenueCat paywall the same as tapping a locked dot in
//  the indicator row below does.
//
//  Two taps on a real ram/companion's card do different things: tapping
//  the portrait plays a bleat (`RamBleatPlayer`) with a light haptic —
//  petting the ram; tapping its name underneath opens the rename prompt.
//
//  Below the card, a compact row of slot indicators — one per pasture
//  slot — shows which are occupied (and which of those is currently on
//  screen), which are still open, and which are locked. Tapping any dot
//  jumps the big card straight to that slot.
//

import SwiftUI
import UIKit

struct RamSelectorSlider: View {
    let rams: [Ram]
    let capacity: Int
    let unlockedSlots: Int
    @Binding var selectedRamId: UUID?
    let onRentTapped: () -> Void
    let onNameTapped: (Ram) -> Void

    /// Names of the unlocked slots that don't have a journey yet, by
    /// absolute slot index — each is a ram of its own waiting in the
    /// pasture. `namedOpenSlots` are the ones the person already named
    /// (a slot can be named once).
    var openSlotNames: [Int: String] = [:]
    var namedOpenSlots: Set<Int> = []
    var onOpenSlotNameTapped: (Int) -> Void = { _ in }

    /// The person's own default ram — shown resting in the big card
    /// instead of an empty placeholder whenever `rams` is empty, since
    /// onboarding guarantees this exists before any letter is ever sent.
    let companion: RamCompanion?
    let onCompanionNameTapped: () -> Void

    /// Which of the `capacity` slots the big card is currently showing —
    /// independent of `selectedRamId`, since a locked or empty slot has
    /// no ram to select at all. Synced *to* `selectedRamId` (one-way)
    /// whenever it lands on a real ram, so the rest of Pasture stays in
    /// step with whatever's on screen here.
    @State private var displayedSlotIndex = 0
    @State private var hasSyncedInitialSlot = false

    /// How far a horizontal drag has to travel before it counts as a
    /// deliberate swipe to the next/previous slot, rather than an
    /// incidental touch-move (petting the portrait, for instance).
    private static let swipeThreshold: CGFloat = 50

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard capacity > 1 else { return }
                if value.translation.width < -Self.swipeThreshold, displayedSlotIndex < capacity - 1 {
                    displayedSlotIndex += 1
                } else if value.translation.width > Self.swipeThreshold, displayedSlotIndex > 0 {
                    displayedSlotIndex -= 1
                }
            }
    }

    var body: some View {
        VStack(spacing: 10) {
            RamSelectorStage(
                rams: rams,
                capacity: capacity,
                unlockedSlots: unlockedSlots,
                companion: companion,
                slotIndex: displayedSlotIndex,
                openSlotNames: openSlotNames,
                namedOpenSlots: namedOpenSlots,
                onOpenSlotNameTapped: onOpenSlotNameTapped,
                onNameTapped: onNameTapped,
                onCompanionNameTapped: onCompanionNameTapped,
                onRentTapped: onRentTapped
            )
            .frame(height: 190)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(swipeGesture)

            slotIndicator
        }
        .sensoryFeedback(.selection, trigger: displayedSlotIndex)
        .onAppear {
            guard !hasSyncedInitialSlot else { return }
            hasSyncedInitialSlot = true
            if let id = selectedRamId, let index = rams.firstIndex(where: { $0.id == id }) {
                displayedSlotIndex = index
            }
        }
        .onChange(of: displayedSlotIndex) { _, newIndex in
            guard rams.indices.contains(newIndex) else { return }
            selectedRamId = rams[newIndex].id
        }
    }

    private var slotIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<capacity, id: \.self) { index in
                slotIndicatorMark(at: index)
                    .onTapGesture {
                        if index >= unlockedSlots, index >= rams.count {
                            onRentTapped()
                        } else {
                            displayedSlotIndex = index
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func slotIndicatorMark(at index: Int) -> some View {
        let isCurrent = index == displayedSlotIndex
        // With no real rams yet, the companion is still occupying the
        // first slot in every way that matters visually — its dot reads
        // as filled/current too, rather than looking like an open slot
        // sitting right under a ram that's clearly on screen.
        let isCompanionRestingSlot = rams.isEmpty && companion != nil && index == 0

        Group {
            if index < rams.count || isCompanionRestingSlot {
                Circle()
                    .fill(isCurrent ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 7, height: 7)
            } else if index < unlockedSlots {
                Circle()
                    .strokeBorder(isCurrent ? Color.accentColor : Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2]))
                    .frame(width: 7, height: 7)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(isCurrent ? Color.accentColor : Color(uiColor: .tertiaryLabel))
            }
        }
        .frame(width: 18, height: 18)
        .contentShape(Rectangle())
    }
}

private extension Array {
    /// Clamps into bounds instead of trapping — used only for indexing
    /// into small, fixed-size sprite-frame arrays where a value could
    /// momentarily lag a phase change by a frame.
    subscript(safeIndex index: Int) -> Element {
        self[Swift.min(Swift.max(index, 0), count - 1)]
    }
}

/// Owns the big card's identity and its own walk choreography — see the
/// header doc for why this stays mounted across a switch instead of being
/// swapped via `.id`/`.transition`.
private struct RamSelectorStage: View {
    let rams: [Ram]
    let capacity: Int
    let unlockedSlots: Int
    let companion: RamCompanion?
    let slotIndex: Int
    let openSlotNames: [Int: String]
    let namedOpenSlots: Set<Int>
    let onOpenSlotNameTapped: (Int) -> Void
    let onNameTapped: (Ram) -> Void
    let onCompanionNameTapped: () -> Void
    let onRentTapped: () -> Void

    private enum Content {
        case ram(Ram)
        case companion(RamCompanion)
        /// A slot within `unlockedSlots` that doesn't have a journey yet:
        /// a ram of its own is waiting there, under a suggested name the
        /// person can replace once.
        case openRam(slot: Int)
        case locked
    }

    /// How far the card travels off either edge — well past its own
    /// (clipped) bounds, so it genuinely reads as having left rather than
    /// stopping at the edge.
    private static let travelDistance: CGFloat = 260

    /// One stepped frame every 70ms — a deliberate frame-by-frame walk
    /// for a real ram/companion, and (same sprite, for now) a locked slot
    /// too. Only a genuinely empty slot has no sprite to step through, so
    /// it just rides the same timed offset without swapping images.
    private static let frameDuration: Duration = .milliseconds(70)
    private static let stepCount = max(RamSpriteFrameSets.walkCycle.count, 1)

    @State private var displayed: Content = .locked
    @State private var displayedKey = ""
    @State private var hasAppeared = false
    @State private var walkTask: Task<Void, Never>?

    @State private var offsetX: CGFloat = 0
    @State private var frameImageName: String?
    @State private var isRearingUp = false
    @State private var rearFrame = 0
    @State private var bleatTrigger = 0

    private func resolveContent(at index: Int) -> (content: Content, key: String) {
        guard index < unlockedSlots else {
            return (.locked, "locked-\(index)")
        }
        if index < rams.count {
            let ram = rams[index]
            return (.ram(ram), "ram-\(ram.id)")
        }
        if index == 0, rams.isEmpty, let companion {
            return (.companion(companion), "companion")
        }
        return (.openRam(slot: index), "open-\(index)")
    }

    private var targetKey: String { resolveContent(at: slotIndex).key }
    private var targetContent: Content { resolveContent(at: slotIndex).content }

    private var currentHasLetter: Bool {
        if case .ram(let ram) = displayed { return ram.letter != nil }
        return false
    }

    var body: some View {
        content
            .offset(x: offsetX)
            .onAppear {
                #if DEBUG
                if CommandLine.arguments.contains("-demoMode") {
                    hasAppeared = true
                    settleImmediately()
                    return
                }
                #endif
                if !hasAppeared {
                    hasAppeared = true
                    displayed = targetContent
                    displayedKey = targetKey
                    walkTask = Task { await playWalkIn() }
                } else if walkTask == nil {
                    // Reappearing (scrolled back into view after Pasture's
                    // List recycled this row, most commonly) with no task
                    // running at all means the last one was cancelled by
                    // `onDisappear` mid-stride — the walk-in/walk-out was
                    // interrupted partway and, before this, nothing ever
                    // resumed or finished it: `hasAppeared` was already
                    // `true` so the `if !hasAppeared` branch above never
                    // ran again, and the sprite was left stuck at
                    // whatever offset/frame it happened to be on. Snapping
                    // straight to the settled pose for whatever's
                    // actually selected now clears that stuck frame
                    // instead of leaving the ram frozen mid-walk forever.
                    settleImmediately()
                }
            }
            .onChange(of: targetKey) { _, newKey in
                guard hasAppeared, newKey != displayedKey else { return }
                walkTask?.cancel()
                walkTask = Task {
                    await playSwap(to: newKey)
                    walkTask = nil
                }
            }
            // The identity on screen hasn't changed, but something about
            // it has (a status update, a new passenger letter) — refresh
            // in place, no walk replayed.
            .onChange(of: rams) { _, _ in
                guard hasAppeared, targetKey == displayedKey else { return }
                displayed = targetContent
            }
            .onChange(of: openSlotNames) { _, _ in
                guard hasAppeared, targetKey == displayedKey else { return }
                displayed = targetContent
            }
            .onChange(of: companion?.name) { _, _ in
                guard hasAppeared, targetKey == displayedKey else { return }
                displayed = targetContent
            }
            .onDisappear {
                walkTask?.cancel()
                walkTask = nil
            }
    }

    /// Jumps straight to the settled, facing-camera pose for whatever's
    /// currently selected — no walk replayed. Used only to recover from
    /// an animation that got cancelled mid-flight (see `onAppear` above);
    /// replaying the full walk every time this row scrolls in and out
    /// would look far worse than just snapping to rest.
    @MainActor
    private func settleImmediately() {
        isRearingUp = false
        offsetX = 0
        displayed = targetContent
        displayedKey = targetKey
        switch displayed {
        case .ram, .companion, .openRam, .locked:
            frameImageName = RamSpriteFrameSets.faceCameraFrame
            walkTask = Task {
                await idleLoop()
                walkTask = nil
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch displayed {
        case .ram(let ram):
            bigCard(
                name: ram.name,
                subtitle: ram.status.displayName,
                statusSymbolName: ram.status.symbolName,
                onNameTapped: { onNameTapped(ram) }
            )
        case .companion(let companion):
            bigCard(
                name: companion.name,
                subtitle: String(localized: "Resting in the pasture — \(companion.ageDescription)", bundle: .appLanguage, locale: .appLanguage),
                statusSymbolName: nil,
                onNameTapped: onCompanionNameTapped
            )
        case .openRam(let slot):
            let isNamed = namedOpenSlots.contains(slot)
            bigCard(
                name: openSlotNames[slot] ?? String(localized: "New ram", bundle: .appLanguage, locale: .appLanguage),
                subtitle: isNamed
                    ? String(localized: "Waiting in the pasture", bundle: .appLanguage, locale: .appLanguage)
                    : String(localized: "Waiting in the pasture — name it once", bundle: .appLanguage, locale: .appLanguage),
                statusSymbolName: nil,
                showsRenameHint: !isNamed,
                onNameTapped: { if !isNamed { onOpenSlotNameTapped(slot) } }
            )
        case .locked:
            LockedBigSlotCard(frameImageName: frameImageName, onRentTapped: onRentTapped)
        }
    }

    private func bigCard(
        name: String,
        subtitle: String,
        statusSymbolName: String?,
        showsRenameHint: Bool = true,
        onNameTapped: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            portraitImage(name: name)
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 112 * 0.22, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if let statusSymbolName {
                        Image(systemName: statusSymbolName)
                            .font(.caption)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.primary)
                            .padding(6)
                            .background(.regularMaterial, in: Circle())
                            .offset(x: 4, y: 4)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    bleatTrigger += 1
                    RamBleatPlayer.shared.play()
                }
                .sensoryFeedback(.impact(weight: .light), trigger: bleatTrigger)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Pet \(name)")

            VStack(spacing: 2) {
                Button(action: onNameTapped) {
                    HStack(spacing: 4) {
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if showsRenameHint {
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Resolves in four steps, same precedence `RamPortraitView` uses
    /// elsewhere: bespoke "Ram-<name>" art always wins (shown static);
    /// otherwise whichever frame the walk/turn/rear-up choreography below
    /// currently wants; then the shared placeholder; then an SF Symbol.
    @ViewBuilder
    private func portraitImage(name: String) -> some View {
        if UIImage(named: "Ram-\(name)") != nil {
            Image("Ram-\(name)")
                .resizable()
                .scaledToFill()
        } else if isRearingUp, RamSpriteFrameSets.assetExists(RamSpriteFrameSets.rearUpWithEnvelope.first ?? "") {
            Image(RamSpriteFrameSets.rearUpWithEnvelope[safeIndex: rearFrame])
                .resizable()
                .scaledToFit()
        } else if let frameImageName, RamSpriteFrameSets.assetExists(frameImageName) {
            Image(frameImageName)
                .resizable()
                .scaledToFit()
        } else if UIImage(named: "RamPortraitPlaceholder") != nil {
            Image("RamPortraitPlaceholder")
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "pawprint.circle.fill")
                .resizable()
                .scaledToFit()
                .padding(112 * 0.18)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
        }
    }

    /// Walks whichever slot is currently on screen off to the right (frame
    /// by frame, for a real ram/companion — otherwise just the timed
    /// slide), then swaps to whatever `newKey` now points at and walks
    /// that one in from the left the same way `playWalkIn` does on first
    /// appearance.
    @MainActor
    private func playSwap(to newKey: String) async {
        isRearingUp = false
        let frames = RamSpriteFrameSets.walkCycle
        for step in 0..<Self.stepCount {
            guard !Task.isCancelled else { return }
            if !frames.isEmpty { frameImageName = frames[step % frames.count] }
            offsetX = Self.travelDistance * CGFloat(step + 1) / CGFloat(Self.stepCount)
            try? await Task.sleep(for: Self.frameDuration)
        }
        guard !Task.isCancelled else { return }

        displayed = targetContent
        displayedKey = newKey
        await playWalkIn()
    }

    /// Starts off-canvas to the left and walks in to the middle (frame by
    /// frame for a real ram/companion), then — for a real ram/companion
    /// only — turns to face the person (`faceCameraFrame`) and holds
    /// there, the resting pose every ram settles into once it's the one
    /// on screen.
    @MainActor
    private func playWalkIn() async {
        let frames = RamSpriteFrameSets.walkCycle
        offsetX = -Self.travelDistance
        frameImageName = frames.first
        for step in 0..<Self.stepCount {
            guard !Task.isCancelled else { return }
            if !frames.isEmpty { frameImageName = frames[step % frames.count] }
            offsetX = -Self.travelDistance + Self.travelDistance * CGFloat(step + 1) / CGFloat(Self.stepCount)
            try? await Task.sleep(for: Self.frameDuration)
        }
        guard !Task.isCancelled else { return }
        offsetX = 0

        switch displayed {
        case .ram, .companion, .openRam, .locked:
            frameImageName = RamSpriteFrameSets.faceCameraFrame
            await idleLoop()
        }
    }

    /// Once settled facing the person, an occasional rear-up-on-two-hooves
    /// flourish — only for a ram actually carrying a letter, since every
    /// frame in `rearUpWithEnvelope` shows the envelope still gripped in
    /// its mouth.
    @MainActor
    private func idleLoop() async {
        guard currentHasLetter, RamSpriteFrameSets.assetExists(RamSpriteFrameSets.rearUpWithEnvelope.first ?? "") else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 4...7)))
            guard !Task.isCancelled else { return }
            isRearingUp = true
            let frames = Array(RamSpriteFrameSets.rearUpWithEnvelope.indices)
            // Rise slowly, hold at the top, then lower back down in
            // reverse — a deliberate rear rather than a flicker.
            for frame in frames {
                guard !Task.isCancelled else { return }
                rearFrame = frame
                try? await Task.sleep(for: .milliseconds(260))
            }
            try? await Task.sleep(for: .milliseconds(800))
            for frame in frames.dropLast().reversed() {
                guard !Task.isCancelled else { return }
                rearFrame = frame
                try? await Task.sleep(for: .milliseconds(240))
            }
            guard !Task.isCancelled else { return }
            isRearingUp = false
        }
    }
}

/// A locked pasture slot — past `unlockedSlots`, waiting to be rented
/// through RevenueCat. Walks in the same as a real ram (same sprite, for
/// now) rather than sitting there as a bare padlock, so a locked pasture
/// still reads as alive; the corner badge is what actually marks it
/// locked. The button is the one interactive element on the card, so it's
/// bigger than usual and two lines, styled as real *transparent* Liquid
/// Glass (`.glass` on iOS 26+, a thinMaterial capsule before that — never
/// a solid filled button).
private struct LockedBigSlotCard: View {
    /// The same walk-cycle/face-camera frame `RamSelectorStage` is
    /// currently driving for whatever's on screen — a locked slot walks in
    /// with the identical sprite a real ram uses (nothing bespoke to a
    /// locked ram exists yet), only the padlock badge in the corner and
    /// the missing name/rename affordance say it isn't one you actually
    /// have.
    let frameImageName: String?
    let onRentTapped: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            portraitImage
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 112 * 0.22, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                        .padding(6)
                        .background(.regularMaterial, in: Circle())
                        .offset(x: 4, y: 4)
                }

            VStack(spacing: 8) {
                Text("Locked")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                rentButton
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Same four-step fallback chain `RamSelectorStage.portraitImage(name:)`
    /// uses for a real ram, minus the bespoke "Ram-<name>" art lookup — a
    /// locked slot has no name to look one up by.
    @ViewBuilder
    private var portraitImage: some View {
        if let frameImageName, RamSpriteFrameSets.assetExists(frameImageName) {
            Image(frameImageName)
                .resizable()
                .scaledToFit()
        } else if UIImage(named: "RamPortraitPlaceholder") != nil {
            Image("RamPortraitPlaceholder")
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "pawprint.circle.fill")
                .resizable()
                .scaledToFit()
                .padding(112 * 0.18)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
        }
    }

    /// Bigger than a typical inline action button, and two lines — this is
    /// the one interactive thing on an otherwise-inert card, so it should
    /// read as a real destination, not a footnote.
    @ViewBuilder
    private var rentButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: onRentTapped) {
                rentButtonLabel
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
        } else {
            Button(action: onRentTapped) {
                rentButtonLabel
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .background(.thinMaterial, in: Capsule())
        }
    }

    private var rentButtonLabel: some View {
        VStack(spacing: 2) {
            Label("Let Them Graze", systemImage: "pawprint.fill")
                .font(.subheadline.weight(.semibold))
            Text("Unlock another pasture slot")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("One ram") {
    @Previewable @State var selectedRamId: UUID? = FlockViewModel.preview.activeRams.first?.id
    RamSelectorSlider(
        rams: FlockViewModel.preview.activeRams,
        capacity: FlockViewModel.pastureCapacity,
        unlockedSlots: 1,
        selectedRamId: $selectedRamId,
        onRentTapped: {},
        onNameTapped: { _ in },
        companion: RamCompanionStore.preview.companion,
        onCompanionNameTapped: {}
    )
    .padding(.vertical)
}

#Preview("Resting companion, no rams yet") {
    @Previewable @State var selectedRamId: UUID?
    RamSelectorSlider(
        rams: [],
        capacity: FlockViewModel.pastureCapacity,
        unlockedSlots: 1,
        selectedRamId: $selectedRamId,
        onRentTapped: {},
        onNameTapped: { _ in },
        companion: RamCompanionStore.preview.companion,
        onCompanionNameTapped: {}
    )
    .padding(.vertical)
}
