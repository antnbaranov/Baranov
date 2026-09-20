//
//  LetterStationery.swift
//  Baranov
//
//  The letter as an object: an envelope lying on a linen tabletop, the
//  recipient and sender written on it in serif type, a perforated stamp
//  and an ink postmark (date and distance walked) in the top-right
//  corner, and the wax seal on the flap.
//
//  Paper, stamp and ink are physical materials, so — like `EnvelopePaper`
//  — they are fixed colours rather than semantic ones; the only things
//  that adapt to Light/Dark are the paper the sender chose (cream follows
//  the appearance), the tabletop and the sheet inside. Shadows are plain
//  black, soft and low: the envelope rests on the table, nothing glows.
//

import SwiftUI

// MARK: - Tabletop

/// A quiet linen weave behind the letter: two hairline grids at
/// different pitches, drawn once, so the envelope reads as sitting on a
/// surface instead of floating on a flat grey.
struct LinenSurface: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)

            Canvas { context, size in
                var fine = Path()
                var x: CGFloat = 0
                while x < size.width {
                    fine.move(to: CGPoint(x: x, y: 0))
                    fine.addLine(to: CGPoint(x: x, y: size.height))
                    x += 3
                }
                var y: CGFloat = 0
                while y < size.height {
                    fine.move(to: CGPoint(x: 0, y: y))
                    fine.addLine(to: CGPoint(x: size.width, y: y))
                    y += 3
                }
                context.stroke(fine, with: .color(.primary.opacity(0.03)), lineWidth: 0.5)

                var coarse = Path()
                x = 1.5
                while x < size.width {
                    coarse.move(to: CGPoint(x: x, y: 0))
                    coarse.addLine(to: CGPoint(x: x, y: size.height))
                    x += 9
                }
                context.stroke(coarse, with: .color(.primary.opacity(0.02)), lineWidth: 1)
            }
            .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Stamp

/// Stamp outline with a row of semicircular bites along every edge.
/// Meant for `.mask` with an even-odd fill: the bites are where a circle
/// overlaps the rectangle, so they cut out instead of adding.
private struct StampPerforation: Shape {
    var pitch: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let radius = pitch * 0.32

        func bite(at center: CGPoint) {
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2))
        }

        let columns = max(2, Int((rect.width / pitch).rounded()))
        for i in 0...columns {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(columns)
            bite(at: CGPoint(x: x, y: rect.minY))
            bite(at: CGPoint(x: x, y: rect.maxY))
        }
        let rows = max(2, Int((rect.height / pitch).rounded()))
        for i in 1..<rows {
            let y = rect.minY + rect.height * CGFloat(i) / CGFloat(rows)
            bite(at: CGPoint(x: rect.minX, y: y))
            bite(at: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

/// A small vintage postage stamp: cream margin, a single flat field of
/// deep green, the app's paw and two lines of engraving.
struct PostalStampView: View {
    private static let margin = Color(.sRGB, red: 0.98, green: 0.95, blue: 0.88)
    private static let field = Color(.sRGB, red: 0.16, green: 0.36, blue: 0.34)

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack {
                Rectangle().fill(Self.margin)
                Rectangle().fill(Self.field).padding(w * 0.1)
                VStack(spacing: w * 0.035) {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: w * 0.3, weight: .semibold))
                    Text(verbatim: "BARANOV")
                        .font(.system(size: w * 0.115, weight: .bold, design: .serif))
                        .kerning(0.6)
                        .lineLimit(1)
                    Text(verbatim: "SLOW POST")
                        .font(.system(size: w * 0.075, weight: .medium, design: .serif))
                        .kerning(0.8)
                        .lineLimit(1)
                        .opacity(0.85)
                }
                .foregroundStyle(Self.margin)
            }
            .mask {
                StampPerforation(pitch: w * 0.14)
                    .fill(style: FillStyle(eoFill: true))
            }
        }
        .aspectRatio(0.82, contentMode: .fit)
        .shadow(color: .black.opacity(0.2), radius: 0.8, x: 0, y: 0.8)
        .accessibilityHidden(true)
    }
}

// MARK: - Postmark

/// Wavy cancellation lines that run off the postmark's left side.
private struct PostmarkWaves: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rows = 4
        let steps = 24
        for row in 0..<rows {
            let y = rect.minY + rect.height * (CGFloat(row) + 0.5) / CGFloat(rows)
            path.move(to: CGPoint(x: rect.minX, y: y))
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                path.addLine(to: CGPoint(
                    x: rect.minX + rect.width * t,
                    y: y + sin(t * .pi * 4) * rect.height * 0.05
                ))
            }
        }
        return path
    }
}

/// Circular ink postmark: dispatch date, a rule, the distance walked.
struct PostmarkView: View {
    let date: Date
    let distanceText: String
    let ink: Color

    var body: some View {
        GeometryReader { proxy in
            let d = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().strokeBorder(ink, lineWidth: d * 0.03)
                Circle().strokeBorder(ink, lineWidth: d * 0.012).padding(d * 0.07)
                VStack(spacing: d * 0.025) {
                    Text(date.formatted(.dateTime.day().month(.abbreviated)).uppercased())
                        .font(.system(size: d * 0.125, weight: .bold, design: .monospaced))
                    Rectangle().fill(ink).frame(height: d * 0.012)
                    Text(distanceText)
                        .font(.system(size: d * 0.16, weight: .heavy, design: .monospaced))
                        .minimumScaleFactor(0.6)
                    Text(date.formatted(.dateTime.year()))
                        .font(.system(size: d * 0.105, weight: .semibold, design: .monospaced))
                }
                .lineLimit(1)
                .padding(.horizontal, d * 0.15)
            }
            .foregroundStyle(ink)
            .frame(width: d, height: d)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Envelope

private struct EnvelopeFlapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The envelope on the table. Layers, back to front: the letter sheet
/// (inside), the pocket with its fold lines and the "To:" line, the flap
/// (which swings up on its top edge and drops behind the sheet once it
/// is past vertical), then stamp, postmark, "From:" and the seal.
struct LetterEnvelopeView<Seal: View>: View {
    let senderName: String
    let recipientName: String
    let paper: PaperStyle
    /// When the letter was dispatched — printed in the postmark.
    let sentDate: Date
    /// Distance walked so far, already formatted ("0.6 km").
    let distanceText: String
    /// The flap is up.
    var isOpen = false
    /// The letter sheet has slid out of the pocket.
    var isLetterRisen = false
    @ViewBuilder var seal: () -> Seal

    /// Where the flap's tip — and so the seal — sits, as a fraction of height.
    static var flapTip: CGFloat { 0.5 }
    static var aspectRatio: CGFloat { 1.5 }

    @State private var flapIsBehind = false

    private let corner: CGFloat = 8

    private var sheetColor: Color {
        .adaptive(light: (1.0, 0.995, 0.975), dark: (0.25, 0.25, 0.27))
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height

            ZStack {
                letterSheet(width: w, height: h).zIndex(1)
                pocket(width: w, height: h).zIndex(2)
                flap(width: w, height: h).zIndex(flapIsBehind ? 0 : 3)
                markings(width: w, height: h).zIndex(4)
                seal()
                    .position(x: w / 2, y: h * Self.flapTip)
                    .zIndex(5)
            }
            .frame(width: w, height: h)
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .onAppear { flapIsBehind = isOpen }
        .onChange(of: isOpen) { _, open in
            if open {
                Task {
                    try? await Task.sleep(for: .milliseconds(240))
                    flapIsBehind = true
                }
            } else {
                flapIsBehind = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Letter from \(senderName) to \(recipientName)"))
    }

    // MARK: Layers

    /// The sheet inside the envelope. Hidden behind the pocket until it
    /// slides up.
    private func letterSheet(width w: CGFloat, height h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(sheetColor)
            .overlay(alignment: .top) {
                VStack(spacing: h * 0.065) {
                    ForEach(0..<5, id: \.self) { _ in
                        Rectangle().fill(paper.ink.opacity(0.1)).frame(height: 1)
                    }
                }
                .padding(.horizontal, w * 0.08)
                .padding(.top, h * 0.09)
            }
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.primary.opacity(0.06), lineWidth: 0.5))
            .frame(width: w * 0.88, height: h * 0.86)
            .offset(y: isLetterRisen ? -h * 0.58 : 0)
            .animation(.spring(response: 0.55, dampingFraction: 0.82), value: isLetterRisen)
    }

    private func pocket(width w: CGFloat, height h: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return ZStack {
            shape.fill(paper.color)
            PaperGrain().clipShape(shape)

            // The two side folds meeting at the flap's tip.
            Path { path in
                path.move(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: w / 2, y: h * Self.flapTip))
                path.move(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: w / 2, y: h * Self.flapTip))
            }
            .stroke(paper.ink.opacity(0.14), lineWidth: 0.8)

            // "To:" under the seal.
            VStack {
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("To:")
                        .font(.system(.footnote, design: .serif))
                        .foregroundStyle(paper.ink.opacity(0.6))
                    Text(recipientName)
                        .font(.system(.title2, design: .serif).italic())
                        .foregroundStyle(paper.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, w * 0.1)
                .padding(.bottom, h * 0.08)
            }
        }
        .frame(width: w, height: h)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)
        .shadow(color: .black.opacity(0.1), radius: 1.5, x: 0, y: 1)
    }

    private func flap(width w: CGFloat, height h: CGFloat) -> some View {
        EnvelopeFlapShape()
            .fill(paper.color)
            .overlay(EnvelopeFlapShape().fill(.black.opacity(isOpen ? 0.14 : 0.06)))
            .overlay(EnvelopeFlapShape().stroke(paper.ink.opacity(0.18), lineWidth: 0.8))
            .frame(width: w, height: h * Self.flapTip)
            .rotation3DEffect(
                .degrees(isOpen ? -168 : 0),
                axis: (x: 1, y: 0, z: 0),
                anchor: .top,
                perspective: 0.35
            )
            .position(x: w / 2, y: h * Self.flapTip / 2)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isOpen)
    }

    /// Everything printed or stamped on the face: it stays put when the
    /// flap swings away.
    private func markings(width w: CGFloat, height h: CGFloat) -> some View {
        let stampWidth = w * 0.15
        let stampHeight = stampWidth / 0.82
        let stampCenter = CGPoint(x: w - w * 0.05 - stampWidth / 2, y: h * 0.06 + stampHeight / 2)
        let markDiameter = w * 0.21
        let markCenter = CGPoint(x: stampCenter.x - stampWidth * 0.62, y: stampCenter.y + stampHeight * 0.34)
        let inkColor = paper.ink.opacity(0.55)

        return ZStack {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("From:")
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(paper.ink.opacity(0.6))
                Text(senderName)
                    .font(.system(.callout, design: .serif).italic())
                    .foregroundStyle(paper.ink.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.leading, w * 0.05)
            .padding(.top, h * 0.07)
            .frame(width: w * 0.5, height: h, alignment: .topLeading)
            .position(x: w * 0.25, y: h / 2)

            PostalStampView()
                .frame(width: stampWidth, height: stampHeight)
                .position(stampCenter)

            PostmarkWaves()
                .stroke(inkColor, lineWidth: 1)
                .frame(width: w * 0.14, height: markDiameter * 0.5)
                .position(x: markCenter.x - markDiameter / 2 - w * 0.05, y: markCenter.y)
                .accessibilityHidden(true)

            PostmarkView(date: sentDate, distanceText: distanceText, ink: inkColor)
                .frame(width: markDiameter, height: markDiameter)
                .rotationEffect(.degrees(-14))
                .position(markCenter)
        }
        .frame(width: w, height: h)
    }
}

#Preview("Envelope") {
    ScrollView {
        LetterEnvelopeView(
            senderName: "Anton",
            recipientName: "Mama",
            paper: PaperStyle(paper: .cream, customHex: nil),
            sentDate: .now,
            distanceText: "0.6 km"
        ) {
            WaxSealView(wax: .crimson, monogram: "A", diameter: 64)
        }
        .padding(24)
    }
    .background { LinenSurface().ignoresSafeArea() }
}
