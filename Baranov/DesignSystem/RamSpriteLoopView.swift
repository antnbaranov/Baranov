//
//  RamSpriteLoopView.swift
//  Baranov
//
//  A small, generic frame-by-frame sprite player: given a list of asset
//  names, steps through them on a timer. This is the same "advance
//  currentFrame on a Task-driven timer" approach
//  `WaxSealBreakView` (in DesignSystem/WaxSeal.swift) already uses
//  for the wax-seal break effect, pulled out here so every sprite
//  sequence in the project — the pasture's walk-cycle portrait, the map
//  marker's gallop, the shake-to-handoff overlay — can share one driver
//  instead of each re-implementing its own frame timer.
//
//  Native SwiftUI only: a `.task` stepping plain `Image` frames, no
//  third-party animation runtime.
//

import SwiftUI

struct RamSpriteLoopView: View {
    let frameNames: [String]
    var frameDuration: Duration = .milliseconds(70)
    var loops: Bool = true
    /// Called once, after the final frame, for a non-looping sequence.
    /// Never called for a looping one.
    var onFinishedOnce: (() -> Void)?

    @State private var currentFrame = 0

    var body: some View {
        Group {
            if frameNames.indices.contains(currentFrame) {
                Image(frameNames[currentFrame])
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .task(id: frameNames) {
            currentFrame = 0
            guard !frameNames.isEmpty else { return }

            if loops {
                while !Task.isCancelled {
                    try? await Task.sleep(for: frameDuration)
                    guard !Task.isCancelled else { return }
                    currentFrame = (currentFrame + 1) % frameNames.count
                }
            } else {
                for frame in frameNames.indices {
                    currentFrame = frame
                    try? await Task.sleep(for: frameDuration)
                    if Task.isCancelled { return }
                }
                onFinishedOnce?()
            }
        }
    }
}

#Preview("Walk cycle") {
    RamSpriteLoopView(frameNames: RamSpriteFrameSets.walkCycle, frameDuration: .milliseconds(70))
        .frame(width: 120, height: 120)
        .padding()
}

#Preview("Gallop, one-shot") {
    RamSpriteLoopView(
        frameNames: RamSpriteFrameSets.gallopWithEnvelope,
        frameDuration: .milliseconds(70),
        loops: false
    )
    .frame(width: 160, height: 160)
    .padding()
}
