//
//  RamPortraitView.swift
//  Baranov
//
//  A ram's picture in the selector slider. Resolves in four steps and
//  never requires a code change once new art shows up:
//
//  1. A portrait named exactly "Ram-<name>" (e.g. "Ram-Klaus") — for
//     giving one specific ram its own likeness.
//  2. The "ram_goes0"..."ram_goes15" walk-cycle sprite set, looped — the
//     generic, always-alive portrait for every ram that doesn't have its
//     own named art.
//  3. A shared static "RamPortraitPlaceholder" asset, if the walk-cycle
//     frames aren't present either.
//  4. An SF Symbol fallback — what renders when none of the above exist.
//
//  Drop any of these assets into Assets.xcassets later; nothing else
//  changes.
//

import SwiftUI
import UIKit

struct RamPortraitView: View {
    /// The name used to look up bespoke "Ram-<name>" art — not itself a
    /// `Ram`, so this same view can portray the person's `RamCompanion`
    /// too, before it's ever actually carried a letter as a real `Ram`.
    let name: String
    var diameter: CGFloat = 56

    /// The wool color the person gave this ram (white until they do).
    private var walkFrames: [String] {
        RamSpriteFrameSets.walkFrames(for: RamColorStore.shared.color(for: name))
    }

    private var hasWalkCycleArt: Bool {
        guard let first = walkFrames.first else { return false }
        return RamSpriteFrameSets.assetExists(first)
    }

    var body: some View {
        Group {
            if UIImage(named: "Ram-\(name)") != nil {
                Image("Ram-\(name)")
                    .resizable()
                    .scaledToFill()
            } else if hasWalkCycleArt {
                RamSpriteLoopView(frameNames: walkFrames, frameDuration: .milliseconds(70))
                    .padding(diameter * 0.06)
            } else if UIImage(named: "RamPortraitPlaceholder") != nil {
                Image("RamPortraitPlaceholder")
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "pawprint.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(diameter * 0.18)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: diameter, height: diameter)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: diameter * 0.22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: diameter * 0.22, style: .continuous))
    }
}

#Preview {
    RamPortraitView(name: FlockViewModel.preview.activeRams[0].name)
        .padding()
}
