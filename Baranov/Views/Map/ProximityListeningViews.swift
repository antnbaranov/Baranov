//
//  ProximityListeningViews.swift
//  Baranov
//
//  What passive code discovery looks like: quiet rings in the background
//  while the phone listens for a nearby sender, a status row saying so,
//  and a confirmation pill once a code is locked.
//

import SwiftUI

/// Expanding rings drawn into the background canvas. Static under Reduce Motion.
struct ProximityRadarBackground: View {
    var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive || reduceMotion)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width / 2, y: size.height * 0.28)
                let maxRadius = max(size.width, size.height) * 0.5
                for i in 0..<3 {
                    let phase = (t / 3.2 + Double(i) / 3.0).truncatingRemainder(dividingBy: 1)
                    let r = maxRadius * phase
                    let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                    context.stroke(Path(ellipseIn: rect),
                                   with: .color(.accentColor.opacity((1 - phase) * 0.3)),
                                   lineWidth: 1)
                }
            }
        }
        .opacity(isActive ? 1 : 0)
        .animation(.easeInOut(duration: 0.6), value: isActive)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// "Looking for someone who's sending…" / "Sharing your code…" status row.
struct ProximityStatusRow: View {
    let state: ProximityCodeDiscovery.State
    let isBroadcasting: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isBroadcasting ? "wave.3.right" : "dot.radiowaves.left.and.right")
                .symbolEffect(.variableColor.iterative, isActive: isBroadcasting || state == .listening)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(isBroadcasting ? "Sharing your receiving code" : "Looking for someone who's sending")
                    .font(.subheadline.weight(.semibold))
                Text(isBroadcasting ? "Anyone nearby who is listening can pick it up for the next minute or so."
                                    : "Keep this screen open near the sender.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false,
                     fallbackMaterial: .thinMaterial)
        .accessibilityElement(children: .combine)
    }
}

struct CodeLockedPill: View {
    let code: String
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pickup code found")
                    .font(.subheadline.weight(.semibold))
                Text(code)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Use", action: onAccept)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .liquidGlass(in: Capsule(style: .continuous), interactive: false, fallbackMaterial: .thinMaterial)
        .padding(.horizontal, 16)
    }
}
