//
//  InkStampView.swift
//  Baranov
//
//  A passport stamp as a rubber stamp presses it: a double border, the
//  place in capitals, a date line, and a little ink that never lands
//  evenly — a soft bleed under the crisp mark and a few worn specks where
//  the rubber missed. Departure, arrival, towns, water and hand-overs each
//  get their own frame. Everything is drawn with `Path` and SF Symbols.
//
//  Tilt and wear are derived from the stamp's id (`StableSeed`), so a page
//  looks hand-stamped but never reshuffles between redraws.
//

import SwiftUI

// MARK: - Frames

private struct TicketShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 6)
        let bite: CGFloat = 8
        for corner in [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
        ] {
            path = path.subtracting(Path(ellipseIn: CGRect(x: corner.x - bite, y: corner.y - bite, width: bite * 2, height: bite * 2)))
        }
        return path
    }
}

/// A small pine, for the Pacific Northwest.
struct PineSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        let tiers: [(top: CGFloat, bottom: CGFloat, halfWidth: CGFloat)] = [
            (0.00, 0.40, 0.26), (0.24, 0.66, 0.36), (0.48, 0.90, 0.48),
        ]
        for tier in tiers {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY + h * tier.top))
            path.addLine(to: CGPoint(x: rect.midX + w * tier.halfWidth, y: rect.minY + h * tier.bottom))
            path.addLine(to: CGPoint(x: rect.midX - w * tier.halfWidth, y: rect.minY + h * tier.bottom))
            path.closeSubpath()
        }
        path.addRect(CGRect(x: rect.midX - w * 0.06, y: rect.minY + h * 0.88, width: w * 0.12, height: h * 0.12))
        return path
    }
}

private enum StampFrame {
    case circle, rounded, ticket, oval

    var shape: AnyShape {
        switch self {
        case .circle: AnyShape(Circle())
        case .rounded: AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .ticket: AnyShape(TicketShape())
        case .oval: AnyShape(Capsule())
        }
    }
}

// MARK: - Per-kind styling

extension JourneyStampKind {
    fileprivate var frame: StampFrame {
        switch self {
        case .setOut: .rounded
        case .arrival: .ticket
        case .town, .landmark: .circle
        case .water, .handoff: .oval
        }
    }

    fileprivate var ink: Color {
        switch self {
        case .setOut, .water: PassportInk.blue
        case .arrival, .handoff: PassportInk.red
        case .town, .landmark: PassportInk.green
        }
    }

    fileprivate var stampWord: LocalizedStringKey {
        switch self {
        case .setOut: "DEPARTED"
        case .arrival: "ARRIVED"
        case .town: "PASSED"
        case .landmark: "LANDMARK"
        case .water: "CROSSED"
        case .handoff: "HANDED OVER"
        }
    }

    /// The word used in the tap-to-inspect slip.
    var journalVerb: LocalizedStringKey {
        switch self {
        case .setOut: "Departed"
        case .arrival: "Arrived"
        case .town: "Passed through"
        case .landmark: "Passed"
        case .water: "Crossed"
        case .handoff: "Handed over at"
        }
    }
}

private func isPacificNorthwest(_ place: String) -> Bool {
    let name = place.lowercased()
    return ["burnaby", "vancouver", "british columbia", "bcit", "surrey", "richmond", "victoria", "seattle", "whistler"]
        .contains { name.contains($0) }
        || name.hasSuffix(" bc") || name.contains(", bc")
}

// MARK: - Stamp

struct InkStampView: View {
    let stamp: JourneyStamp
    var isSelected: Bool = false

    private var seed: UInt64 { StableSeed.value(for: stamp.id) }

    /// -3° … +4°, stable for a given stamp.
    private var tilt: Double { -3 + Double(seed % 71) / 10 }

    private var ink: Color { stamp.kind.ink }

    var body: some View {
        let frame = stamp.kind.frame
        ZStack {
            mark(frame: frame).blur(radius: 0.9).opacity(0.45)
            mark(frame: frame)
        }
        .compositingGroup()
        .mask(WornMask(seed: seed))
        .frame(width: 104, height: stamp.kind.frame == .oval ? 84 : 104)
        .rotationEffect(.degrees(tilt))
        .scaleEffect(isSelected ? 1.07 : 1)
        .animation(.spring(duration: 0.35, bounce: 0.45), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(stamp.displayPlaceName), \(stamp.timestamp.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: .appLanguage)))"))
        .accessibilityHint("Shows the stamp's details")
    }

    private func mark(frame: StampFrame) -> some View {
        ZStack {
            frame.shape.stroke(ink, lineWidth: 2.4)
            frame.shape.stroke(ink, lineWidth: 0.9).padding(6)

            VStack(spacing: 2) {
                glyph
                    .frame(height: 22)
                Text(stamp.kind.stampWord)
                    .font(.system(size: 8, weight: .heavy, design: .serif))
                    .tracking(1.2)
                Text(stamp.shortPlaceName.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .serif))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                Text(stamp.timestamp.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits).locale(.appLanguage)).uppercased())
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var glyph: some View {
        if stamp.kind == .town || stamp.kind == .landmark, isPacificNorthwest(stamp.placeName) {
            PineSilhouette()
                .fill(ink)
                .frame(width: 20, height: 22)
        } else {
            Image(systemName: stamp.kind.symbolName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(ink)
        }
    }
}

/// Opaque everywhere except a scatter of tiny holes: the rubber's worn
/// spots, where no ink lands.
private struct WornMask: View {
    let seed: UInt64

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            context.blendMode = .destinationOut
            var generator = SeededGenerator(seed: seed)
            for _ in 0..<26 {
                let x = CGFloat.random(in: 0..<size.width, using: &generator)
                let y = CGFloat.random(in: 0..<size.height, using: &generator)
                let r = CGFloat.random(in: 0.5...1.6, using: &generator)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(.black))
            }
        }
    }
}
