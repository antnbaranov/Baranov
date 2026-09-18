//
//  LookAroundHeadingCone.swift
//  Baranov
//
//  The radar-style field-of-view cone drawn under the ram marker while
//  Look Around is open in split screen — the same affordance Apple Maps
//  draws under its Look Around pin so you can tell which way the imagery
//  is facing on the map below it.
//
//  Drawn with its apex at the center of its own square frame, so placing
//  it in a `ZStack` behind the marker inside an `Annotation` (which is
//  centered on the coordinate) automatically puts the apex on the exact
//  coordinate. The rotation is about that same center. Heading is passed
//  in *unnormalized* (see `LookAroundSession.headingDegrees`), which is
//  what lets the rotation animate the short way across 0°/360°.
//

import SwiftUI

struct LookAroundHeadingCone: View {
    /// Estimated Look Around camera heading, 0 = north, clockwise.
    var headingDegrees: Double
    /// Angular width of the cone.
    var fieldOfViewDegrees: Double
    /// The map camera's own heading, so the cone stays true-north correct
    /// when the person has rotated the map.
    var mapHeadingDegrees: Double = 0
    var radius: CGFloat = 84

    var body: some View {
        ConeWedge(spanDegrees: fieldOfViewDegrees)
            .fill(
                RadialGradient(
                    colors: [Color.accentColor.opacity(0.42), Color.accentColor.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
            .frame(width: radius * 2, height: radius * 2)
            .rotationEffect(.degrees(headingDegrees - mapHeadingDegrees))
            // Interactive springs so the cone tracks the finger inside the
            // imagery without lagging, but still settles softly.
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.86), value: headingDegrees)
            .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.86), value: fieldOfViewDegrees)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A wedge pointing straight up (north) from the frame's center, spanning
/// `spanDegrees`. Animatable so pinch-driven FOV changes ease.
struct ConeWedge: Shape {
    var spanDegrees: Double

    var animatableData: Double {
        get { spanDegrees }
        set { spanDegrees = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let halfSpan = max(1, spanDegrees) / 2

        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90 - halfSpan),
            endAngle: .degrees(-90 + halfSpan),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        LookAroundHeadingCone(headingDegrees: 40, fieldOfViewDegrees: 80)
        Circle().fill(.primary).frame(width: 12, height: 12)
    }
    .padding()
}
