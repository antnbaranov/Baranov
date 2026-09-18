//
//  RamRigAnimator.swift
//  Baranov
//
//  Maps a high-level motion state onto a sampled `RamPose` from the clip
//  library, plus a small cross-fade helper so switching states mid-stride
//  doesn't pop. Pure/stateless by design — `RamMarkerView` owns the only
//  piece of actual state (when the current motion state began) and drives
//  this each frame from a `TimelineView`.
//

import Foundation

/// The ram marker's current behavior. Speed and category are deliberately
/// separate: category picks which clip plays, `moving`'s associated speed
/// only affects playback rate, so changing speed doesn't restart the stride.
public enum RamMotionState: Hashable, Sendable {
    case idle
    /// `speed` is a 0...1 normalized step cadence (e.g. from
    /// `StepTrackerService`), 0 = nearly stopped, 1 = fastest observed pace.
    case moving(speed: Double)
    /// One-shot celebration for reaching a gate/waypoint. The caller should
    /// transition back to `.idle` once `RamRigAnimator.isArrivedClipFinished`
    /// reports true.
    case arrived

    /// Coarse category, ignoring `moving`'s speed payload — this is what
    /// should trigger a state-change reset (and cross-fade), not any change
    /// in speed while already moving.
    var category: Category {
        switch self {
        case .idle: .idle
        case .moving: .moving
        case .arrived: .arrived
        }
    }

    enum Category: Equatable, Sendable { case idle, moving, arrived }
}

public enum RamRigAnimator {
    /// A near-zero step cadence still animates, just slowly, rather than
    /// freezing the rig on a single frozen mid-stride frame.
    private static let minimumSpeedFactor = 0.15

    /// Cross-fade duration applied whenever the motion state's `category`
    /// changes, so bones ease from one clip's pose into another's instead
    /// of snapping.
    public static let stateTransitionDuration: TimeInterval = 0.25

    /// Samples the appropriate clip for `state` at `elapsedInState` seconds
    /// (time since this state was entered).
    public static func pose(for state: RamMotionState, elapsedInState: TimeInterval) -> RamPose {
        switch state {
        case .idle:
            return RamClipLibrary.idleBreath.pose(at: elapsedInState)
        case .moving(let speed):
            let clampedSpeed = max(min(speed, 1), minimumSpeedFactor)
            return RamClipLibrary.runCycle.pose(at: elapsedInState * clampedSpeed)
        case .arrived:
            return RamClipLibrary.rearingCelebration.pose(at: elapsedInState)
        }
    }

    /// Whether the one-shot `.arrived` clip has played through to its final
    /// (settled) keyframe.
    public static func isArrivedClipFinished(elapsedInState: TimeInterval) -> Bool {
        elapsedInState >= RamClipLibrary.rearingCelebration.duration
    }

    /// Linearly interpolates every component of two poses by `amount`
    /// (0 = `from`, 1 = `to`). Used only for the brief cross-fade window
    /// right after a motion-state change.
    public static func blend(_ from: RamPose, _ to: RamPose, amount: Double) -> RamPose {
        let t = min(max(amount, 0), 1)
        var angles: [RamBoneID: Double] = [:]
        angles.reserveCapacity(RamBoneID.allCases.count)
        for id in RamBoneID.allCases {
            let a = from.boneAngles[id] ?? 0
            let b = to.boneAngles[id] ?? 0
            angles[id] = a + (b - a) * t
        }
        return RamPose(
            boneAngles: angles,
            rootBounce: from.rootBounce + (to.rootBounce - from.rootBounce) * t,
            spineCompression: from.spineCompression + (to.spineCompression - from.spineCompression) * t,
            envelopeBob: from.envelopeBob + (to.envelopeBob - from.envelopeBob) * t
        )
    }
}
