//
//  BaranovLiveActivityView.swift
//  BaranovWidget
//
//  Live Activity + Dynamic Island for a ram on its journey.
//
//  Follows the pattern Apple uses for delivery/ride Live Activities: one
//  glanceable hero number, a progress track with the traveller riding along it,
//  and endpoints underneath. Standard system type styles and semantic
//  foreground styles only, so Dynamic Type, Always-On and dark/light all work.
//
import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Widget

struct BaranovLiveActivityView: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RamActivityAttributes.self) { context in
            LockScreenLiveActivityView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(.liveActivityBackground)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded: sprite left, hero distance right, name centred, track below.
                DynamicIslandExpandedRegion(.leading) {
                    RamSprite(pose: context.state.pose, height: 52)
                        .padding(.leading, 4)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(context.state.remainingDistance)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("to go")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.ramName)
                            .font(.headline)
                            .lineLimit(1)
                        Label(context.state.statusLabel, systemImage: context.state.statusSymbol)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        JourneyTrack(progress: context.state.progress, pose: context.state.pose, spriteHeight: 30)
                        RouteRow(from: context.attributes.fromCity,
                                 to: context.attributes.toCity,
                                 progress: context.state.progress)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
            } compactLeading: {
                RamSprite(pose: context.state.pose, height: 22)
                    .padding(.leading, 2)
                    .accessibilityHidden(true)
            } compactTrailing: {
                Text(context.state.remainingDistance)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .fixedSize()
            } minimal: {
                MinimalProgressRing(progress: context.state.progress, pose: context.state.pose)
            }
            .keylineTint(.accentColor)
            .widgetURL(URL(string: "baranov://pasture"))
        }
    }
}

// MARK: - Background

private extension Color {
    /// Soft parchment in light mode, warm charcoal in dark mode, so the Lock Screen
    /// card reads as a light, native card instead of the default near-black slab.
    static let liveActivityBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.20, green: 0.18, blue: 0.16, alpha: 0.92)
            : UIColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 0.92)
    })
}

// MARK: - Lock Screen / banner

struct LockScreenLiveActivityView: View {
    let attributes: RamActivityAttributes
    let state: RamActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(attributes.ramName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Label(state.statusLabel, systemImage: state.statusSymbol)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(routeDescription(from: attributes.fromCity, to: attributes.toCity))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(state.remainingDistance)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("to go")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            JourneyTrack(progress: state.progress, pose: state.pose, spriteHeight: 38)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(attributes.ramName), \(state.statusLabel). \(state.remainingDistance) to go from \(attributes.fromCity) to \(attributes.toCity), \(state.percentComplete) percent complete."
        )
    }
}

// MARK: - Building blocks

/// The ram, drawn from the bundled sprite art for the current pose.
struct RamSprite: View {
    let pose: RamActivityPose
    let height: CGFloat

    var body: some View {
        Image(pose.assetName)
            .resizable()
            .scaledToFit()
            .frame(height: height)
    }
}

/// A track with the ram standing on it, advancing left → right with progress.
struct JourneyTrack: View {
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

                RamSprite(pose: pose, height: spriteHeight)
                    .offset(x: x, y: -(trackHeight - 2))
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: spriteHeight + trackHeight - 2)
        .animation(.smooth, value: progress)
        .accessibilityHidden(true)
    }
}

/// "A → B", or just the place name when origin and destination match.
func routeDescription(from: String, to: String) -> String {
    from == to || from.isEmpty ? to : "\(from) \u{2192} \(to)"
}

/// Route on the left (one line, truncates), percent on the right (never truncates).
/// When origin and destination are the same place (e.g. arrived), the name is shown once.
struct RouteRow: View {
    let from: String
    let to: String
    let progress: Double

    private var routeText: String { routeDescription(from: from, to: to) }

    var body: some View {
        HStack(spacing: 8) {
            Label(routeText, systemImage: "mappin.and.ellipse")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text("\(Int((min(max(progress, 0), 1) * 100).rounded()))%")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.primary)
                .fixedSize()
        }
    }
}

/// Circular progress with the ram inside, for the minimal Dynamic Island.
private struct MinimalProgressRing: View {
    let progress: Double
    let pose: RamActivityPose

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            RamSprite(pose: pose, height: 12)
        }
        .padding(2)
        .accessibilityLabel("Journey \(Int((progress * 100).rounded())) percent complete")
    }
}

// MARK: - Pose mapping

/// Which sprite frame to show. Derived from the existing content state so the
/// ActivityKit payload (shared with the app) does not change.
enum RamActivityPose {
    case idle, run, leap

    var assetName: String {
        switch self {
        case .idle: return "RamIdle"
        case .run: return "RamRun"
        case .leap: return "RamLeap"
        }
    }

    /// Width / height of the bundled frame, so the track can reserve room.
    var aspectRatio: CGFloat {
        switch self {
        case .idle: return 215.0 / 200.0
        case .run: return 304.0 / 197.0
        case .leap: return 184.0 / 218.0
        }
    }
}

extension RamActivityAttributes.ContentState {
    var pose: RamActivityPose {
        switch statusSymbol {
        case "figure.walk": return .run
        case "flag.checkered", "checkmark.seal.fill": return .leap
        default: return .idle
        }
    }

    var percentComplete: Int { Int((min(max(progress, 0), 1) * 100).rounded()) }
}
