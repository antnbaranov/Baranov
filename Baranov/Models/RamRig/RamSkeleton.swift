//
//  RamSkeleton.swift
//  Baranov
//
//  The ram's bind pose (rest skeleton) plus the forward-kinematics that turns
//  a `RamPose` (per-bone angle offsets from an animation clip) into concrete
//  2D line segments a view can draw. Everything here is authored in "facing
//  right" local space — angle 0 points along +x — so the same pose data
//  produces a correctly-deforming rig no matter which way the marker is
//  ultimately rotated to face on screen (see `DirectionalLock` in
//  RamMarkerView.swift).
//
//  Placeholder note: rest angles/lengths below are a first-pass approximation
//  of a standing quadruped, tuned by eye against the vector placeholder
//  shapes in RamMarkerView. When real reference art lands, only these
//  numbers need retuning — the hierarchy and FK math do not change.
//

import CoreGraphics
import Foundation

/// A bone's fixed (un-animated) relationship to its parent: how far it
/// extends, at what angle relative to the parent bone, and how thick to draw
/// it. Angles are degrees, local to the parent's own direction.
public struct RamBoneRest: Sendable {
    public let parent: RamBoneID?
    public let restAngle: Double
    public let length: CGFloat
    public let thickness: CGFloat
}

/// A world-space (marker-local) line segment ready to draw: where a bone
/// starts, where it ends, and how thick it is.
public struct RamBoneSegment: Sendable, Identifiable {
    public let id: RamBoneID
    public let start: CGPoint
    public let end: CGPoint
    public let thickness: CGFloat
}

public enum RamSkeleton {
    /// The bind pose: every bone's rest length/angle/thickness relative to
    /// its parent. `.root` is the only bone with no parent and zero extent —
    /// it exists purely as the origin the pelvis hangs off of.
    public static let bindPose: [RamBoneID: RamBoneRest] = [
        .root: RamBoneRest(parent: nil, restAngle: 0, length: 0, thickness: 0),

        // Torso: three spine segments running roughly horizontal (facing +x),
        // each tilting very slightly to give the back a natural curve.
        .pelvis: RamBoneRest(parent: .root, restAngle: 0, length: 9, thickness: 11),
        .spine1: RamBoneRest(parent: .pelvis, restAngle: -6, length: 8, thickness: 10),
        .spine2: RamBoneRest(parent: .spine1, restAngle: -3, length: 7, thickness: 9),
        .spine3: RamBoneRest(parent: .spine2, restAngle: 2, length: 6, thickness: 8),

        // Neck/head, integrated so a future look-at behavior can just add a
        // small extra offset onto `.head`'s angle without touching the spine.
        .neck: RamBoneRest(parent: .spine3, restAngle: 22, length: 6, thickness: 6),
        .head: RamBoneRest(parent: .neck, restAngle: 15, length: 6, thickness: 7),

        // The envelope hangs from the head like it's gripped in the mouth.
        .envelope: RamBoneRest(parent: .head, restAngle: -40, length: 4.5, thickness: 3),

        // Hind limbs attach at the pelvis.
        .hindLeftUpper: RamBoneRest(parent: .pelvis, restAngle: 105, length: 8, thickness: 5),
        .hindLeftLower: RamBoneRest(parent: .hindLeftUpper, restAngle: -18, length: 8.5, thickness: 4),
        .hindRightUpper: RamBoneRest(parent: .pelvis, restAngle: 105, length: 8, thickness: 5),
        .hindRightLower: RamBoneRest(parent: .hindRightUpper, restAngle: -18, length: 8.5, thickness: 4),

        // Forelimbs attach at the shoulder (spine1).
        .foreLeftUpper: RamBoneRest(parent: .spine1, restAngle: 92, length: 7.5, thickness: 5),
        .foreLeftLower: RamBoneRest(parent: .foreLeftUpper, restAngle: -12, length: 8, thickness: 4),
        .foreRightUpper: RamBoneRest(parent: .spine1, restAngle: 92, length: 7.5, thickness: 5),
        .foreRightLower: RamBoneRest(parent: .foreRightUpper, restAngle: -12, length: 8, thickness: 4),
    ]

    /// Draw order (back-to-front) so the far-side legs render behind the
    /// body and the near-side legs, head, and envelope render in front.
    /// This is a cheap stand-in for real depth sorting — good enough for a
    /// small map marker with flat vector shading.
    public static let drawOrder: [RamBoneID] = [
        .hindRightUpper, .hindRightLower, .foreRightUpper, .foreRightLower,
        .pelvis, .spine1, .spine2, .spine3,
        .hindLeftUpper, .hindLeftLower, .foreLeftUpper, .foreLeftLower,
        .neck, .head, .envelope,
    ]

    /// Runs forward kinematics: combines the bind pose with an animated
    /// `RamPose` (from `RamAnimationClip.pose(at:)`) to produce concrete
    /// segments in marker-local space, with `rootPosition` as the origin.
    ///
    /// - Parameters:
    ///   - pose: animated per-bone angle offsets plus root bounce, spine
    ///     compression, and envelope bob.
    ///   - rootPosition: where the pelvis root sits in the destination view.
    ///   - scale: uniform scale applied to every bone length (and thickness).
    public static func segments(
        for pose: RamPose,
        rootPosition: CGPoint = .zero,
        scale: CGFloat = 1
    ) -> [RamBoneSegment] {
        var worldAngle: [RamBoneID: Double] = [.root: 0]
        var worldEnd: [RamBoneID: CGPoint] = [.root: CGPoint(x: rootPosition.x, y: rootPosition.y - CGFloat(pose.rootBounce) * scale)]
        var segments: [RamBoneSegment] = []
        segments.reserveCapacity(RamBoneID.allCases.count - 1)

        for id in RamBoneID.hierarchyOrder where id != .root {
            guard let rest = bindPose[id] else { continue }
            let parentID = rest.parent ?? .root
            let parentAngle = worldAngle[parentID] ?? 0
            let parentEnd = worldEnd[parentID] ?? rootPosition
            let angle = parentAngle + rest.restAngle + (pose.boneAngles[id] ?? 0)

            let isSpine = (id == .spine1 || id == .spine2 || id == .spine3)
            let compression = isSpine ? CGFloat(pose.spineCompression) : 1
            let length = rest.length * scale * compression
            let radians = angle * .pi / 180
            var end = CGPoint(
                x: parentEnd.x + CGFloat(cos(radians)) * length,
                y: parentEnd.y + CGFloat(sin(radians)) * length
            )
            if id == .envelope {
                end.y -= CGFloat(pose.envelopeBob) * scale
            }

            worldAngle[id] = angle
            worldEnd[id] = end
            segments.append(RamBoneSegment(id: id, start: parentEnd, end: end, thickness: rest.thickness * scale))
        }

        let order = drawOrder
        return segments.sorted { lhs, rhs in
            (order.firstIndex(of: lhs.id) ?? 0) < (order.firstIndex(of: rhs.id) ?? 0)
        }
    }
}
