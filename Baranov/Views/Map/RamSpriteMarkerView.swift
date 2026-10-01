//
//  RamSpriteMarkerView.swift
//  Baranov
//
//  A drop-in visual upgrade for the map's ram marker: same interface as
//  `RamMarkerView` (bearingDegrees/motionState/markerSize), but drawing
//  the "Object-N" sprite sequence — a ram galloping with the envelope
//  gripped in its mouth, dust kicked up behind, finishing in a leap —
//  instead of the vector skeletal rig.
//
//  Animation is driven by an explicit three-state machine (`Phase`) kept
//  in `@State`, not directly by the `motionState` the parent passes in:
//
//  - `motionState` can be re-sent many times a second with the same
//    category but a different `moving(speed:)` payload (every pedometer
//    or GPS tick). Only a *category* change should restart a frame
//    sequence; a speed change must never reset the stride mid-cycle.
//  - `.arrived` plays its leap once and then holds — the machine needs
//    to know it's already finished so a re-render doesn't replay it.
//  - The loop view is keyed by `.id(phase)`, which guarantees SwiftUI
//    tears down the old frame task and starts the new sequence the
//    instant the phase flips, rather than relying on `switch` branches
//    inside the map annotation getting fresh identity (which is what
//    left the marker looping Object-11/12 while walking).
//
//  A heading indicator (`location.north.fill`, rotated to the bearing)
//  sits outside the horizontal mirror so it always points the true way;
//  the sprite itself only ever flips left/right, never rotates, since a
//  ram drawn at 37° would look like it's falling over.
//
//  Falls back to `RamMarkerView` itself, completely unchanged, whenever
//  the sprite art isn't present in Assets.xcassets.
//

import SwiftUI

struct RamSpriteMarkerView: View {
    var bearingDegrees: Double
    var motionState: RamMotionState
    var markerSize: CGFloat = 44
    /// Wool color of the ram this marker stands for.
    var color: RamColor = .white
    /// Show the small compass chevron that carries the exact bearing.
    var showsHeadingIndicator: Bool = true

    /// The sprite machine's own state — see the header doc for why this
    /// is separate from `motionState`.
    enum Phase: Hashable {
        case idle
        case running
        case arriving
        /// The leap has played through; hold the final frame.
        case arrivedHold
    }

    @State private var phase: Phase = .idle

    private var hasSpriteArt: Bool {
        guard let first = RamSpriteFrameSets.gallopWithEnvelope.first else { return false }
        return RamSpriteFrameSets.assetExists(first)
    }

    var body: some View {
        Group {
            if hasSpriteArt {
                spriteRig
            } else {
                RamMarkerView(bearingDegrees: bearingDegrees, motionState: motionState, markerSize: markerSize)
            }
        }
        .onAppear {
            phase = Self.initialPhase(for: motionState)
        }
        .onChange(of: motionState.category) { _, newCategory in
            transition(to: newCategory)
        }
    }

    // MARK: - State machine

    private static func initialPhase(for state: RamMotionState) -> Phase {
        switch state.category {
        case .idle: .idle
        case .moving: .running
        case .arrived: .arriving
        }
    }

    /// The only place `phase` changes in response to the parent. Speed
    /// changes never reach here (they don't change the category), so a
    /// ram already running keeps its stride.
    private func transition(to category: RamMotionState.Category) {
        let next: Phase
        switch category {
        case .idle:
            next = .idle
        case .moving:
            next = .running
        case .arrived:
            // Don't replay the leap if it has already finished.
            next = phase == .arrivedHold ? .arrivedHold : .arriving
        }
        guard next != phase else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            phase = next
        }
    }

    // MARK: - Drawing

    private var spriteRig: some View {
        frameContent
            .frame(width: markerSize, height: markerSize)
            .modifier(SpriteDirectionalLock(bearingDegrees: bearingDegrees))
            .overlay(alignment: .topTrailing) {
                if showsHeadingIndicator {
                    headingChevron
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var frameContent: some View {
        switch phase {
        case .idle:
            // Standing still reads as a slow, settled sway between two held
            // frames (Object-11/12) rather than a mid-stride pose — a long
            // frame duration so it doesn't flicker.
            RamSpriteLoopView(frameNames: RamSpriteFrameSets.idleFrames(for: color), frameDuration: .milliseconds(450))
                .id(Phase.idle)
        case .running:
            // Object-2…Object-8, looped. Playback rate follows the
            // normalized speed so a stroll and a jog read differently.
            // `RamSpriteLoopView` reads its duration once when its task
            // starts, so the speed is quantized into three tiers and the
            // loop is keyed on the tier: a per-tick speed wobble never
            // restarts the stride, a real change of pace re-times it.
            RamSpriteLoopView(frameNames: RamSpriteFrameSets.runningFrames(for: color), frameDuration: runningFrameDuration)
                .id("running-\(runningSpeedTier)-\(color.rawValue)")
        case .arriving:
            RamSpriteLoopView(
                frameNames: RamSpriteFrameSets.leapFrames(for: color),
                frameDuration: .milliseconds(70),
                loops: false,
                onFinishedOnce: { phase = .arrivedHold }
            )
            .id(Phase.arriving)
        case .arrivedHold:
            if let last = RamSpriteFrameSets.leapFrames(for: color).last {
                Image(last)
                    .resizable()
                    .scaledToFit()
            }
        }
    }

    /// 0 = stroll, 1 = walk, 2 = jog — from the normalized `moving` speed.
    private var runningSpeedTier: Int {
        guard case .moving(let speed) = motionState else { return 1 }
        if speed < 0.4 { return 0 }
        if speed < 0.75 { return 1 }
        return 2
    }

    /// ~100 ms/frame for a stroll, ~75 ms walking, ~55 ms jogging.
    private var runningFrameDuration: Duration {
        switch runningSpeedTier {
        case 0: .milliseconds(100)
        case 1: .milliseconds(75)
        default: .milliseconds(55)
        }
    }

    /// Exact-bearing wayfinding accessory, matching the vector rig's own.
    /// Rendered above the directional mirror so it never appears flipped.
    private var headingChevron: some View {
        Image(systemName: "location.north.fill")
            .font(.system(size: markerSize * 0.26, weight: .semibold))
            .foregroundStyle(.tint)
            .rotationEffect(.degrees(bearingDegrees))
            .animation(.easeInOut(duration: 0.25), value: bearingDegrees)
            .offset(x: markerSize * 0.12, y: -markerSize * 0.12)
            .accessibilityHidden(true)
    }

    private var accessibilityDescription: String {
        let compass = [String(localized: "north", bundle: .appLanguage, locale: .appLanguage), String(localized: "northeast", bundle: .appLanguage, locale: .appLanguage), String(localized: "east", bundle: .appLanguage, locale: .appLanguage), String(localized: "southeast", bundle: .appLanguage, locale: .appLanguage), String(localized: "south", bundle: .appLanguage, locale: .appLanguage), String(localized: "southwest", bundle: .appLanguage, locale: .appLanguage), String(localized: "west", bundle: .appLanguage, locale: .appLanguage), String(localized: "northwest", bundle: .appLanguage, locale: .appLanguage)]
        let safeBearing = bearingDegrees.isFinite ? bearingDegrees : 0
        let normalized = (safeBearing.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let direction = compass[Int(normalized / 45 + 0.5) % 8]
        switch phase {
        case .idle:
            return String(localized: "Ram resting, facing \(direction)", bundle: .appLanguage, locale: .appLanguage)
        case .running:
            return String(localized: "Ram traveling \(direction)", bundle: .appLanguage, locale: .appLanguage)
        case .arriving, .arrivedHold:
            return String(localized: "Ram arrived, rearing up", bundle: .appLanguage, locale: .appLanguage)
        }
    }
}

/// Mirrors the sprite horizontally when the bearing points generally
/// "left" on screen — the same convention `RamMarkerView`'s own
/// `DirectionalLock` uses, assuming the source art faces right. Only ever
/// flips horizontally, never vertically, so the sprite never renders
/// upside down.
private struct SpriteDirectionalLock: ViewModifier {
    let bearingDegrees: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: facingLeft ? -1 : 1, y: 1)
            .animation(.easeInOut(duration: 0.2), value: facingLeft)
    }

    private var facingLeft: Bool {
        var normalized = bearingDegrees.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        return normalized > 180 && normalized < 360
    }
}

#Preview("Ram sprite marker states") {
    struct PreviewHarness: View {
        @State private var state: RamMotionState = .moving(speed: 0.7)
        @State private var bearing: Double = 40

        var body: some View {
            VStack(spacing: 24) {
                RamSpriteMarkerView(bearingDegrees: bearing, motionState: state, markerSize: 96)
                    .border(.secondary.opacity(0.2))

                Picker("State", selection: $state) {
                    Text("Idle").tag(RamMotionState.idle)
                    Text("Moving").tag(RamMotionState.moving(speed: 0.7))
                    Text("Arrived").tag(RamMotionState.arrived)
                }
                .pickerStyle(.segmented)

                Slider(value: $bearing, in: 0...360) {
                    Text("Bearing")
                }
                Text("Bearing: \(Int(bearing))°")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    return PreviewHarness()
}
