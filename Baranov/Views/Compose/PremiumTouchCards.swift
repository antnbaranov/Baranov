//
//  PremiumTouchCards.swift
//  Baranov
//
//  The compose screen's three paid touches — scratch-off secret, geo-lock
//  and time capsule — shown as live cards instead of a collapsed row.
//  Each card carries a small preview that is already moving before the
//  sender pays: foil being scratched clear, a radius pulsing on a map, a
//  capsule counting down. Tapping a card opens the paywall while locked,
//  or switches the touch on and reveals its settings inline.
//
//  Native materials, semantic styles, continuous corners and the system
//  font only. Every animation stops under Reduce Motion.
//

import MapKit
import SwiftUI

// MARK: - Card

struct PremiumTouchCard<Preview: View, Editor: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let isUnlocked: Bool
    let isOn: Bool
    let onTap: () -> Void
    @ViewBuilder var preview: Preview
    @ViewBuilder var editor: Editor

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 14) {
                    preview
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    trailingMark
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn && isUnlocked ? .isSelected : [])
            .accessibilityHint(isUnlocked ? "" : "Included with Expand the Pasture")

            if isUnlocked, isOn {
                editor
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .sensoryFeedback(.selection, trigger: isOn)
    }

    @ViewBuilder private var trailingMark: some View {
        if isUnlocked {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .symbolRenderingMode(.hierarchical)
        } else {
            Image(systemName: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(8)
                .background(.regularMaterial, in: Circle())
        }
    }
}

// MARK: - Scratch-off preview

/// Foil that scratches itself clear and re-covers, on a loop.
struct ScratchTeaserView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let progress = reduceMotion ? 0.55 : Self.progress(at: context.date)
            ZStack {
                VStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                    Text("Psst…")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Canvas { canvas, size in
                    canvas.fill(Path(CGRect(origin: .zero, size: size)), with: .style(Color(uiColor: .systemGray3)))
                    canvas.blendMode = .destinationOut
                    var path = Path()
                    let rows = 4
                    for row in 0..<rows {
                        let y = size.height * (CGFloat(row) + 0.5) / CGFloat(rows)
                        let leftToRight = row % 2 == 0
                        let startX = leftToRight ? -6 : size.width + 6
                        let endX = leftToRight ? size.width + 6 : -6
                        if row == 0 { path.move(to: CGPoint(x: startX, y: y)) } else { path.addLine(to: CGPoint(x: startX, y: y)) }
                        path.addLine(to: CGPoint(x: endX, y: y))
                    }
                    canvas.stroke(
                        path.trimmedPath(from: 0, to: progress),
                        with: .style(.white),
                        style: StrokeStyle(lineWidth: 24, lineCap: .round, lineJoin: .round)
                    )
                }
                .compositingGroup()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
        }
    }

    /// 0 → 1 while scratching, holds, then covers again.
    private static func progress(at date: Date) -> CGFloat {
        let period = 5.0
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        let value: Double
        switch t {
        case ..<0.45: value = t / 0.45
        case ..<0.75: value = 1
        default: value = 1 - (t - 0.75) / 0.25
        }
        return CGFloat(value * value * (3 - 2 * value))
    }
}

// MARK: - Geo-lock preview

/// A map with the lock radius pulsing over the sender's spot. Falls back
/// to plain pulsing rings until a location is known.
struct GeoLockTeaserView: View {
    var coordinate: CLLocationCoordinate2D?
    var radiusMeters: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let coordinate {
                Map(
                    position: .constant(.region(MKCoordinateRegion(
                        center: coordinate,
                        latitudinalMeters: max(radiusMeters * 5, 300),
                        longitudinalMeters: max(radiusMeters * 5, 300)
                    ))),
                    interactionModes: []
                ) {
                    MapCircle(center: coordinate, radius: radiusMeters)
                        .foregroundStyle(Color.accentColor.opacity(0.22))
                        .stroke(Color.accentColor, lineWidth: 2)
                }
                .allowsHitTesting(false)
            } else {
                Rectangle().fill(Color(uiColor: .secondarySystemBackground))
            }

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
                let phase = reduceMotion ? 0.5 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                Circle()
                    .strokeBorder(Color.accentColor.opacity(1 - phase), lineWidth: 2)
                    .scaleEffect(0.25 + phase * 0.75)
                    .padding(6)
            }

            Image(systemName: "location.fill")
                .font(.callout)
                .foregroundStyle(Color.accentColor)
                .padding(6)
                .background(.regularMaterial, in: Circle())
        }
    }
}

// MARK: - Time-capsule preview

/// A capsule counting down to a sample moment, second by second.
struct CapsuleTeaserView: View {
    var target: Date?
    @State private var sample = Date().addingTimeInterval(3 * 86_400 + 4 * 3_600 + 12 * 60)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int((target ?? sample).timeIntervalSince(context.date)))
            let days = remaining / 86_400
            let hours = (remaining % 86_400) / 3_600
            let minutes = (remaining % 3_600) / 60
            let seconds = remaining % 60
            VStack(spacing: 5) {
                Image(systemName: "lock.clock.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                Text(String(format: "%dd %02d:%02d:%02d", days, hours, minutes, seconds))
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: seconds)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
        }
    }
}
