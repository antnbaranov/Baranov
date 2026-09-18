//
//  TransitProgressStrip.swift
//  Baranov
//
//  What the "Slide to Dispatch" control morphs into once the ram is out:
//  the same capsule footprint, now a live schematic of the leg — origin
//  waypoint on the left, destination on the right, the ram's marker
//  sliding along the line between them in proportion to the meters
//  actually walked, and the three place names (origin, halfway,
//  destination) from `RouteWaypointService` underneath. The halfway
//  label is dropped rather than repeated when the leg never leaves one
//  city (see that service for the rule).
//
//  Nothing here is interactive — recalling a ram is its own deliberate
//  slide, kept separate so a drag intended for the sheet can't withdraw
//  a letter. Materials and semantic colors only: `.regularMaterial`
//  track, `.tint` progress, `.primary`/`.secondary`/`.tertiary` text.
//

import SwiftUI

struct TransitProgressStrip: View {
    /// 0…1 along the current leg.
    let progress: Double
    let originLabel: String
    let midpointLabel: String?
    let destinationLabel: String
    /// Whether the shepherd is moving right now — drives the marker's
    /// pulse so a stationary ram reads as standing, not stalled.
    var isMoving: Bool = false
    /// The road's bearing under the ram, so the marker's chevron faces
    /// the way the ram does on the map.
    var bearingDegrees: Double? = nil
    /// Whether the leg ends at a handoff (plane) or the final gate (flag).
    var endsAtHandoff: Bool = false

    private let trackHeight: CGFloat = 56
    private let markerDiameter: CGFloat = 32
    private let endpointDiameter: CGFloat = 10

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let inset = (trackHeight - markerDiameter) / 2 + markerDiameter / 2
                let travel = max(0, proxy.size.width - inset * 2)
                let x = inset + travel * CGFloat(min(max(progress, 0), 1))

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.regularMaterial)

                    // The road: a hairline between the two waypoints,
                    // with the walked portion drawn in the tint.
                    Capsule()
                        .fill(.tertiary)
                        .frame(width: travel, height: 3)
                        .offset(x: inset)

                    Capsule()
                        .fill(.tint)
                        .frame(width: max(0, x - inset), height: 3)
                        .offset(x: inset)

                    waypointDot(systemImage: "house.fill")
                        .position(x: inset, y: trackHeight / 2)

                    waypointDot(systemImage: endsAtHandoff ? "airplane.departure" : "flag.checkered")
                        .position(x: inset + travel, y: trackHeight / 2)

                    ramMarker
                        .position(x: x, y: trackHeight / 2)
                        .animation(.smooth(duration: 0.6), value: progress)
                }
                .frame(height: trackHeight)
            }
            .frame(height: trackHeight)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(originLabel)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if let midpointLabel, !midpointLabel.isEmpty {
                    Text(midpointLabel)
                        .lineLimit(1)
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                    Spacer(minLength: 0)
                }

                Text(destinationLabel)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .font(.caption2.weight(.medium))
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 6)
            .animation(.easeInOut(duration: 0.2), value: midpointLabel)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((progress * 100).rounded())) percent of the way from \(originLabel) to \(destinationLabel)")
    }

    private func waypointDot(systemImage: String) -> some View {
        ZStack {
            Circle()
                .fill(.thinMaterial)
                .frame(width: 22, height: 22)
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var ramMarker: some View {
        ZStack {
            Circle()
                .fill(.tint)
                .frame(width: markerDiameter, height: markerDiameter)

            Image(systemName: "pawprint.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.pulse, options: .repeating, isActive: isMoving)

            if let bearingDegrees {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(bearingDegrees))
                    .offset(y: -markerDiameter / 2 - 3)
                    .animation(.smooth(duration: 0.4), value: bearingDegrees)
            }
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        TransitProgressStrip(
            progress: 0.0,
            originLabel: "Burnaby",
            midpointLabel: "Metrotown",
            destinationLabel: "Vancouver",
            bearingDegrees: 270
        )
        TransitProgressStrip(
            progress: 0.62,
            originLabel: "Calgary",
            midpointLabel: "Thunder Bay",
            destinationLabel: "Gander",
            isMoving: true,
            bearingDegrees: 80,
            endsAtHandoff: true
        )
    }
    .padding()
}
