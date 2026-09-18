//
//  RamAnimationClip.swift
//  Baranov
//
//  A tiny, dependency-free keyframe/interpolation engine purpose-built for
//  the ram rig. Rather than fighting SwiftUI's `KeyframeTrack` result-builder
//  DSL across sixteen bones (extremely verbose, and awkward for mirroring
//  left/right limbs), each animatable property is a plain array of
//  (time, value) keyframes sampled with a Catmull-Rom spline.
//
//  This directly satisfies the original brief's animation requirements:
//   - "smooth, vectorized interpolation between key poses" -> Catmull-Rom
//     blends through every authored keyframe rather than snapping to it.
//   - "do not just cycle poses sequentially" -> the spline factors in the
//     neighboring keyframes on both sides, so motion eases rather than
//     moves at constant velocity between two poses.
//   - "variable velocity ... slow prying shift or a rapid powerful rear" ->
//     achieved purely by how closely keyframes are spaced in time. Tightly
//     spaced keyframes = fast local motion; widely spaced = slow motion.
//     See RamClipLibrary for the authored spacing.
//
//  Everything is `Sendable` value types so a clip can be looked up from a
//  static library and safely read from any actor.
//

import Foundation

/// One authored (time, value) sample on a single animatable property.
public struct RamKeyframe: Sendable, Equatable {
    public let time: Double
    public let value: Double

    public init(_ time: Double, _ value: Double) {
        self.time = time
        self.value = value
    }
}

/// A sorted sequence of keyframes for one animatable property (e.g. one
/// bone's angle, or the root's vertical bounce), sampled with a Catmull-Rom
/// spline for smooth easing between keyframes instead of linear snapping.
public struct RamBoneTrack: Sendable {
    public let keyframes: [RamKeyframe]
    public let loops: Bool

    public init(keyframes: [RamKeyframe], loops: Bool) {
        precondition(!keyframes.isEmpty, "RamBoneTrack requires at least one keyframe")
        self.keyframes = keyframes
        self.loops = loops
    }

    /// A track that holds a single constant value for the whole clip.
    public static func constant(_ value: Double, loops: Bool = true) -> RamBoneTrack {
        RamBoneTrack(keyframes: [RamKeyframe(0, value)], loops: loops)
    }

    /// Samples the track at `time` (seconds into the clip), wrapping around
    /// `duration` for looping tracks (including the implicit final segment
    /// that connects the last keyframe back to the first) or clamping to
    /// the ends for one-shots.
    public func value(at time: Double, duration: Double) -> Double {
        let count = keyframes.count
        guard count > 1 else { return keyframes[0].value }

        let t: Double
        if loops {
            let m = time.truncatingRemainder(dividingBy: duration)
            t = m < 0 ? m + duration : m
        } else {
            t = min(max(time, 0), duration)
        }

        // Resolves an arbitrary (possibly out-of-range) index to a (time,
        // value) pair. Looping tracks treat the keyframe array as circular,
        // unwrapping each extra lap onto the timeline by adding
        // `cycles * duration` to that keyframe's authored time — this is
        // what makes the segment from the last keyframe back to the first
        // interpolate correctly, and gives correct neighbors for the
        // Catmull-Rom blend right at that seam. Non-looping tracks simply
        // clamp to the first/last keyframe.
        func resolve(_ index: Int) -> (time: Double, value: Double) {
            if loops {
                let wrapped = ((index % count) + count) % count
                let cycles = Double(Int((Double(index) / Double(count)).rounded(.down)))
                return (keyframes[wrapped].time + cycles * duration, keyframes[wrapped].value)
            } else {
                let clamped = min(max(index, 0), count - 1)
                return (keyframes[clamped].time, keyframes[clamped].value)
            }
        }

        let searchUpperBound = loops ? count : count - 1
        var i = 0
        while i < searchUpperBound - 1 && resolve(i + 1).time <= t {
            i += 1
        }

        let k1 = resolve(i)
        let k2 = resolve(i + 1)
        let span = k2.time - k1.time
        let localT = span > 0 ? (t - k1.time) / span : 0
        let k0 = resolve(i - 1)
        let k3 = resolve(i + 2)
        return Self.catmullRom(k0.value, k1.value, k2.value, k3.value, localT)
    }

    private static func catmullRom(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double, _ t: Double) -> Double {
        let t2 = t * t
        let t3 = t2 * t
        return 0.5 * (
            (2 * p1)
                + (-p0 + p2) * t
                + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                + (-p0 + 3 * p1 - 3 * p2 + p3) * t3
        )
    }
}

/// A fully-resolved pose: every bone's current angle offset (from bind
/// pose), plus a few whole-rig parameters (vertical bounce, spine
/// compression, envelope bob) that don't map to a single bone.
public struct RamPose: Sendable {
    public var boneAngles: [RamBoneID: Double]
    public var rootBounce: Double
    public var spineCompression: Double
    public var envelopeBob: Double

    public static let bind = RamPose(boneAngles: [:], rootBounce: 0, spineCompression: 1, envelopeBob: 0)
}

/// A named, authored animation — a run cycle, an idle breathing loop, or the
/// one-shot rearing celebration — expressed as one `RamBoneTrack` per
/// animated bone plus the whole-rig parameter tracks.
public struct RamAnimationClip: Sendable {
    public let duration: Double
    public let loops: Bool
    public let boneTracks: [RamBoneID: RamBoneTrack]
    public let rootBounceTrack: RamBoneTrack
    public let spineCompressionTrack: RamBoneTrack
    public let envelopeBobTrack: RamBoneTrack

    public init(
        duration: Double,
        loops: Bool,
        boneTracks: [RamBoneID: RamBoneTrack],
        rootBounceTrack: RamBoneTrack = .constant(0),
        spineCompressionTrack: RamBoneTrack = .constant(1),
        envelopeBobTrack: RamBoneTrack = .constant(0)
    ) {
        self.duration = duration
        self.loops = loops
        self.boneTracks = boneTracks
        self.rootBounceTrack = rootBounceTrack
        self.spineCompressionTrack = spineCompressionTrack
        self.envelopeBobTrack = envelopeBobTrack
    }

    /// Samples every track at `time` (seconds into the clip) and returns the
    /// resulting whole-rig pose.
    public func pose(at time: Double) -> RamPose {
        var angles: [RamBoneID: Double] = [:]
        angles.reserveCapacity(boneTracks.count)
        for (bone, track) in boneTracks {
            angles[bone] = track.value(at: time, duration: duration)
        }
        return RamPose(
            boneAngles: angles,
            rootBounce: rootBounceTrack.value(at: time, duration: duration),
            spineCompression: spineCompressionTrack.value(at: time, duration: duration),
            envelopeBob: envelopeBobTrack.value(at: time, duration: duration)
        )
    }
}
