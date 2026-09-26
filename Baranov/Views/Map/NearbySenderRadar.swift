//
//  NearbySenderRadar.swift
//  Baranov
//
//  The marker on the map when someone standing nearby is sharing a receiving
//  code (see `ProximityCodeDiscovery`). Bluetooth/Wi-Fi discovery can say
//  "someone is close" but never where, so the marker sits on your own dot and
//  pulses in rings — it means "they're within reach", not a position.
//  Tapping it opens the letter at the gate that the code fits, if there is
//  one. Static under Reduce Motion.
//
//  System materials and semantic styles only.
//

import SwiftUI

struct NearbySenderRadar: View {
    var onTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        for i in 0..<3 {
                            let phase = reduceMotion ? 0.6 : (t / 2.8 + Double(i) / 3.0).truncatingRemainder(dividingBy: 1)
                            let radius = size.width / 2 * phase
                            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                            context.stroke(Path(ellipseIn: rect),
                                           with: .color(Color.accentColor.opacity((1 - phase) * 0.6)),
                                           lineWidth: 2)
                        }
                    }
                }
                .frame(width: 120, height: 120)

                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(.regularMaterial, in: Circle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Someone nearby is sharing a code")
        .accessibilityHint("Opens the letter it fits")
    }
}
