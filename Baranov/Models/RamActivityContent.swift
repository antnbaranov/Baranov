//
//  RamActivityContent.swift
//  Baranov
//
//  Builds the Live Activity's content state from a ram. Shared by the
//  foreground path (`FlockViewModel`, real step callbacks) and the
//  background path (`BackgroundStepSync`, a HealthKit wake with the app
//  otherwise suspended), so both draw exactly the same card.
//
//  Baranov has no background mode for location. While the app is
//  suspended the card animates on its own toward an estimated arrival
//  (`barStart`/`barEnd`, drawn with `ProgressView(timerInterval:)` and
//  `Text(timerInterval:)`), and the `staleDate` windows below cap how long
//  that estimate is trusted before the widget falls back to the last real
//  numbers.
//

import ActivityKit
import Foundation

extension RamActivityAttributes.ContentState {
    /// How long a projection pushed from the background is trusted. If the
    /// person stops walking with the phone locked, the bar can run ahead of
    /// the real count for at most this long before the card goes stale and
    /// snaps back to the last real numbers.
    static let backgroundProjectionWindow: TimeInterval = 20 * 60

    /// How long a non-moving ("Paused") card pushed from the background is
    /// trusted. Kept short: the person may start walking with the phone
    /// locked, and a stale card says "Updated … ago" rather than "Paused".
    static let backgroundIdleWindow: TimeInterval = 5 * 60

    /// Slower than this (steps per second) is not a walk worth projecting.
    static let minimumProjectedPace: Double = 0.3

    /// Longest estimate worth drawing. Beyond this the bar would crawl too
    /// slowly to read and the countdown would mean nothing.
    static let maximumProjection: TimeInterval = 6 * 3600

    /// Estimated arrival for `remainingSteps` at `stepsPerSecond`, or `nil`
    /// when the pace is too slow or the arrival too far off to estimate.
    static func estimatedArrival(remainingSteps: Int, stepsPerSecond: Double, now: Date = Date()) -> Date? {
        guard remainingSteps > 0, stepsPerSecond >= minimumProjectedPace else { return nil }
        let secondsLeft = Double(remainingSteps) / stepsPerSecond
        guard secondsLeft <= maximumProjection else { return nil }
        return now.addingTimeInterval(secondsLeft)
    }

    /// The content state for `ram`.
    ///
    /// - Parameters:
    ///   - stepsWalked: Overrides `ram.stepsWalked` — the background path
    ///     shows a caught-up count without committing it to the flock.
    ///   - isMoving: Whether the person is walking right now; `nil` for a
    ///     ram that isn't walking.
    ///   - stepsPerSecond: Recent pace, for the cadence and the estimate.
    static func make(
        ram: Ram,
        stepsWalked: Int? = nil,
        isMoving: Bool?,
        stepsPerSecond: Double,
        stride: Int,
        walkingSince: Date?,
        weatherSymbol: String?,
        now: Date = Date()
    ) -> Self {
        let total = ram.totalStepsRequired
        let walked = min(total, max(0, stepsWalked ?? ram.stepsWalked))
        let remaining = max(0, total - walked)
        let progress = total > 0 ? min(1.0, Double(walked) / Double(total)) : 0
        let distance = remaining >= 1000
            ? String(format: "%.1f km", Double(remaining) / 1000)
            : "\(remaining) m"

        var stepsPerMinute: Int?
        var barStart: Date?
        var barEnd: Date?
        if ram.status == .walking, isMoving == true, stepsPerSecond > 0 {
            stepsPerMinute = Int((stepsPerSecond * 60).rounded())
            if total > 0, let eta = estimatedArrival(remainingSteps: remaining, stepsPerSecond: stepsPerSecond, now: now) {
                // A virtual walk that started at zero steps at this pace and
                // ends at the ETA, so the system bar sits at the real
                // progress right now and slides on from there.
                barEnd = eta
                barStart = eta.addingTimeInterval(-Double(total) / stepsPerSecond)
            }
        }

        return Self(
            progress: progress,
            remainingSteps: remaining,
            remainingDistance: distance,
            statusSymbol: ram.status.symbolName,
            statusLabel: ram.status.displayName,
            weatherSymbol: weatherSymbol,
            stride: stride,
            walkingSince: walkingSince,
            isMoving: isMoving,
            totalSteps: total,
            stepsPerMinute: stepsPerMinute,
            barStart: barStart,
            barEnd: barEnd,
            updatedAt: now
        )
    }

    /// The `staleDate` for a card pushed while the app is in the background.
    func backgroundStaleDate(now: Date = Date()) -> Date {
        now.addingTimeInterval(barEnd != nil ? Self.backgroundProjectionWindow : Self.backgroundIdleWindow)
    }
}
