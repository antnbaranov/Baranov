//
//  CourierDockParts.swift
//  Baranov
//
//  The two small pieces of the courier dock that live on the main map
//  screen: the tactile "break the seal" button shown once a ram is at the
//  gate, and the idle courier card shown while no letter is out, so the
//  courier is always on the main screen and never only inside Pasture.
//
//  System materials and semantic styles only — no gradients, no glow.
//

import SwiftUI
import UIKit

struct BreakSealButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            action()
        } label: {
            Image(systemName: "seal.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
        }
        .glassIconButton()
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Break the Seal and Read")
    }
}

struct IdleCourierCard: View {
    let name: String

    var body: some View {
        HStack(spacing: 12) {
            RamPortraitView(name: name, diameter: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("Ready for a letter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text("Free")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.thinMaterial, in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
