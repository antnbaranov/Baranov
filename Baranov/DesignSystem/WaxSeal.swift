//
//  WaxSeal.swift
//  Baranov
//
//  The wax seal, as a thing you *do* rather than a checkbox you tick.
//
//  Three pieces share one visual language so the seal the sender presses
//  in Compose is recognisably the same seal the recipient breaks at the
//  gate:
//
//  - `WaxSealView` — a disc of wax with a slightly uneven edge, a raised
//    rim, and the sender's monogram pressed into it. Static; used
//    wherever a sealed letter is shown.
//  - `WaxSealPressView` — the sealing ritual. Hold: molten wax pools and
//    spreads under the thumb with soft haptic ticks. At the end of the
//    hold a signet stamp drops, hits with a heavy impact, the wax
//    squashes and settles, a ripple runs out, and the monogram is left
//    behind. Built on `keyframeAnimator`, so it's one declarative
//    timeline.
//  - `WaxSealBreakView` — the arrival ritual's payoff. Cracks spread
//    across the wax as the recipient holds; on success the seal
//    shatters into shards that fly outward and fade.
//  - `SealedEnvelopeView` — the closed envelope the seal sits on, with a
//    flap that swings open.
//
//  Materials and colours are all system: `Color.gradient` for the wax
//  body, `.primary`/`.secondary` for everything else. No coloured
//  shadows, no glow — the depth comes from two offset monogram layers
//  (an emboss), the way real wax reads.
//

import SwiftUI
import UIKit

// MARK: - Shapes

/// A disc whose edge wobbles a little — wax never sets perfectly round.
/// Deterministic, so the same seal looks the same every frame.
struct WaxBlobShape: Shape, InsettableShape {
    /// 0 = a perfect circle, 1 = a very uneven puddle.
    var unevenness: CGFloat = 0.06
    var inset: CGFloat = 0

    var animatableData: CGFloat {
        get { unevenness }
        set { unevenness = newValue }
    }

    func inset(by amount: CGFloat) -> WaxBlobShape {
        var copy = self
        copy.inset += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let base = min(rect.width, rect.height) / 2
        let points = 72
        var path = Path()
        for i in 0...points {
            let t = CGFloat(i) / CGFloat(points) * .pi * 2
            // Three low-frequency lobes plus one faster wobble.
            let wobble = sin(t * 3 + 0.4) * 0.55 + sin(t * 5 + 1.9) * 0.3 + sin(t * 8 + 0.7) * 0.15
            let r = base * (1 + unevenness * wobble)
            let p = CGPoint(x: center.x + cos(t) * r, y: center.y + sin(t) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

/// One pie-slice of a wax disc, used for the shatter.
private struct WaxShardShape: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - The seal itself

/// A set wax seal with a monogram pressed into it.
struct WaxSealView: View {
    var wax: SealColor
    var monogram: String
    var diameter: CGFloat = 64

    var body: some View {
        ZStack {
            WaxBlobShape()
                .fill(wax.color.gradient)

            // Raised rim: a soft dark ring just inside the edge.
            WaxBlobShape(unevenness: 0.05)
                .strokeBorder(.black.opacity(0.14), lineWidth: diameter * 0.055)
                .padding(diameter * 0.07)

            SealMonogram(monogram: monogram, diameter: diameter)
        }
        .frame(width: diameter, height: diameter)
        // Shimmer first, clip second: the highlight must be cut to the wax's
        // own silhouette, or its band sweeps across the letter behind it.
        .metallicShimmer(isActive: wax.hasShimmer)
        .clipShape(WaxBlobShape())
        .accessibilityLabel("\(wax.displayName) wax seal, monogram \(monogram)")
    }
}

/// The impression: a darker layer a hair below, a lighter one on top —
/// an emboss without a single drop shadow.
private struct SealMonogram: View {
    let monogram: String
    let diameter: CGFloat

    var body: some View {
        ZStack {
            Text(monogram)
                .font(.system(size: diameter * 0.42, weight: .bold, design: .serif))
                .foregroundStyle(.black.opacity(0.28))
                .offset(y: diameter * 0.02)
            Text(monogram)
                .font(.system(size: diameter * 0.42, weight: .bold, design: .serif))
                .foregroundStyle(.white.opacity(0.92))
                .offset(y: -diameter * 0.01)
        }
    }
}

// MARK: - Pressing the seal (Compose)

/// The values the sealing timeline drives. Starts with the stamp raised
/// out of view and the wax unmarked.
private struct StampMotion {
    var stampOffset: CGFloat = -110
    var stampOpacity: Double = 0
    var stampScale: CGFloat = 1.15
    var waxScaleX: CGFloat = 1
    var waxScaleY: CGFloat = 1
    var rippleScale: CGFloat = 0.9
    var rippleOpacity: Double = 0
    var monogramOpacity: Double = 0
    var monogramScale: CGFloat = 1.6
}

/// Hold to pool the wax, then the signet drops and stamps it.
///
/// Drives itself: the parent only supplies the wax, the monogram and
/// what to do once the seal has set. `onSealed` fires after the stamp
/// animation has fully settled, so the parent can swap to a "sealed"
/// presentation without cutting the motion short.
struct WaxSealPressView: View {
    var wax: SealColor
    var monogram: String
    var diameter: CGFloat = 84
    var holdDuration: Double = 1.5
    /// True while a hold is in progress (and through the stamp), false on release.
    var onHoldChange: ((Bool) -> Void)? = nil
    var onSealed: () -> Void

    @State private var holdProgress: Double = 0
    @State private var isStamping = false
    @State private var holdTick = 0
    @State private var stampTrigger = 0
    @State private var impactTrigger = 0
    @State private var settledTrigger = 0
    @State private var holdTask: Task<Void, Never>?
    @State private var holdTimerTask: Task<Void, Never>?
    @State private var isHolding = false

    private var poolScale: CGFloat {
        isStamping ? 1 : 0.3 + 0.7 * CGFloat(holdProgress)
    }

    var body: some View {
        ZStack {
            // Where the wax will land: a faint dashed ring until it does.
            Circle()
                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                .opacity(isStamping ? 0 : 1 - holdProgress * 0.8)

            // Hold-progress ring.
            Circle()
                .trim(from: 0, to: holdProgress)
                .stroke(wax.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(isStamping ? 0 : 1)

            waxAndStamp
                .scaleEffect(poolScale * (1 + 0.06 * CGFloat(holdProgress)))
                .opacity(isStamping ? 1 : min(1, holdProgress * 3))

            if !isStamping, holdProgress == 0 {
                Image(systemName: "seal")
                    .font(.system(size: diameter * 0.32, weight: .light))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        // A real, continuous touch-and-hold rather than
        // `onLongPressGesture` — that modifier's own `perform` closure
        // could fire the full completion animation off a brief tap (a
        // quick down-up sometimes still reads as "long press succeeded"
        // once combined with `onPressingChanged`). A plain `DragGesture`
        // with zero minimum distance gives full control instead: press
        // starts a timer by hand, and only reaching `holdDuration` while
        // still pressed calls `stamp()`. Releasing early — at any point,
        // for any reason — cancels the timer and eases the pool back to
        // idle; there is no path from "tap" to "sealed."
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    guard !isStamping else { return }
                    // A press that has wandered too far off the seal
                    // reads as a drag/scroll, not a hold — cancel rather
                    // than let it keep counting down under the finger.
                    guard hypot(value.translation.width, value.translation.height) <= 40 else {
                        cancelHold()
                        return
                    }
                    guard !isHolding else { return }
                    isHolding = true
                    withAnimation(.linear(duration: holdDuration)) { holdProgress = 1 }
                    startHoldTicks()
                    armHoldTimer()
                }
                .onEnded { _ in
                    cancelHold()
                }
        )
        .onChange(of: isHolding) { _, holding in onHoldChange?(holding || isStamping) }
        .accessibilityLabel("Wax seal")
        .accessibilityHint("Touch and hold to seal the letter")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Seal Letter") {
            stamp()
        }
        .onDisappear {
            holdTask?.cancel()
            holdTimerTask?.cancel()
        }
    }

    /// Releasing before the hold has actually completed: stop the
    /// countdown and, unless the stamp has already begun, snap the pool
    /// back to unset rather than leaving it half-formed.
    private func cancelHold() {
        guard isHolding else { return }
        isHolding = false
        holdTimerTask?.cancel()
        holdTask?.cancel()
        guard !isStamping else { return }
        // `holdProgress` is already 1 (the linear fill is only an
        // animation towards it), so it must be pulled back explicitly —
        // otherwise letting go left the ring finishing on its own.
        withAnimation(.easeOut(duration: 0.25)) { holdProgress = 0 }
    }

    /// The actual "did they really hold it long enough" check — a `Task`
    /// timed to `holdDuration` that only calls `stamp()` if the press is
    /// still down (`isHolding`) when it fires. This, not the gesture's
    /// own callbacks, is what a brief tap can no longer short-circuit.
    private func armHoldTimer() {
        holdTimerTask?.cancel()
        holdTimerTask = Task {
            try? await Task.sleep(for: .seconds(holdDuration))
            guard !Task.isCancelled, isHolding, !isStamping else { return }
            isHolding = false
            stamp()
        }
    }

    /// The molten pool, and — once `stampTrigger` fires — the signet
    /// dropping onto it. One keyframe timeline for every layer.
    private var waxAndStamp: some View {
        WaxBlobShape(unevenness: isStamping ? 0.06 : 0.11)
            .fill(wax.color.gradient)
            .keyframeAnimator(initialValue: StampMotion(), trigger: stampTrigger) { pool, motion in
                ZStack {
                    // Ripple in the wax from the impact.
                    Circle()
                        .strokeBorder(wax.color.opacity(0.7), lineWidth: 2)
                        .scaleEffect(motion.rippleScale)
                        .opacity(motion.rippleOpacity)

                    pool
                        .scaleEffect(x: motion.waxScaleX, y: motion.waxScaleY)

                    // Rim + monogram, left behind by the stamp.
                    WaxBlobShape(unevenness: 0.05)
                        .strokeBorder(.black.opacity(0.14), lineWidth: diameter * 0.055)
                        .padding(diameter * 0.07)
                        .opacity(motion.monogramOpacity)
                    SealMonogram(monogram: monogram, diameter: diameter)
                        .scaleEffect(motion.monogramScale)
                        .opacity(motion.monogramOpacity)

                    // The signet.
                    signet
                        .scaleEffect(motion.stampScale)
                        .offset(y: motion.stampOffset)
                        .opacity(motion.stampOpacity)
                }
            } keyframes: { _ in
                KeyframeTrack(\.stampOpacity) {
                    LinearKeyframe(1, duration: 0.06)
                    LinearKeyframe(1, duration: 0.40)
                    LinearKeyframe(0, duration: 0.22)
                }
                KeyframeTrack(\.stampOffset) {
                    CubicKeyframe(0, duration: 0.22)
                    LinearKeyframe(0, duration: 0.16)
                    CubicKeyframe(-120, duration: 0.30)
                }
                KeyframeTrack(\.stampScale) {
                    CubicKeyframe(1.0, duration: 0.22)
                    LinearKeyframe(1.0, duration: 0.16)
                    CubicKeyframe(1.12, duration: 0.30)
                }
                KeyframeTrack(\.waxScaleX) {
                    LinearKeyframe(1, duration: 0.22)
                    SpringKeyframe(1.16, duration: 0.10, spring: .snappy)
                    SpringKeyframe(1, duration: 0.55, spring: .bouncy)
                }
                KeyframeTrack(\.waxScaleY) {
                    LinearKeyframe(1, duration: 0.22)
                    SpringKeyframe(0.84, duration: 0.10, spring: .snappy)
                    SpringKeyframe(1, duration: 0.55, spring: .bouncy)
                }
                KeyframeTrack(\.rippleScale) {
                    LinearKeyframe(0.9, duration: 0.22)
                    CubicKeyframe(2.0, duration: 0.62)
                }
                KeyframeTrack(\.rippleOpacity) {
                    LinearKeyframe(0, duration: 0.22)
                    LinearKeyframe(0.8, duration: 0.03)
                    LinearKeyframe(0, duration: 0.59)
                }
                KeyframeTrack(\.monogramOpacity) {
                    LinearKeyframe(0, duration: 0.25)
                    LinearKeyframe(1, duration: 0.14)
                }
                KeyframeTrack(\.monogramScale) {
                    LinearKeyframe(1.6, duration: 0.25)
                    SpringKeyframe(1, duration: 0.50, spring: .bouncy)
                }
            }
    }

    /// A signet stamp seen from above: the handle, and the die with the
    /// monogram in reverse relief.
    private var signet: some View {
        VStack(spacing: -diameter * 0.06) {
            Capsule()
                .fill(.regularMaterial)
                .frame(width: diameter * 0.22, height: diameter * 0.46)
                .overlay(Capsule().strokeBorder(.secondary.opacity(0.35), lineWidth: 1))
            Circle()
                .fill(.thickMaterial)
                .frame(width: diameter * 0.78, height: diameter * 0.78)
                .overlay(Circle().strokeBorder(.secondary.opacity(0.35), lineWidth: 1))
                .overlay {
                    Text(monogram)
                        .font(.system(size: diameter * 0.36, weight: .bold, design: .serif))
                        .foregroundStyle(.secondary)
                        .scaleEffect(x: -1)
                }
        }
    }

    private func startHoldTicks() {
        holdTask?.cancel()
        // Progressive haptics: rigid taps that grow stronger, then heavy
        // ones as the wax is about to set.
        let steps = 6
        let interval = Int(holdDuration * 1000) / (steps + 1)
        let rigid = UIImpactFeedbackGenerator(style: .rigid)
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        rigid.prepare()
        heavy.prepare()
        holdTask = Task {
            for step in 1...steps {
                try? await Task.sleep(for: .milliseconds(interval))
                guard !Task.isCancelled else { return }
                let strength = 0.3 + 0.7 * Double(step) / Double(steps)
                if step <= 4 {
                    rigid.impactOccurred(intensity: strength)
                } else {
                    heavy.impactOccurred(intensity: strength)
                }
                holdTick += 1
                if step % 2 == 0 { SoundEffectPlayer.shared.play(.waxCrack, volume: 0.25) }
            }
        }
    }

    private func stamp() {
        holdTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) {
            holdProgress = 1
            isStamping = true
        }
        stampTrigger += 1
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            impactTrigger += 1
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            SoundEffectPlayer.shared.play(.waxStamp)
            try? await Task.sleep(for: .milliseconds(620))
            settledTrigger += 1
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onSealed()
        }
    }
}

// MARK: - Breaking the seal (Arrival)

/// A set seal that cracks as `crackProgress` rises, then shatters when
/// `isShattering` flips. The arrival ritual drives `crackProgress` from
/// its long-press and sets `isShattering` once the code has opened the
/// letter.
struct WaxSealBreakView: View {
    var wax: SealColor
    var monogram: String
    var diameter: CGFloat = 72
    /// 0…1 while the recipient holds; the cracks lengthen with it.
    var crackProgress: Double
    var isShattering: Bool

    private let shardCount = 8
    private let crackAngles: [Double] = [11, 79, 163, 231, 292]

    var body: some View {
        ZStack {
            if isShattering {
                shards
            } else {
                WaxSealView(wax: wax, monogram: monogram, diameter: diameter)
                cracks
            }
        }
        .frame(width: diameter, height: diameter)
    }

    /// Hairline fractures that grow from the centre outward as the seal
    /// is held. Drawn with `trim`, so they lengthen rather than fade in.
    private var cracks: some View {
        ForEach(0..<5, id: \.self) { i in
            let appearsAt = Double(i) / 5 * 0.7
            let local = max(0, min(1, (crackProgress - appearsAt) / 0.3))
            CrackShape(seed: i)
                .trim(from: 0, to: local)
                .stroke(.black.opacity(0.45), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(crackAngles[i]))
        }
    }

    private var shards: some View {
        ForEach(0..<shardCount, id: \.self) { i in
            let start = Angle.degrees(Double(i) / Double(shardCount) * 360)
            let end = Angle.degrees(Double(i + 1) / Double(shardCount) * 360)
            let mid = (start.radians + end.radians) / 2
            let distance = diameter * (0.9 + Double(i % 3) * 0.25)
            ShardView(
                wax: wax,
                start: start,
                end: end,
                diameter: diameter,
                flight: CGSize(width: cos(mid) * distance, height: sin(mid) * distance + diameter * 0.35),
                spin: Double(i % 2 == 0 ? 1 : -1) * (40 + Double(i) * 17)
            )
        }
    }
}

private struct CrackShape: Shape {
    let seed: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)
        // A jagged line from the centre to the rim with two kinks.
        let k1 = CGPoint(x: center.x + r * 0.35, y: center.y + r * (seed % 2 == 0 ? 0.08 : -0.1))
        let k2 = CGPoint(x: center.x + r * 0.68, y: center.y + r * (seed % 3 == 0 ? -0.09 : 0.12))
        let tip = CGPoint(x: center.x + r * 0.98, y: center.y + r * (seed % 2 == 0 ? 0.03 : -0.04))
        path.addLine(to: k1)
        path.addLine(to: k2)
        path.addLine(to: tip)
        return path
    }
}

/// One shard: sits in place, then flies out, spins, drops and fades.
private struct ShardView: View {
    let wax: SealColor
    let start: Angle
    let end: Angle
    let diameter: CGFloat
    let flight: CGSize
    let spin: Double

    @State private var flown = false

    var body: some View {
        WaxShardShape(startAngle: start, endAngle: end)
            .fill(wax.color.gradient)
            .overlay(WaxShardShape(startAngle: start, endAngle: end).stroke(.black.opacity(0.18), lineWidth: 0.8))
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(flown ? spin : 0))
            .offset(flown ? flight : .zero)
            .scaleEffect(flown ? 0.55 : 1)
            .opacity(flown ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.65)) { flown = true }
            }
    }
}

// MARK: - Envelope

/// A closed (or opening) envelope with the seal on its flap. `isOpen`
/// swings the flap up on the top edge; the seal goes with it.
struct SealedEnvelopeView: View {
    var wax: SealColor
    var monogram: String
    var addressee: String
    var isOpen: Bool = false
    var width: CGFloat = 260
    /// `false` lets a caller draw its own seal (one that cracks and
    /// shatters, say) at `sealCenterY(width:)` instead.
    var showsSeal: Bool = true
    /// The paper the envelope is made of; `nil` keeps the system-material look.
    var paper: EnvelopePaper?
    /// A colour the writer picked; overrides the preset paper.
    var customPaperHex: String? = nil

    private var style: PaperStyle? { paper.map { PaperStyle(paper: $0, customHex: customPaperHex) } }

    private var height: CGFloat { width * 0.62 }

    /// Where the seal's centre sits, measured from the envelope's top
    /// edge, for a caller overlaying its own seal on a closed envelope.
    static func sealCenterY(width: CGFloat) -> CGFloat {
        width * 0.62 * 0.55 - width * 0.02
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Pocket.
            Group {
                if let style {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(style.color)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.thickMaterial)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.secondary.opacity(0.25), lineWidth: 1))
            .frame(width: width, height: height)

            // Address line.
            VStack(spacing: 2) {
                Text("To")
                    .font(.caption2)
                    .foregroundStyle(style.map { $0.ink.opacity(0.6) } ?? Color(uiColor: .tertiaryLabel))
                Text(addressee)
                    .font(.system(.body, design: .serif, weight: .semibold))
                    .foregroundStyle(style?.ink ?? Color.primary)
                    .lineLimit(1)
            }
            .frame(width: width * 0.8)
            .offset(y: height * 0.6)

            // Flap, hinged on the top edge, with the seal riding on it.
            ZStack(alignment: .bottom) {
                Group {
                    if let style {
                        FlapShape().fill(style.color)
                            .overlay(FlapShape().fill(.black.opacity(0.07)))
                    } else {
                        FlapShape().fill(.regularMaterial)
                    }
                }
                .overlay(FlapShape().stroke(.secondary.opacity(0.3), lineWidth: 1))
                if showsSeal {
                    WaxSealView(wax: wax, monogram: monogram, diameter: width * 0.2)
                        .offset(y: width * 0.08)
                }
            }
            .frame(width: width, height: height * 0.55)
            .rotation3DEffect(.degrees(isOpen ? -168 : 0), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.35)
        }
        .frame(width: width, height: height)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isOpen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOpen ? "Open envelope addressed to \(addressee)" : "Sealed envelope addressed to \(addressee)")
    }
}

private struct FlapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Monogram helper

extension String {
    /// The letter pressed into a seal for this name — its first
    /// character, uppercased; "B" (for Baranov) when there's nothing to
    /// go on.
    var sealMonogram: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first.isLetter else { return "B" }
        return String(first).uppercased()
    }
}

#Preview("Seal") {
    VStack(spacing: 32) {
        WaxSealPressView(wax: .crimson, monogram: "A") {}
        WaxSealView(wax: .gold, monogram: "M")
        SealedEnvelopeView(wax: .navy, monogram: "A", addressee: "Marta")
        WaxSealBreakView(wax: .plum, monogram: "K", crackProgress: 0.7, isShattering: false)
    }
    .padding()
    .background(.regularMaterial)
}
