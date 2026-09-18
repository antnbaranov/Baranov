//
//  RamClipLibrary.swift
//  Baranov
//
//  The three authored animations the mascot marker uses, expressed as
//  `RamAnimationClip`s (see RamAnimationClip.swift for the interpolation
//  engine). All angle values are placeholders tuned by eye against the
//  vector primitives `RamMarkerView` draws today — retune freely once real
//  reference art exists; nothing else in the rig needs to change.
//
//  - `.runCycle`: the 8-pose locomotion loop from the original brief,
//    driving the ram's stride (fore/hind limb swing, torso pitch, a double
//    vertical bounce per stride, and a subtle rib-cage compression/extension
//    on contact vs. suspension).
//  - `.idleBreath`: the "Idle 2/Shift" pose with slow, unevenly-spaced
//    keyframes — a long, "prying" weight shift rather than a metronomic
//    loop.
//  - `.rearingCelebration`: a one-shot, non-looping clip — rapid rise to a
//    held high point, then a smooth lower back toward idle — for when a ram
//    reaches its destination.
//

import Foundation

public enum RamClipLibrary {
    // MARK: - Run cycle (8-pose gait loop)

    public static let runCycle: RamAnimationClip = {
        let duration = 0.8
        let step = duration / 8

        func track(_ values: [Double]) -> RamBoneTrack {
            RamBoneTrack(
                keyframes: values.enumerated().map { RamKeyframe(Double($0.offset) * step, $0.element) },
                loops: true
            )
        }

        let hindLeftUpper = track([-25, -10, 10, 35, 55, 40, 10, -15])
        let hindLeftLower = track([40, 20, 0, -10, 10, 45, 60, 55])
        let foreLeftUpper = track([30, 45, 55, 35, 5, -20, -35, -10])
        let foreLeftLower = track([10, -5, -15, 5, 30, 50, 45, 25])

        return RamAnimationClip(
            duration: duration,
            loops: true,
            boneTracks: [
                .spine1: track([0, 2, 4, 2, 0, -2, -4, -2]),
                .spine2: track([0, 1, 2, 1, 0, -1, -2, -1]),
                .spine3: track([0, 1, 1, 0, 0, -1, -1, 0]),
                .neck: track([0, -2, -3, -2, 0, 2, 3, 2]),
                .head: track([0, -1, -2, -1, 0, 1, 2, 1]),
                .hindLeftUpper: hindLeftUpper,
                .hindLeftLower: hindLeftLower,
                .foreLeftUpper: foreLeftUpper,
                .foreLeftLower: foreLeftLower,
                // Diagonal gait: the opposite pair is the same motion, half
                // a stride out of phase.
                .hindRightUpper: shifted(hindLeftUpper, by: duration / 2, duration: duration),
                .hindRightLower: shifted(hindLeftLower, by: duration / 2, duration: duration),
                .foreRightUpper: shifted(foreLeftUpper, by: duration / 2, duration: duration),
                .foreRightLower: shifted(foreLeftLower, by: duration / 2, duration: duration),
            ],
            rootBounceTrack: track([0, 3, 5, 3, 0, 3, 5, 3]),
            spineCompressionTrack: track([1.0, 0.97, 0.94, 0.97, 1.0, 1.03, 1.06, 1.03]),
            envelopeBobTrack: track([0, 0.3, 0.5, 0.3, 0, -0.3, -0.5, -0.3])
        )
    }()

    // MARK: - Idle / breathing shift

    public static let idleBreath = RamAnimationClip(
        duration: 2.4,
        loops: true,
        boneTracks: [
            .hindLeftUpper: RamBoneTrack(keyframes: [RamKeyframe(0, 0), RamKeyframe(1.2, 2), RamKeyframe(1.6, -1), RamKeyframe(2.4, 0)], loops: true),
            .foreRightUpper: RamBoneTrack(keyframes: [RamKeyframe(0, 0), RamKeyframe(1.2, -1.5), RamKeyframe(1.6, 1), RamKeyframe(2.4, 0)], loops: true),
            .head: RamBoneTrack(keyframes: [RamKeyframe(0, 0), RamKeyframe(1.2, 1.5), RamKeyframe(1.6, 0.5), RamKeyframe(2.4, 0)], loops: true),
        ],
        rootBounceTrack: RamBoneTrack(keyframes: [RamKeyframe(0, 0), RamKeyframe(1.2, 0.6), RamKeyframe(1.6, 0.3), RamKeyframe(2.4, 0)], loops: true),
        spineCompressionTrack: RamBoneTrack(keyframes: [RamKeyframe(0, 1.0), RamKeyframe(1.2, 1.02), RamKeyframe(1.6, 0.995), RamKeyframe(2.4, 1.0)], loops: true)
    )

    // MARK: - Rearing celebration (one-shot: rapid rise, hold, smooth lower)

    public static let rearingCelebration: RamAnimationClip = {
        let foreUpper = RamBoneTrack(keyframes: [RamKeyframe(0, 0), RamKeyframe(0.18, -40), RamKeyframe(0.4, -75), RamKeyframe(1.1, -75), RamKeyframe(1.6, -5)], loops: false)
        let foreLower = RamBoneTrack(keyframes: [RamKeyframe(0, 0), RamKeyframe(0.18, 20), RamKeyframe(0.4, 35), RamKeyframe(1.1, 35), RamKeyframe(1.6, 5)], loops: false)
        let hindUpper = RamBoneTrack(keyframes: [RamKeyframe(0, 0), RamKeyframe(0.18, 15), RamKeyframe(0.4, 20), RamKeyframe(1.1, 20), RamKeyframe(1.6, 0)], loops: false)
        let hindLower = RamBoneTrack(keyframes: [RamKeyframe(0, 0), RamKeyframe(0.18, -10), RamKeyframe(0.4, -15), RamKeyframe(1.1, -15), RamKeyframe(1.6, 0)], loops: false)

        return RamAnimationClip(
            duration: 1.6,
            loops: false,
            boneTracks: [
                .spine1: RamBoneTrack(keyframes: [RamKeyframe(0, 0), RamKeyframe(0.18, -15), RamKeyframe(0.4, -25), RamKeyframe(1.1, -25), RamKeyframe(1.6, -3)], loops: false),
                .spine2: RamBoneTrack(keyframes: [RamKeyframe(0, 0), RamKeyframe(0.18, -10), RamKeyframe(0.4, -18), RamKeyframe(1.1, -18), RamKeyframe(1.6, -2)], loops: false),
                .spine3: RamBoneTrack(keyframes: [RamKeyframe(0, 0), RamKeyframe(0.18, -5), RamKeyframe(0.4, -10), RamKeyframe(1.1, -10), RamKeyframe(1.6, 0)], loops: false),
                .neck: RamBoneTrack(keyframes: [RamKeyframe(0, 0), RamKeyframe(0.18, 10), RamKeyframe(0.4, 18), RamKeyframe(1.1, 18), RamKeyframe(1.6, 2)], loops: false),
                .head: RamBoneTrack(keyframes: [RamKeyframe(0, 0), RamKeyframe(0.18, 8), RamKeyframe(0.4, 14), RamKeyframe(1.1, 14), RamKeyframe(1.6, 0)], loops: false),
                .foreLeftUpper: foreUpper,
                .foreLeftLower: foreLower,
                .foreRightUpper: foreUpper,
                .foreRightLower: foreLower,
                .hindLeftUpper: hindUpper,
                .hindLeftLower: hindLower,
                .hindRightUpper: hindUpper,
                .hindRightLower: hindLower,
            ],
            rootBounceTrack: RamBoneTrack(keyframes: [RamKeyframe(0, 0), RamKeyframe(0.18, 4), RamKeyframe(0.4, 9), RamKeyframe(1.1, 9), RamKeyframe(1.6, 0)], loops: false),
            spineCompressionTrack: RamBoneTrack(keyframes: [RamKeyframe(0, 1.0), RamKeyframe(0.18, 1.05), RamKeyframe(0.4, 1.1), RamKeyframe(1.1, 1.1), RamKeyframe(1.6, 1.0)], loops: false),
            envelopeBobTrack: RamBoneTrack(keyframes: [RamKeyframe(0, 0), RamKeyframe(0.4, 1.5), RamKeyframe(1.1, 1.5), RamKeyframe(1.6, 0)], loops: false)
        )
    }()

    /// Returns a copy of `track` with every keyframe's time shifted forward
    /// by `shift` seconds, wrapping around `duration`. Used to derive a
    /// mirrored limb's motion from its counterpart without re-authoring
    /// identical keyframe data by hand.
    private static func shifted(_ track: RamBoneTrack, by shift: Double, duration: Double) -> RamBoneTrack {
        let shiftedKeyframes = track.keyframes
            .map { RamKeyframe(($0.time + shift).truncatingRemainder(dividingBy: duration), $0.value) }
            .sorted { $0.time < $1.time }
        return RamBoneTrack(keyframes: shiftedKeyframes, loops: track.loops)
    }
}
