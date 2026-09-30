//
//  JourneyCertificateView.swift
//  Baranov
//
//  A paid alternative to the free doodle attachment — not something you
//  draw, but something the journey itself already made. Every field on
//  this card comes straight from the ram's real passport stamps (place,
//  who carried it, when) and the letter it delivered; nothing here is
//  invented for the occasion, the same honesty rule the paywall and the
//  flock-pulse stat already follow elsewhere in the app.
//
//  Rendered with `ImageRenderer` straight from this SwiftUI view (no
//  ARKit, no camera, no new permission, no third-party rendering) into a
//  plain image the recipient can share however they like — Messages,
//  photos, wherever. Native System Materials only, per the design
//  system: no gradient borders, no glow, no glass effects beyond the
//  standard materials.
//
//  Gated behind `EntitlementService.hasPastureExpansion` — the same
//  entitlement that already unlocks every wax colour — rather than a new
//  product, so this ships without adding another thing to configure in
//  RevenueCat before a deadline.
//

import SwiftUI
import UIKit

/// The certificate card itself, sized for sharing (fixed width, grows
/// vertically) rather than for on-screen navigation.
struct JourneyCertificateView: View {
    let ram: Ram
    let letter: Letter

    private var orderedStamps: [JourneyStamp] {
        ram.stamps.sorted { $0.stepsAtStamp < $1.stepsAtStamp }
    }

    private var daysTraveled: Int? {
        guard let start = orderedStamps.first?.timestamp,
              let end = orderedStamps.last?.timestamp,
              end >= start
        else { return nil }
        return Calendar.current.dateComponents([.day], from: start, to: end).day
    }

    private var metersWalked: Int {
        max(ram.stepsWalked, orderedStamps.map(\.stepsAtStamp).max() ?? 0)
    }

    /// Everyone who actually carried this letter at some point, in the
    /// order they first appear — a handoff chain, not a head count.
    private var carriers: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for stamp in orderedStamps where seen.insert(stamp.carrierName).inserted {
            ordered.append(stamp.carrierName)
        }
        return ordered
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.horizontal, 20)
            stampsList
            Divider().padding(.horizontal, 20)
            footer
        }
        .frame(width: 360)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "flag.checkered.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(letter.sealColor.color.gradient)
                .symbolRenderingMode(.hierarchical)

            Text("Journey Certificate")
                .font(.title2.bold())

            Text("\(letter.senderName) \u{2192} \(letter.recipientName)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 20) {
                statBlock(value: DistanceFormatter.string(forMeters: metersWalked), label: String(localized: "Walked", bundle: .appLanguage, locale: .appLanguage))
                if let daysTraveled {
                    statBlock(value: "\(daysTraveled)", label: daysTraveled == 1 ? String(localized: "Day", bundle: .appLanguage, locale: .appLanguage) : String(localized: "Days", bundle: .appLanguage, locale: .appLanguage))
                }
                statBlock(value: "\(carriers.count)", label: carriers.count == 1 ? String(localized: "Carrier", bundle: .appLanguage, locale: .appLanguage) : String(localized: "Carriers", bundle: .appLanguage, locale: .appLanguage))
            }
            .padding(.top, 2)
        }
        .padding(22)
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stampsList: some View {
        if orderedStamps.isEmpty {
            Text("No waypoints were logged for this journey.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(20)
        } else {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(orderedStamps.prefix(6)) { stamp in
                    HStack(spacing: 10) {
                        Image(systemName: stamp.kind.symbolName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(stamp.displayPlaceName)
                            .font(.footnote.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(stamp.kind.caption)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if orderedStamps.count > 6 {
                    Text("+ \(orderedStamps.count - 6) more stops")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(18)
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Carried by \(ram.name)")
                .font(.caption.weight(.semibold))
            Text("Sealed in \(letter.sealColor.displayName.lowercased()) wax \u{00B7} Baranov")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }
}

/// Renders a `JourneyCertificateView` to a plain, shareable image.
///
/// `ImageRenderer` runs on the main actor and reads the view's real
/// SwiftUI layout, so the exported image always matches what the card
/// looked like on screen — no separate drawing code to keep in sync.
@MainActor
enum JourneyCertificateRenderer {
    static func image(ram: Ram, letter: Letter, scale: CGFloat = 3) -> UIImage? {
        let renderer = ImageRenderer(content: JourneyCertificateView(ram: ram, letter: letter))
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

#Preview {
    let ram = FlockViewModel.preview.activeRams[0]
    if let letter = ram.letter {
        JourneyCertificateView(ram: ram, letter: letter)
            .padding()
    }
}
