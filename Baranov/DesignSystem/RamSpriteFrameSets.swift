//
//  RamSpriteFrameSets.swift
//  Baranov
//
//  Names the frame sequences dropped into Assets.xcassets so every call
//  site that wants to play one just references these arrays instead of
//  re-typing/re-counting asset names by hand. Two sets exist today:
//
//  - `walkCycle` ("ram_goes0"..."ram_goes15", skipping the missing
//    "ram_goes1" and "ram_goes11" — neither imageset actually exists in
//    Assets.xcassets, so leaving them in would silently render a blank
//    frame mid-stride): a plain walking gait, no envelope — used for the
//    small, always-alive portrait in the Pasture's ram selector, and for
//    the big selector card's own walk-in/walk-out.
//  - `faceCameraFrame` ("ram_goes16"): the one frame the big selector
//    card settles on once a ram has walked in and turned to face the
//    person — not part of the walking gait itself.
//  - `gallopWithEnvelope` ("Object-2"..."Object-16"): a galloping stride
//    that finishes in a leap, the envelope gripped in its mouth and dust
//    kicked up behind — used for the live map marker and the
//    shake-to-handoff overlay. `gallopRunningStride`/`gallopLeapFinish`
//    slice it into a steady-running loop and a one-shot leaping finish.
//
//  `assetExists` is what lets every consumer stay safe on a checkout that
//  doesn't have this art yet — same "check for the named asset, fall back
//  to something else if it's missing" idiom `RamPortraitView` and
//  `WaxSealBreakView` (DesignSystem/WaxSeal.swift) already use elsewhere.
//

import UIKit

enum RamSpriteFrameSets {
    static let walkCycle: [String] = (0...15).filter { $0 != 1 && $0 != 11 }.map { "ram_goes\($0)" }

    /// The big selector card's "turned around, looking at us" settle
    /// pose — played once, right after `walkCycle` finishes walking a ram
    /// in, and held there until the next swap.
    static let faceCameraFrame = "ram_goes16"

    static let gallopWithEnvelope: [String] = (2...16).map { "Object-\($0)" }

    /// A steady running read of `gallopWithEnvelope` — the loop used while
    /// a ram is actively `.moving`. Object-2…Object-8 is one clean stride
    /// cycle; Object-9 already begins the gather into the leap, so looping
    /// it back to Object-2 produced a visible hitch every cycle.
    static let gallopRunningStride: [String] = (2...8).map { "Object-\($0)" }

    /// The leaping tail of `gallopWithEnvelope` — played once, not looped,
    /// when a ram reaches `.arrived`.
    static let gallopLeapFinish: [String] = (10...16).map { "Object-\($0)" }

    /// Just the two frames used to hold `.idle` — a small, slow sway
    /// between a settled stance and a rearing-up hint, rather than
    /// cycling the whole `gallopLeapFinish` range while just standing.
    static let idleHold: [String] = ["Object-11", "Object-12"]

    /// A short "look, I'm carrying it!" flourish — the tail end of
    /// `gallopLeapFinish`, rearing all the way up onto its hind legs
    /// with the envelope still gripped in its mouth. Played occasionally
    /// while a letter-carrying ram is the one settled in the Pasture's
    /// big selector card (not just once, on actual arrival, the way
    /// `gallopLeapFinish` is elsewhere) — every frame in this slice
    /// still shows the envelope, so it's only ever used for a ram that
    /// actually has a letter to show off.
    static let rearUpWithEnvelope: [String] = (13...16).map { "Object-\($0)" }

    static func assetExists(_ name: String) -> Bool {
        UIImage(named: name) != nil
    }
}
