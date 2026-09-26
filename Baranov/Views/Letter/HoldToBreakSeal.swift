//
//  HoldToBreakSeal.swift
//  Baranov
//
//  The one control on the letter screen that matters: a wax seal you press
//  and hold. Cracks spread across it while the finger stays down, the
//  phone answers with a run of taps that starts crisp (`.rigid`) and ends
//  heavy (`.heavy`), and at `holdDuration` the seal gives way — one heavy
//  hit and the system success haptic — and `onBroken` fires.
//
//  Three interaction modes so the caller never has to swap views:
//  `.hold` is live, `.locked` looks dimmed and explains itself on tap
//  (wrong recipient, code not entered yet), `.display` is a plain intact
//  seal for a letter that is still on the road.
//
//  The seal art itself is `WaxSealBreakView` from the design system, so
//  it cracks and shatters exactly like every other seal in the app.
//

import SwiftUI
import UIKit

// MARK: - Haptics

/// Progressive haptics for the hold. Generators are created once and
/// re-prepared after every hit so the Taptic Engine never spins down
/// mid-gesture.
@MainActor
private final class SealHaptics {
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    func prepare() {
        rigid.prepare()
        heavy.prepare()
        notification.prepare()
    }

    /// `progress` is 0…1 through the hold: the first half taps `.rigid`,
    /// the second half `.heavy`, and both grow in intensity.
    func tick(progress: Double) {
        let clamped = min(max(progress, 0), 1)
        let intensity = CGFloat(0.35 + 0.65 * clamped)
        if clamped < 0.5 {
            rigid.impactOccurred(intensity: intensity)
            rigid.prepare()
        } else {
            heavy.impactOccurred(intensity: intensity)
            heavy.prepare()
        }
    }

    func completed() {
        heavy.impactOccurred(intensity: 1)
        notification.notificationOccurred(.success)
    }
}

// MARK: - View

struct HoldToBreakSeal: View {
    enum Kind {
        /// Wax pressed with the sender's monogram.
        case wax(SealColor, monogram: String)
        /// An open postcard: nothing to break, just something to lift out.
        case postcard
    }

    enum Interaction {
        /// Live: press and hold to break.
        case hold
        /// Dimmed; a tap calls `onLockedTap` so the caller can say why.
        case locked
        /// Intact, inert, full strength — the letter is still travelling.
        case display
    }

    let kind: Kind
    var interaction: Interaction = .hold
    var diameter: CGFloat = 68
    /// Flips to `true` once the letter has been opened; the wax shatters.
    var isBroken = false
    /// Bump to put the seal back after a failed attempt (wrong code).
    var resetToken = 0
    /// Colour of the progress ring; should read on the paper behind it.
    var ringColor: Color = .primary
    var holdDuration: Double = 1.5
    var lockedHint: LocalizedStringKey = "Not ready to open yet"
    var onLockedTap: () -> Void = {}
    let onBroken: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var progress = 0.0
    @State private var hasFinished = false
    @State private var holdTask: Task<Void, Never>?
    @State private var haptics = SealHaptics()

    private var ringDiameter: CGFloat { diameter + 14 }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor.opacity(0.7), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: ringDiameter, height: ringDiameter)
                .opacity(isBroken ? 0 : 1)

            sealBody
        }
        .frame(width: ringDiameter, height: ringDiameter)
        .scaleEffect(reduceMotion ? 1 : 1 - 0.06 * progress)
        .opacity(interaction == .locked && !isBroken ? 0.6 : 1)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 40) {
            finish()
        } onPressingChanged: { pressing in
            pressingChanged(pressing)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                if interaction == .locked, !isBroken { onLockedTap() }
            }
        )
        .onChange(of: resetToken) {
            holdTask?.cancel()
            hasFinished = false
            withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
        }
        .onDisappear { holdTask?.cancel() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sealLabel)
        .accessibilityHint(interaction == .hold ? Text("Touch and hold to open the letter") : Text(lockedHint))
        .accessibilityAddTraits(interaction == .display ? [] : .isButton)
        .accessibilityAction(named: Text("Break Seal")) {
            if interaction == .hold { finish() }
        }
    }

    // MARK: Seal art

    @ViewBuilder
    private var sealBody: some View {
        switch kind {
        case .wax(let wax, let monogram):
            WaxSealBreakView(
                wax: wax,
                monogram: monogram,
                diameter: diameter,
                crackProgress: progress,
                isShattering: isBroken
            )
        case .postcard:
            Circle()
                .fill(.regularMaterial)
                .frame(width: diameter, height: diameter)
                .overlay(Circle().strokeBorder(.secondary.opacity(0.3), lineWidth: 1))
                .overlay {
                    Image(systemName: "envelope.open.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .opacity(isBroken ? 0 : 1)
                .animation(.easeOut(duration: 0.2), value: isBroken)
        }
    }

    private var sealLabel: Text {
        switch kind {
        case .wax: Text("Wax seal")
        case .postcard: Text("Postcard")
        }
    }

    // MARK: Gesture

    private func pressingChanged(_ pressing: Bool) {
        guard interaction == .hold, !hasFinished, !isBroken else { return }
        if pressing { begin() } else { cancel() }
    }

    private func begin() {
        haptics.prepare()
        withAnimation(.linear(duration: holdDuration)) { progress = 1 }

        holdTask?.cancel()
        let interval = 0.12
        let steps = Int(holdDuration / interval)
        holdTask = Task { @MainActor in
            for step in 1..<max(steps, 2) {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                let fraction = Double(step) * interval / holdDuration
                haptics.tick(progress: fraction)
                if step.isMultiple(of: 2) {
                    SoundEffectPlayer.shared.play(.waxCrack, volume: 0.3)
                }
            }
        }
    }

    private func cancel() {
        holdTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
    }

    private func finish() {
        guard interaction == .hold, !hasFinished else { return }
        hasFinished = true
        holdTask?.cancel()
        withAnimation(.easeOut(duration: 0.1)) { progress = 1 }
        haptics.completed()
        onBroken()
    }
}

#Preview("Hold to break") {
    HoldToBreakSeal(kind: .wax(.crimson, monogram: "A")) {}
        .padding(40)
        .background(.regularMaterial)
}
