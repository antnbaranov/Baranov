//
//  RamBoneID.swift
//  Baranov
//
//  Identifies every bone in the ram mascot's 2D skeletal rig used to render
//  the map "navigation marker" (see RamMarkerView). This replaces the
//  originally-proposed Rive/.riv asset pipeline: Baranov's project rules
//  explicitly forbid third-party UI/animation runtimes (Lottie is named
//  directly; Rive is the same category of dependency), so the entire rig —
//  skeleton, keyframed poses, interpolation, and rendering — is hand-built
//  on native SwiftUI + Foundation with zero external dependencies.
//
//  NOTE ON PLACEHOLDER ART: no source pose images (ram_run_*.png,
//  image_39/40/41.png) exist in the repo yet. This rig renders the ram as
//  low-poly vector primitives (capsules/circles drawn with Canvas) rather
//  than textured bitmaps, so it is fully functional today. Swapping in real
//  textured art later does not require touching the skeleton, animation, or
//  interpolation layers — only `RamMarkerView`'s draw step needs to change
//  from vector primitives to `Image` layers keyed by `RamBoneID`, using the
//  exact same `RamBoneSegment` transforms this file's geometry produces.
//

import Foundation

/// A single named bone in the ram's skeletal hierarchy.
///
/// Layout mirrors a real quadruped rig: a 3-segment spine for torso motion,
/// an integrated neck/head for look-at/facing, four two-segment limbs, and a
/// dedicated attachment bone for the envelope the ram carries in its mouth.
public enum RamBoneID: String, CaseIterable, Hashable, Sendable, Codable {
    case root
    case pelvis
    case spine1
    case spine2
    case spine3
    case neck
    case head
    case envelope
    case hindLeftUpper
    case hindLeftLower
    case hindRightUpper
    case hindRightLower
    case foreLeftUpper
    case foreLeftLower
    case foreRightUpper
    case foreRightLower

    /// Traversal order in which every bone's parent is guaranteed to appear
    /// earlier in the list. `RamSkeleton.segments(for:)` walks bones in this
    /// order so each child can look up its already-computed parent transform
    /// in a single forward pass (no recursion needed).
    static let hierarchyOrder: [RamBoneID] = [
        .root, .pelvis, .spine1, .spine2, .spine3, .neck, .head, .envelope,
        .hindLeftUpper, .hindLeftLower, .hindRightUpper, .hindRightLower,
        .foreLeftUpper, .foreLeftLower, .foreRightUpper, .foreRightLower,
    ]
}
