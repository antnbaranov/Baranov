//
//  EnvelopePaper.swift
//  Baranov
//
//  The paper a letter travels on — chosen at the sealing step and shown
//  on the postcard, the envelope and, on arrival, the recipient's
//  envelope. Paper is a physical material, so these are fixed colours
//  (not semantic ones); text on them picks a legible ink per paper.
//

import SwiftUI

enum EnvelopePaper: String, Codable, CaseIterable, Identifiable, Sendable {
    case cream, kraft, navy, sage, terracotta

    var id: String { rawValue }

    /// Natural Cream comes with the app; the other papers come with
    /// "Expand the Pasture", like the wax colours.
    var isIncludedFree: Bool { true }

    var displayName: LocalizedStringKey {
        switch self {
        case .cream: return "Natural Cream"
        case .kraft: return "Vintage Kraft"
        case .navy: return "Deep Navy"
        case .sage: return "Sage Olive"
        case .terracotta: return "Terracotta"
        }
    }

    var color: Color {
        switch self {
        // Natural Cream is the app's default paper, so it follows the
        // appearance: warm parchment in Light, a dark charcoal-brown
        // sheet in Dark.
        case .cream: return .adaptive(light: (0.97, 0.94, 0.86), dark: (0.17, 0.17, 0.18))
        case .kraft: return Color(.sRGB, red: 0.79, green: 0.63, blue: 0.43)
        case .navy: return Color(.sRGB, red: 0.13, green: 0.20, blue: 0.36)
        case .sage: return Color(.sRGB, red: 0.62, green: 0.68, blue: 0.54)
        case .terracotta: return Color(.sRGB, red: 0.79, green: 0.42, blue: 0.30)
        }
    }

    /// Ink that reads on this paper.
    var ink: Color {
        switch self {
        case .navy, .terracotta: return Color(.sRGB, red: 0.97, green: 0.95, blue: 0.90)
        case .cream: return .adaptive(light: (0.16, 0.13, 0.10), dark: (0.96, 0.96, 0.98))
        default: return Color(.sRGB, red: 0.16, green: 0.13, blue: 0.10)
        }
    }
}

extension Color {
    /// A colour that resolves differently in Light and Dark.
    static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    /// `#RRGGBB` for a fixed (non-dynamic) colour; used to store a picked paper colour.
    var paperHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    init?(paperHex: String) {
        var h = paperHex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// A paper plus an optional colour the writer picked on the colour wheel.
/// A picked colour wins over the preset; ink is chosen by the colour's
/// luminance so the text is always legible on it.
struct PaperStyle: Equatable {
    var paper: EnvelopePaper
    var customHex: String?

    private var custom: Color? { customHex.flatMap { Color(paperHex: $0) } }

    var color: Color { custom ?? paper.color }

    var ink: Color {
        guard let custom else { return paper.ink }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(custom).getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.55 ? Color(.sRGB, red: 0.16, green: 0.13, blue: 0.10)
                                : Color(.sRGB, red: 0.97, green: 0.95, blue: 0.90)
    }
}

/// Faint paper grain — a fixed scatter of specks, so it never shimmers
/// between redraws.
struct PaperGrain: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(1 << 31)
            }
            for _ in 0..<Int(size.width * size.height / 90) {
                let rect = CGRect(x: next() * size.width, y: next() * size.height, width: 1, height: 1)
                let dark = next() > 0.5
                context.fill(Path(rect), with: .color((dark ? Color.black : Color.white).opacity(0.05)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// The letter as a postcard: message on the left, address and stamp box
/// on the right, on the chosen paper.
struct PostcardView: View {
    var paper: EnvelopePaper
    var addressee: String
    var excerpt: String
    var wax: SealColor
    var monogram: String
    var showsSeal: Bool = false
    /// A colour picked on the colour wheel; overrides the preset paper.
    var customHex: String? = nil

    private var style: PaperStyle { PaperStyle(paper: paper, customHex: customHex) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(excerpt.isEmpty ? " " : excerpt)
                .font(.system(.footnote, design: .serif).italic())
                .foregroundStyle(style.ink.opacity(0.85))
                .lineLimit(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Rectangle()
                .fill(style.ink.opacity(0.25))
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(style.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .frame(width: 26, height: 32)
                }
                Spacer(minLength: 0)
                Text(addressee)
                    .font(.system(.subheadline, design: .serif, weight: .semibold))
                    .foregroundStyle(style.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                ForEach(0..<2, id: \.self) { _ in
                    Rectangle().fill(style.ink.opacity(0.25)).frame(height: 1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .aspectRatio(1.55, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                style.color
                PaperGrain()
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        .overlay(alignment: .bottomTrailing) {
            if showsSeal {
                WaxSealView(wax: wax, monogram: monogram, diameter: 46)
                    .padding(14)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 7)
        .shadow(color: .black.opacity(0.10), radius: 1.5, x: 0, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Postcard to \(addressee)")
    }
}
