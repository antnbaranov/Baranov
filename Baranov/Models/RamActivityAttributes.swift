//
//  RamActivityAttributes.swift
//  Baranov
//
import ActivityKit
import Foundation

struct RamActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var progress: Double
        var remainingSteps: Int
        var remainingDistance: String
        var statusSymbol: String
        var statusLabel: String
        /// The sky where the ram is right now, from WeatherKit — an SF Symbol
        /// name, or `nil` when no reading is available yet (offline, no
        /// coordinate, or the free monthly WeatherKit budget is spent).
        /// Never blocks or delays the activity: always safe to omit.
        var weatherSymbol: String? = nil
        /// Gait frame counter. The app bumps it on every update while the ram
        /// is walking, so the sprite takes a step per update. Optional so a
        /// Live Activity started by an older build still decodes.
        var stride: Int? = nil
        /// When the current walk began, for the self-ticking clock. Optional
        /// for the same reason as `stride`.
        var walkingSince: Date? = nil
        /// `false` once the person has stopped for a few seconds, so the ram
        /// stands still and the card says "Paused" instead of pretending to
        /// walk. `nil` (older builds) is treated as moving.
        var isMoving: Bool? = nil
        /// Steps the whole leg needs, so the card can show "walked" as well
        /// as "to go".
        var totalSteps: Int? = nil
        /// Recent cadence, steps per minute.
        var stepsPerMinute: Int? = nil
        /// A virtual start/end pair at the current pace. The system animates
        /// `ProgressView(timerInterval:)` and `Text(timerInterval:)` on its own,
        /// so the bar and the ETA keep moving with the phone locked and the
        /// app suspended. `barEnd` is the estimated arrival. Only set while
        /// the person is actually walking; the card's `staleDate` caps how
        /// long the projection is trusted.
        var barStart: Date? = nil
        var barEnd: Date? = nil
        /// When the step numbers in this state were last real. The app does
        /// not run in the background, so once the card goes stale the widget
        /// stops projecting and says "Updated 12 min ago" instead of guessing.
        var updatedAt: Date? = nil
    }
    var ramName: String
    var fromCity: String
    var toCity: String
}
