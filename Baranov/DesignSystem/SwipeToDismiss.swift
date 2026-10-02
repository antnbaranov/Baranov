//
//  SwipeToDismiss.swift
//  Baranov
//
//  Every floating message that sits over the map — a courier suggestion, a
//  handover request, the "You are here" pill, the "Meeting …" HUD — can be
//  flicked away the way iOS banners and notifications can: sideways, or up
//  for the ones that hang from the top. The card follows the finger, fades
//  a little, and either flies off (past the threshold) or springs back.
//
//  The gesture is simultaneous, so buttons inside the card keep working,
//  and VoiceOver gets a "Dismiss" action instead of a swipe.
//

import SwiftUI

private struct SwipeToDismissModifier: ViewModifier {
    let isEnabled: Bool
    let onDismiss: () -> Void

    @State private var offset: CGSize = .zero

    private static let horizontalThreshold: CGFloat = 90
    private static let upwardThreshold: CGFloat = 50

    private var fade: Double {
        let travelled = max(abs(offset.width), -offset.height)
        return 1 - min(Double(travelled) / 400, 0.6)
    }

    func body(content: Content) -> some View {
        content
            .offset(offset)
            .opacity(fade)
            .simultaneousGesture(drag, including: isEnabled ? .all : .subviews)
            .accessibilityActions {
                if isEnabled {
                    Button("Dismiss", action: onDismiss)
                }
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                let width = value.translation.width
                let height = value.translation.height
                if abs(width) > abs(height) {
                    offset = CGSize(width: width, height: 0)
                } else if height < 0 {
                    offset = CGSize(width: 0, height: height)
                }
            }
            .onEnded { value in
                let width = value.translation.width + (value.predictedEndTranslation.width - value.translation.width) * 0.3
                let height = value.translation.height

                if abs(width) > Self.horizontalThreshold, abs(value.translation.width) > abs(height) {
                    fling(to: CGSize(width: width > 0 ? 600 : -600, height: 0))
                } else if -height > Self.upwardThreshold, abs(height) > abs(value.translation.width) {
                    fling(to: CGSize(width: 0, height: -300))
                } else {
                    withAnimation(.snappy) { offset = .zero }
                }
            }
    }

    private func fling(to target: CGSize) {
        withAnimation(.snappy(duration: 0.25)) {
            offset = target
        } completion: {
            onDismiss()
            // A view that stays on screen (it only fades out) must come back in place next time.
            withTransaction(Transaction(animation: nil)) { offset = .zero }
        }
    }
}

extension View {
    /// Lets the person flick this message away; `onDismiss` runs once it has left the screen.
    func swipeToDismiss(isEnabled: Bool = true, onDismiss: @escaping () -> Void) -> some View {
        modifier(SwipeToDismissModifier(isEnabled: isEnabled, onDismiss: onDismiss))
    }
}
