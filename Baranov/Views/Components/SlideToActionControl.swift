//
//  SlideToActionControl.swift
//  Baranov
//
//  A "slide to …" confirmation control in the idiom of iOS's own slide-
//  to-power-off: a capsule track with a draggable knob that has to be
//  carried the full way across before the action fires. Used for the two
//  moments in this app that should never happen from a stray tap on a
//  bottom sheet being dragged between detents — sending a letter out
//  (`.dispatch`), and pulling a ram that is already out walking back off
//  the road (`.recall`).
//
//  Everything here is system material and semantic color: a
//  `.regularMaterial` track, a `.tint` (or `.red`, for the destructive
//  recall) knob, no shadows or gradients. The haptic on completion is a
//  medium impact via `sensoryFeedback` — SwiftUI's native equivalent of
//  `UIImpactFeedbackGenerator(style: .medium).impactOccurred()`.
//
//  The knob springs back on release unless the drag reached the end; on
//  completion it holds at the far end for as long as `isBusy` is true (a
//  route being resolved, a location fix awaited) and then returns, so a
//  completion the parent couldn't act on (a missing field, the paywall)
//  leaves the control ready for another try rather than stuck.
//
//  VoiceOver users get a plain button: the whole drag is represented as
//  a single `Button` with the same title, so the gesture is never a
//  barrier to the action.
//

import SwiftUI

struct SlideToActionControl: View {
    enum Role {
        /// Sending a letter out: tinted knob, `paperplane.fill`.
        case dispatch
        /// Withdrawing a ram mid-journey: red knob, `arrow.uturn.backward`.
        case recall

        fileprivate var knobColor: Color {
            switch self {
            case .dispatch: return .accentColor
            case .recall: return .red
            }
        }

        fileprivate var defaultSymbol: String {
            switch self {
            case .dispatch: return "paperplane.fill"
            case .recall: return "arrow.uturn.backward"
            }
        }
    }

    let title: String
    var role: Role = .dispatch
    var systemImage: String? = nil
    /// While true, the knob stays parked at the end and a spinner replaces
    /// its symbol; `busyTitle` replaces the track's label.
    var isBusy: Bool = false
    var busyTitle: String? = nil
    /// The control still slides and still calls `onComplete` when this is
    /// false — the parent decides what "not ready" means (this app
    /// explains what's missing rather than greying out). It only dims.
    var isReady: Bool = true
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var isHeldAtEnd = false
    @State private var completionTick = 0
    @State private var thresholdTick = 0
    @State private var hasPassedThreshold = false
    @State private var returnTask: Task<Void, Never>?

    private let trackHeight: CGFloat = 56
    private let knobInset: CGFloat = 4
    private var knobDiameter: CGFloat { trackHeight - knobInset * 2 }

    /// How far across the knob has to be carried for the action to fire.
    private let completionFraction: CGFloat = 0.88

    var body: some View {
        GeometryReader { proxy in
            let travel = max(0, proxy.size.width - knobDiameter - knobInset * 2)
            let offset = isHeldAtEnd ? travel : min(max(0, dragOffset), travel)
            let fraction = travel > 0 ? offset / travel : 0

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.regularMaterial)

                // The label fades as the knob covers it, so it never
                // reads through the knob mid-drag.
                Text(isBusy ? (busyTitle ?? title) : title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, knobDiameter * 0.6)
                    .opacity(isBusy ? 1 : Double(1 - fraction * 1.6).clamped(to: 0...1))
                    .animation(.easeOut(duration: 0.1), value: fraction)

                knob(travel: travel, offset: offset)
            }
            .frame(height: trackHeight)
            .contentShape(Capsule(style: .continuous))
            .gesture(dragGesture(travel: travel))
        }
        .frame(height: trackHeight)
        .opacity(isReady || isBusy ? 1 : 0.65)
        .animation(.easeInOut(duration: 0.15), value: isReady)
        .sensoryFeedback(.impact(weight: .medium), trigger: completionTick)
        .sensoryFeedback(.selection, trigger: thresholdTick)
        .onChange(of: isBusy) { _, busy in
            // The parent finished whatever the slide started; if this
            // control is still on screen, the action didn't consume it —
            // bring the knob home for another go.
            if !busy { scheduleReturn(after: .milliseconds(150)) }
        }
        .accessibilityRepresentation {
            Button(title, action: onComplete)
                .disabled(isBusy)
        }
    }

    private func knob(travel: CGFloat, offset: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(role.knobColor)

            if isBusy {
                ProgressView()
                    .tint(.white)
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage ?? role.defaultSymbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: completionTick)
            }
        }
        .frame(width: knobDiameter, height: knobDiameter)
        .padding(knobInset)
        .offset(x: offset)
        .animation(knobAnimation, value: offset)
    }

    /// The knob tracks the finger 1:1 while dragging (no animation) and
    /// springs home or to the end on release.
    private var knobAnimation: Animation? {
        if isDragging { return nil }
        return reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.35)
    }

    private func dragGesture(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                guard !isBusy, !isHeldAtEnd else { return }
                returnTask?.cancel()
                isDragging = true
                dragOffset = value.translation.width

                let passed = dragOffset >= travel * completionFraction
                if passed != hasPassedThreshold {
                    hasPassedThreshold = passed
                    if passed { thresholdTick += 1 }
                }
            }
            .onEnded { value in
                guard !isBusy, !isHeldAtEnd else { return }
                isDragging = false
                hasPassedThreshold = false

                if value.translation.width >= travel * completionFraction {
                    isHeldAtEnd = true
                    dragOffset = travel
                    completionTick += 1
                    onComplete()
                    // If the parent never goes busy (synchronous action,
                    // or one it declined), come home on our own.
                    scheduleReturn(after: .milliseconds(600))
                } else {
                    dragOffset = 0
                }
            }
    }

    private func scheduleReturn(after delay: Duration) {
        returnTask?.cancel()
        returnTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, !isBusy else { return }
            isHeldAtEnd = false
            dragOffset = 0
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview("Dispatch") {
    VStack(spacing: 24) {
        SlideToActionControl(title: "Slide to Dispatch") {}
        SlideToActionControl(title: "Slide to Dispatch", isBusy: true, busyTitle: "Finding a Route…") {}
        SlideToActionControl(title: "Slide to Recall", role: .recall) {}
    }
    .padding()
}
