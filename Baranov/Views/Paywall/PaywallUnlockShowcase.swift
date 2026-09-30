//
//  PaywallUnlockShowcase.swift
//  Baranov
//
//  "See what the pasture unlocks": two short looping demonstrations, one
//  per Premium Touch that has no picture of its own — the time capsule
//  and the geo-lock. Each plays the whole mechanic in about seven
//  seconds (a capsule counting down until its lock opens; a courier
//  walking into a place until the lock opens) and starts over.
//
//  Deliberately quiet: white cards on the grouped gray background like
//  every other screen, primary/secondary/tertiary styles and system grays
//  only, no accent colour, no gradients. Under Reduce Motion each card
//  holds one still frame instead of looping.
//

import SwiftUI

// MARK: - Card chrome

extension View {
    /// The one card surface the paywall uses: white (elevated grouped
    /// background) sitting on the gray grouped background.
    func paywallCard(cornerRadius: CGFloat = 20) -> some View {
        background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}

// MARK: - Showcase

struct PaywallUnlockShowcase: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("See what the pasture unlocks")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            HStack(alignment: .top, spacing: 12) {
                TimeCapsuleDemoCard()
                GeoLockDemoCard()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shared helpers

private enum DemoClock {
    /// 0 ..< 1, repeating every `period` seconds.
    static func phase(_ date: Date, period: Double) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
    }

    static func smooth(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    /// Where `t` sits between `lower` and `upper`, clamped to 0...1.
    static func progress(_ t: Double, from lower: Double, to upper: Double) -> Double {
        guard upper > lower else { return t >= upper ? 1 : 0 }
        return min(max((t - lower) / (upper - lower), 0), 1)
    }
}

private struct DemoCaption: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Time capsule

/// A ring drains while a countdown races through three days; when it hits
/// zero the lock opens and the letter inside appears. Then it re-seals.
private struct TimeCapsuleDemoCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period = 8.0
    /// The sample wait the countdown covers: 3 days, 4 hours, 12 minutes.
    private static let totalSeconds = 3 * 86_400 + 4 * 3_600 + 12 * 60

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
                let t = reduceMotion ? 0.35 : DemoClock.phase(context.date, period: Self.period)
                capsule(at: t)
            }
            .frame(height: 124)
            .frame(maxWidth: .infinity)
            .background(
                Color(uiColor: .systemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .accessibilityHidden(true)

            DemoCaption(
                title: "Time capsule",
                detail: "Sealed until the moment you pick. Nobody can open it early."
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paywallCard()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func capsule(at t: Double) -> some View {
        // 0 – 0.62: countdown runs, eased so it hurries at the end.
        // 0.62 – 0.72: lock lets go. 0.72 – 0.92: letter shown. Then reset.
        let drain = DemoClock.smooth(DemoClock.progress(t, from: 0.02, to: 0.62))
        let remaining = Int(Double(Self.totalSeconds) * (1 - drain))
        let isOpen = t >= 0.66 && t < 0.94
        let ringFraction = isOpen ? 0.0 : max(0.0, 1 - drain)

        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color(uiColor: .systemGray5), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: ringFraction)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: isOpen ? "envelope.open.fill" : "lock.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
                    .scaleEffect(isOpen ? 1.12 : 1)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isOpen)
            }
            .frame(width: 62, height: 62)

            Text(isOpen ? String(localized: "Opens now", bundle: .appLanguage, locale: .appLanguage) : Self.countdownString(remaining))
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(isOpen ? .primary : .secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private static func countdownString(_ seconds: Int) -> String {
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        let secs = seconds % 60
        let dayPart = String(localized: "\(days)d", bundle: .appLanguage, locale: .appLanguage,
                             comment: "Days in a countdown, abbreviated to one letter where the language allows, e.g. 3d.")
        return dayPart + String(format: " %02d:%02d:%02d", hours, minutes, secs)
    }
}

// MARK: - Geo-lock

/// A courier walks toward a place; outside the dashed radius the lock
/// stays shut, the moment it crosses in, the ring firms up and the lock
/// opens. Then the courier starts over.
private struct GeoLockDemoCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period = 8.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
                let t = reduceMotion ? 0.3 : DemoClock.phase(context.date, period: Self.period)
                GeoLockScene(phase: t)
            }
            .frame(height: 124)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)

            DemoCaption(
                title: "Geo-lock",
                detail: "Opens only at the place you choose, when the reader is really there."
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paywallCard()
        .accessibilityElement(children: .combine)
    }
}

private struct GeoLockScene: View {
    /// 0 ..< 1 through the loop.
    let phase: Double

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width * 0.58, y: size.height * 0.46)
            let radius = min(size.width, size.height) * 0.27
            let start = CGPoint(x: size.width * 0.10, y: size.height * 0.86)

            // Walk in 0.08 – 0.62, hold inside 0.62 – 0.92, reset.
            let walk = DemoClock.smooth(DemoClock.progress(phase, from: 0.08, to: 0.62))
            let dot = CGPoint(
                x: start.x + (center.x - start.x) * walk,
                y: start.y + (center.y - start.y) * walk
            )
            let pixelDistance = hypot(dot.x - center.x, dot.y - center.y)
            let isInside = pixelDistance <= radius && phase < 0.94
            let meters = Int((pixelDistance / radius * 100).rounded())

            ZStack {
                Color(uiColor: .systemGroupedBackground)

                streets(in: size)

                // The zone.
                Circle()
                    .fill(Color.primary.opacity(isInside ? 0.07 : 0.03))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)
                Circle()
                    .strokeBorder(
                        Color.primary.opacity(isInside ? 0.7 : 0.35),
                        style: StrokeStyle(lineWidth: 1.5, dash: isInside ? [] : [5, 4])
                    )
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)
                    .animation(.easeInOut(duration: 0.3), value: isInside)

                // One soft ring leaving the zone the moment it opens.
                if isInside {
                    let burst = DemoClock.progress(phase, from: 0.62, to: 0.80)
                    Circle()
                        .stroke(Color.primary.opacity(0.25 * (1 - burst)), lineWidth: 1.5)
                        .frame(width: radius * 2 * (1 + burst * 0.5), height: radius * 2 * (1 + burst * 0.5))
                        .position(center)
                }

                Image(systemName: isInside ? "lock.open.fill" : "lock.fill")
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
                    .scaleEffect(isInside ? 1.15 : 1)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isInside)
                    .position(center)

                // The reader, walking in.
                Circle()
                    .fill(Color.primary)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().strokeBorder(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 2))
                    .position(dot)
                    .opacity(phase < 0.94 ? 1 : 0)

                Text(isInside ? "Here" : "\(meters) m")
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(isInside ? .primary : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())
                    .position(x: size.width - 34, y: size.height - 16)
            }
        }
    }

    /// A few plain street lines so the zone reads as a place on a map.
    private func streets(in size: CGSize) -> some View {
        Canvas { context, canvas in
            var path = Path()
            for fraction in [0.22, 0.56, 0.84] {
                path.move(to: CGPoint(x: 0, y: canvas.height * fraction))
                path.addLine(to: CGPoint(x: canvas.width, y: canvas.height * (fraction - 0.08)))
            }
            for fraction in [0.18, 0.5, 0.82] {
                path.move(to: CGPoint(x: canvas.width * fraction, y: 0))
                path.addLine(to: CGPoint(x: canvas.width * (fraction + 0.06), y: canvas.height))
            }
            context.stroke(path, with: .color(Color(uiColor: .systemGray5)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
        .frame(width: size.width, height: size.height)
    }
}

#Preview {
    PaywallUnlockShowcase()
        .padding(20)
        .background(Color(uiColor: .systemGroupedBackground))
}
