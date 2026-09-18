//
//  HoofbeatOverlay.swift
//  Baranov
//
//  The only UI the shake handoff has: a small capsule that drops from the
//  top while `HoofbeatRelay` is doing its work, and slides away on its own
//  once the exchange settles. Deliberately unobtrusive — the gesture is
//  the interaction, this is just the receipt.
//
//  While the satchel is actually changing hands (`.exchanging`), the icon
//  is a small loop of the same galloping-with-envelope sprite the map
//  marker uses (`RamSpriteFrameSets.gallopWithEnvelope`) rather than a
//  generic radio-waves glyph — falls back to that glyph automatically if
//  the sprite art isn't present, same as everywhere else this art is used.
//
//  Native materials and semantic styles only, per the project's HIG rules.
//

import SwiftUI

struct HoofbeatOverlay: View {
    let phase: HoofbeatPhase
    let successTick: Int

    private var hasSpriteArt: Bool {
        guard let first = RamSpriteFrameSets.gallopWithEnvelope.first else { return false }
        return RamSpriteFrameSets.assetExists(first)
    }

    var body: some View {
        Group {
            if phase.isActive {
                HStack(spacing: 10) {
                    icon
                        .frame(width: 22, height: 22)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule(style: .continuous))
                .padding(.horizontal, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: phase)
        .sensoryFeedback(.success, trigger: successTick)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var icon: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .searching:
            ProgressView()
                .controlSize(.small)
        case .connecting:
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.headline)
                .foregroundStyle(.secondary)
                .symbolEffect(.variableColor.iterative)
        case .exchanging:
            if hasSpriteArt {
                RamSpriteLoopView(frameNames: RamSpriteFrameSets.gallopRunningStride, frameDuration: .milliseconds(60))
            } else {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .symbolEffect(.variableColor.iterative)
            }
        case .finished:
            Image(systemName: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var message: String {
        switch phase {
        case .idle:
            return ""
        case .searching:
            return "Listening for hoofbeats nearby…"
        case .connecting(let peerName):
            return "Meeting \(peerName)…"
        case .exchanging(let peerName):
            return "Passing the satchel to \(peerName)…"
        case .finished(let summary):
            return summary
        case .failed(let reason):
            return reason
        }
    }
}

#Preview("Searching") {
    HoofbeatOverlay(phase: .searching, successTick: 0)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
}

#Preview("Exchanging") {
    HoofbeatOverlay(phase: .exchanging(peerName: "Anton"), successTick: 0)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
}

#Preview("Finished") {
    HoofbeatOverlay(phase: .finished(summary: "Klaus went with Anton."), successTick: 1)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
}
