//
//  BaranovLiveActivityView.swift
//  BaranovWidget
//
//  Live Activity + Dynamic Island for a ram on its journey.
//
//  Follows the pattern Apple uses for delivery/ride Live Activities: one
//  glanceable hero number, a plain progress bar and endpoints underneath.
//  The ram appears once, at the leading edge, never on the bar.
//
//  A Live Activity cannot run a free-standing animation loop, so the motion
//  comes from three things the system does animate: the gait frame that
//  advances with every update (`stride`), the distance and progress that
//  transition between updates, and a walking clock that ticks by itself
//  with no update at all (`Text(_:style: .timer)`).
//
//  The app has no background mode, so between updates the card runs on its
//  own: the bar (`ProgressView(timerInterval:)`) and the ETA countdown
//  (`Text(timerInterval:)`) slide toward the estimated arrival at the pace
//  the person was walking. That projection is only trusted until the card's
//  `staleDate`; after that the card freezes on the last real numbers, the
//  ram stands still, and it says when it was last updated. A HealthKit
//  background wake or opening the app brings the real numbers back.
//
//  Standard system type styles and semantic foreground styles only, so
//  Dynamic Type, Always-On and dark/light all work.
//
import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Widget

struct BaranovLiveActivityView: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RamActivityAttributes.self) { context in
            LockScreenLiveActivityView(attributes: context.attributes, state: context.state, isStale: context.isStale)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded: sprite left, hero distance right, name centred, track below.
                DynamicIslandExpandedRegion(.leading) {
                    LiveRam(state: context.state, height: 48, isStale: context.isStale)
                        .padding(.leading, 4)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    DistanceStack(distance: context.state.remainingDistance, valueFont: .title2, unitFont: .caption)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.ramName)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        StatusRow(state: context.state, isStale: context.isStale)
                        LiveTrack(state: context.state, isStale: context.isStale, height: 8)
                        RouteRow(from: context.attributes.fromCity,
                                 to: context.attributes.toCity,
                                 progress: context.state.progress)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
            } compactLeading: {
                LiveRam(state: context.state, height: 22, isStale: context.isStale)
                    .padding(.leading, 2)
                    .accessibilityHidden(true)
            } compactTrailing: {
                CompactTrailing(state: context.state, isStale: context.isStale)
            } minimal: {
                MinimalProgressRing(state: context.state, isStale: context.isStale)
            }
            .keylineTint(.accentColor)
            .widgetURL(URL(string: "baranov://pasture"))
        }
    }
}

// MARK: - Background

/// The card colors are chosen from the color scheme the Lock Screen is rendering the card in, read from
/// the view's own environment, so the background and the `.primary` / `.secondary` text always come from
/// the same scheme. A dynamic `UIColor` handed to `activityBackgroundTint` is resolved separately from the
/// text and could land light behind white text (or dark behind black text).
private enum CardBackground {
    /// Soft parchment in light mode, warm charcoal in dark mode.
    static func standard(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.20, green: 0.18, blue: 0.16)
            : Color(red: 0.98, green: 0.96, blue: 0.92)
    }

    /// The same card warmed toward wax-seal gold, shown only once the ram has reached the gate or the
    /// letter has been delivered: a quiet "arrived" cue rather than a new layout.
    static func arrival(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.30, green: 0.21, blue: 0.10)
            : Color(red: 0.99, green: 0.92, blue: 0.78)
    }
}

// MARK: - Lock Screen / banner

struct LockScreenLiveActivityView: View {
    let attributes: RamActivityAttributes
    let state: RamActivityAttributes.ContentState
    var isStale: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                LiveRam(state: state, height: 46, isStale: isStale)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attributes.ramName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    StatusRow(state: state, isStale: isStale)
                    Text(routeDescription(from: attributes.fromCity, to: attributes.toCity))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                DistanceStack(distance: state.remainingDistance, valueFont: .title, unitFont: .caption)
            }

            LiveTrack(state: state, isStale: isStale, height: 8)
            StatsRow(state: state, isStale: isStale)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .activityBackgroundTint(state.hasArrived ? CardBackground.arrival(colorScheme) : CardBackground.standard(colorScheme))
        .activitySystemActionForegroundColor(colorScheme == .dark ? .white : .black)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(attributes.ramName), \(state.statusLabel). \(state.remainingDistance) to go from \(attributes.fromCity) to \(attributes.toCity), \(state.percentComplete) percent complete."
        )
    }
}

// MARK: - Building blocks

/// The ram, drawn from the bundled sprite art. While walking, `stride` picks
/// the gait frame, so every update the ram takes another step. The frame is
/// laid out in a fixed box so swapping frames never shifts the layout.
struct RamSprite: View {
    let pose: RamActivityPose
    let stride: Int
    let height: CGFloat

    /// The gait frame if it is bundled, otherwise the single run frame, so the
    /// ram can never render as an empty box.
    private var imageName: String {
        let name = pose.assetName(stride: stride)
        return UIImage(named: name) != nil ? name : "RamRun"
    }

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(width: height * pose.aspectRatio, height: height)
            // A small hop on every other step, so the gait reads as a gait.
            .offset(y: pose == .run && stride.isMultiple(of: 2) ? -height * 0.04 : 0)
            .animation(.snappy(duration: 0.25), value: stride)
    }
}

/// The ram for the Live Activity and Dynamic Island. A Live Activity cannot run
/// a loop of its own, so every update is made to count: the gait advances one
/// frame, the ram tips and hops with a bouncy spring, and every eighth step it
/// leaps with a little sparkle. On arrival it stays mid-leap and celebrates.
///
/// The frame box is fixed at the widest sprite, so changing pose never nudges
/// the text next to it.
struct LiveRam: View {
    let state: RamActivityAttributes.ContentState
    let height: CGFloat
    var showsExtras: Bool = true
    /// A stale card no longer knows whether the person is walking, so the
    /// ram stands still rather than trotting on a guess.
    var isStale: Bool = false

    private var pose: RamActivityPose { state.livePose(isStale: isStale) }
    private var stride: Int { state.strideFrame }
    private var isEvenStep: Bool { stride.isMultiple(of: 2) }

    private var imageName: String {
        let name = pose.assetName(stride: stride)
        return UIImage(named: name) != nil ? name : "RamRun"
    }

    private var tilt: Double {
        switch pose {
        case .run: return isEvenStep ? -4 : 4
        case .leap: return -8
        case .idle: return 0
        }
    }

    private var lift: CGFloat {
        switch pose {
        case .run: return isEvenStep ? -height * 0.08 : 0
        case .leap: return -height * 0.12
        case .idle: return 0
        }
    }

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(width: height * RamActivityPose.widestAspectRatio, height: height)
            .rotationEffect(.degrees(tilt), anchor: .bottom)
            .offset(y: lift)
            .overlay(alignment: .topTrailing) {
                if showsExtras, pose == .leap {
                    Image(systemName: "sparkles")
                        .font(.system(size: height * 0.32, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                        .offset(x: -height * 0.02, y: -height * 0.06)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.bouncy(duration: 0.45, extraBounce: 0.25), value: stride)
            .animation(.bouncy(duration: 0.45, extraBounce: 0.25), value: pose)
    }
}

/// A plain progress bar. The ram is not drawn on it; it already stands
/// at the leading edge, so the bar keeps the full width for the distance.
struct JourneyTrack: View {
    let progress: Double
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.quaternary)
                Capsule(style: .continuous)
                    .fill(.tint)
                    .frame(width: max(height, geo.size.width * clamped))
            }
        }
        .frame(height: height)
        .animation(.smooth, value: progress)
        .accessibilityHidden(true)
    }
}

/// Status label, weather and, while walking, a clock that counts up on its
/// own. The clock is the one element that moves between updates.
struct StatusRow: View {
    let state: RamActivityAttributes.ContentState
    var isStale: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Label {
                Text(state.displayLabel(isStale: isStale))
            } icon: {
                Image(systemName: state.displaySymbol(isStale: isStale))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: state.strideFrame)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            if !isStale, state.isWalking, state.isMovingNow, let since = state.walkingSince {
                Text(since, style: .timer)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 64, alignment: .leading)
                    .accessibilityLabel("Walking time")
            }
            if let weatherSymbol = state.weatherSymbol {
                Image(systemName: weatherSymbol)
                    .font(.subheadline)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Current weather")
            }
        }
    }
}

/// Splits "12.3 km" into ("12.3", "km") and "850 m" into ("850", "m").
func splitDistance(_ distance: String) -> (value: String, unit: String) {
    let parts = distance.split(separator: " ", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return (distance, "") }
    return (parts[0], parts[1])
}

/// The hero distance on two lines: the number, then its unit underneath.
struct DistanceStack: View {
    let distance: String
    let valueFont: Font.TextStyle
    let unitFont: Font.TextStyle

    var body: some View {
        let parts = splitDistance(distance)
        VStack(alignment: .trailing, spacing: 0) {
            Text(parts.value)
                .font(.system(valueFont, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(parts.unit)
                .font(.system(unitFont))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(distance) to go")
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
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text("\(Int((min(max(progress, 0), 1) * 100).rounded()))%")
                .font(.system(.caption, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.primary)
                .fixedSize()
        }
    }
}

/// Circular progress with the ram inside, for the minimal Dynamic Island.
private struct MinimalProgressRing: View {
    let state: RamActivityAttributes.ContentState
    var isStale: Bool = false

    var body: some View {
        let progress = min(max(state.progress, 0), 1)
        ZStack {
            if let range = state.liveRange(isStale: isStale) {
                // Sweeps by itself between updates.
                ProgressView(timerInterval: range, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(.accentColor)
            } else {
                Circle().stroke(.quaternary, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            LiveRam(state: state, height: 12, showsExtras: false, isStale: isStale)
        }
        .padding(2)
        .accessibilityLabel("Journey \(Int((progress * 100).rounded())) percent complete")
    }
}

// MARK: - Live (self-animating) pieces

/// The progress bar. While the shepherd is walking it is a system timer bar
/// (`ProgressView(timerInterval:)`), which the system slides forward every
/// frame with no update at all; otherwise a plain static capsule.
struct LiveTrack: View {
    let state: RamActivityAttributes.ContentState
    let isStale: Bool
    let height: CGFloat

    var body: some View {
        if let range = state.liveRange(isStale: isStale) {
            ProgressView(timerInterval: range, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(.accentColor)
            .scaleEffect(x: 1, y: height / 4, anchor: .center)
            .frame(height: height)
            .accessibilityHidden(true)
        } else {
            JourneyTrack(progress: state.progress, height: height)
        }
    }
}

/// Steps walked and cadence, so the card shows more than one distance.
struct StatsRow: View {
    let state: RamActivityAttributes.ContentState
    var isStale: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            if let walked = state.stepsWalked {
                Label {
                    Text("\(walked.formatted()) steps")
                        .contentTransition(.numericText())
                } icon: {
                    Image(systemName: "shoeprints.fill")
                }
            }
            if let range = state.liveRange(isStale: isStale) {
                // Counts down to the estimated arrival by itself, no update needed.
                Label {
                    Text(timerInterval: range, countsDown: true)
                        .frame(maxWidth: 72, alignment: .leading)
                } icon: {
                    Image(systemName: "flag.checkered")
                }
                .accessibilityLabel("Estimated time to arrival")
            } else if !isStale, state.isWalking, state.isMovingNow, let spm = state.stepsPerMinute, spm > 0 {
                Label {
                    Text("\(spm)/min")
                        .contentTransition(.numericText())
                } icon: {
                    Image(systemName: "speedometer")
                }
            }
            if isStale, state.isWalking, let updatedAt = state.updatedAt {
                Label {
                    Text("Updated \(updatedAt, style: .relative) ago")
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .animation(.smooth, value: state.stepsWalked)
    }
}

/// Compact trailing slot: while walking, a ring that sweeps on its own around
/// the state icon; in every other state the icon plus the distance.
struct CompactTrailing: View {
    let state: RamActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if let range = state.liveRange(isStale: isStale) {
            ZStack {
                ProgressView(timerInterval: range, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .tint(.accentColor)
                Image(systemName: state.displaySymbol(isStale: isStale))
                    .font(.system(size: 9, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: state.strideFrame)
            }
            .frame(width: 22, height: 22)
            .accessibilityLabel("\(state.remainingDistance) to go")
        } else {
            HStack(spacing: 3) {
                Image(systemName: state.displaySymbol(isStale: isStale))
                    .font(.system(.footnote, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(state.remainingDistance)
                    .font(.system(.footnote, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }
            .fixedSize()
        }
    }
}

extension RamActivityAttributes.ContentState {
    /// The self-running interval, only while walking and while the card is
    /// still fresh and the end is ahead of us.
    func liveRange(isStale: Bool) -> ClosedRange<Date>? {
        guard !isStale, isWalking, isMovingNow,
              let start = barStart, let end = barEnd, start < end, end > Date() else { return nil }
        return start...end
    }
}

// MARK: - Pose mapping

/// Which sprite frame to show. Derived from the existing content state so the
/// ActivityKit payload (shared with the app) does not change.
enum RamActivityPose {
    case idle, run, leap

    /// Number of gait frames bundled in the widget (`RamStride0…6`).
    static let strideFrameCount = 7

    /// A walking ram takes seven steps, then leaps on the eighth.
    static let walkCycleLength = 8

    /// The widest sprite, used to reserve a fixed frame in the Live Activity.
    static let widestAspectRatio: CGFloat = 313.0 / 202.0

    func assetName(stride: Int) -> String {
        switch self {
        case .idle: return "RamIdle"
        case .leap: return "RamLeap"
        case .run:
            let beat = ((stride % Self.walkCycleLength) + Self.walkCycleLength) % Self.walkCycleLength
            return "RamStride\(min(beat, Self.strideFrameCount - 1))"
        }
    }

    /// Width / height of the bundled frame, so layouts can reserve room.
    var aspectRatio: CGFloat {
        switch self {
        case .idle: return 215.0 / 200.0
        case .run: return 313.0 / 202.0
        case .leap: return 184.0 / 218.0
        }
    }
}

extension RamActivityAttributes.ContentState {
    func livePose(isStale: Bool) -> RamActivityPose {
        switch statusSymbol {
        case "figure.walk":
            // Paused, or a stale card that no longer knows: the ram stands still.
            if isStale || !isMovingNow { return .idle }
            // Seven steps, then a happy leap, so the ram is never just a loop.
            let beat = ((strideFrame % RamActivityPose.walkCycleLength) + RamActivityPose.walkCycleLength) % RamActivityPose.walkCycleLength
            return beat == RamActivityPose.walkCycleLength - 1 ? .leap : .run
        case "flag.checkered", "checkmark.seal.fill": return .leap
        default: return .idle
        }
    }

    var isWalking: Bool { statusSymbol == "figure.walk" }

    /// Older builds never send `isMoving`; treat that as moving.
    var isMovingNow: Bool { isMoving ?? true }

    /// What the card says and shows. A walking ram whose shepherd has stopped
    /// reads "Paused" with a pause glyph, so a still ram is never mistaken for
    /// a frozen card.
    ///
    /// A stale card never says "Paused": the person may well be walking with
    /// the phone locked. It shows the plain status and when it was updated.
    func displayLabel(isStale: Bool) -> String {
        !isStale && isWalking && !isMovingNow ? String(localized: "Paused") : statusLabel
    }

    func displaySymbol(isStale: Bool) -> String {
        !isStale && isWalking && !isMovingNow ? "pause.circle.fill" : statusSymbol
    }

    var stepsWalked: Int? {
        guard let totalSteps else { return nil }
        return max(0, totalSteps - remainingSteps)
    }

    /// Gait frame for this update; advances every time the app pushes one.
    var strideFrame: Int { stride ?? 0 }

    var percentComplete: Int { Int((min(max(progress, 0), 1) * 100).rounded()) }

    /// True once the ram has reached the gate or the letter has been
    /// delivered — the moment the Live Activity's card should feel warmer,
    /// not just report a number.
    var hasArrived: Bool {
        statusSymbol == "flag.checkered" || statusSymbol == "checkmark.seal.fill"
    }
}
