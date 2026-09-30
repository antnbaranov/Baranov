//
//  BaranovWidgetView.swift
//  BaranovWidget
//
import SwiftUI
import WidgetKit

struct BaranovWidgetView: View {
    let entry: BaranovWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            MediumBaranovWidgetView(entry: entry)
        default:
            SmallBaranovWidgetView(entry: entry)
        }
    }
}

private extension BaranovWidgetEntry {
    var pose: RamActivityPose {
        switch statusSymbol {
        case "figure.walk": return .run
        case "flag.checkered", "checkmark.seal.fill": return .leap
        default: return .idle
        }
    }

    var accessibilityDescription: String {
        if let name = ramName, let remaining = remainingDistance {
            return "\(name), \(statusLabel), \(remaining) to go, \(Int((progress * 100).rounded())) percent complete"
        }
        return "Baranov Pasture, no rams currently walking"
    }
}

/// Distance number + "to go", matching the Live Activity.
private struct HeroDistance: View {
    let text: String
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(text)
                .font(.system(.title, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("to go")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct EmptyPastureView: View {
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            RamSprite(pose: .idle, stride: 0, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pasture")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct SmallBaranovWidgetView: View {
    let entry: BaranovWidgetEntry

    var body: some View {
        Group {
            if let name = entry.ramName, let remaining = entry.remainingDistance {
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Label(entry.statusLabel, systemImage: entry.statusSymbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    HeroDistance(text: remaining)
                    RamRidingTrack(progress: entry.progress, pose: entry.pose, spriteHeight: 26)
                        .padding(.top, 6)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Spacer(minLength: 0)
                    RamSprite(pose: .idle, stride: 0, height: 52)
                        .accessibilityHidden(true)
                    Text("Pasture")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("No rams walking")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(.background, for: .widget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityDescription)
    }
}

struct MediumBaranovWidgetView: View {
    let entry: BaranovWidgetEntry

    var body: some View {
        Group {
            if let name = entry.ramName, let remaining = entry.remainingDistance {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Label(entry.statusLabel, systemImage: entry.statusSymbol)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 12)
                        HeroDistance(text: remaining, alignment: .trailing)
                    }
                    Spacer(minLength: 0)
                    RamRidingTrack(progress: entry.progress, pose: entry.pose, spriteHeight: 32)
                    RouteRow(from: entry.fromCity ?? "", to: entry.toCity ?? "", progress: entry.progress)
                }
            } else {
                EmptyPastureView(subtitle: "Your rams are resting")
            }
        }
        .containerBackground(.background, for: .widget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityDescription)
    }
}

#Preview(as: .systemSmall) {
    BaranovHomeWidget()
} timeline: {
    BaranovWidgetEntry.placeholder
    BaranovWidgetEntry.empty
}

#Preview(as: .systemMedium) {
    BaranovHomeWidget()
} timeline: {
    BaranovWidgetEntry.placeholder
    BaranovWidgetEntry.empty
}

/// Home-screen widget only: the ram rides along the bar, because the widget
/// has no other ram on it. The Live Activity uses the plain `JourneyTrack`.
struct RamRidingTrack: View {
    let progress: Double
    let pose: RamActivityPose
    let spriteHeight: CGFloat

    private let trackHeight: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let spriteWidth = spriteHeight * pose.aspectRatio
            let travel = max(0, geo.size.width - spriteWidth)
            let x = travel * min(max(progress, 0), 1)

            ZStack(alignment: .bottomLeading) {
                Capsule(style: .continuous)
                    .fill(.quaternary)
                    .frame(height: trackHeight)

                Capsule(style: .continuous)
                    .fill(.tint)
                    .frame(width: max(trackHeight, x + spriteWidth / 2), height: trackHeight)

                RamSprite(pose: pose, stride: 0, height: spriteHeight)
                    .offset(x: x, y: -(trackHeight - 2))
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: spriteHeight + trackHeight - 2)
        .accessibilityHidden(true)
    }
}
