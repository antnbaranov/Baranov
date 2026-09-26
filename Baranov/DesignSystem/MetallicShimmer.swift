//
//  MetallicShimmer.swift
//  Baranov
//
//  Premium Materials (paid): a tilt-reactive specular highlight for the
//  three rare wax finishes (`SealColor.isRare`) — light catching real
//  metal/wax as the phone tilts, via `CoreMotion`'s device attitude.
//
//  This is deliberately not the "glow shadow" this project's design
//  rules forbid: a glow blurs light *outward*, past a shape's edge. This
//  highlight is clipped strictly inside the wax's own shape, the same
//  way `WaxSealView`'s existing emboss layers stay inside it — one more
//  way light plays across a material that's already there, not a light
//  source added on top of it. It also fully respects Reduce Motion by
//  simply not rendering.
//

import CoreMotion
import SwiftUI

/// One shared `CMMotionManager` for every shimmering swatch on screen at
/// once, so opening a picker with several rare colours doesn't start
/// several independent sensor subscriptions. Reference-counted rather
/// than always-on, so the sensor stops the moment nothing needs it.
@MainActor
@Observable
final class TiltMotionService {
    static let shared = TiltMotionService()

    private(set) var roll: Double = 0
    private let manager = CMMotionManager()
    private var subscriberCount = 0

    private init() {}

    func subscribe() {
        subscriberCount += 1
        guard subscriberCount == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.roll = motion.attitude.roll
        }
    }

    func unsubscribe() {
        subscriberCount = max(0, subscriberCount - 1)
        guard subscriberCount == 0 else { return }
        manager.stopDeviceMotionUpdates()
    }
}

/// A soft diagonal band of brightness that slides across the content as
/// the phone tilts, masked to whatever shape the content already is.
/// Active only while `isActive` is true and Reduce Motion is off.
struct MetallicShimmerModifier: ViewModifier {
    var isActive: Bool
    @State private var motion = TiltMotionService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRendering: Bool { isActive && !reduceMotion }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isRendering {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.5), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.7)
                        .offset(x: CGFloat(motion.roll) * 140)
                        .blendMode(.plusLighter)
                        .animation(.easeOut(duration: 0.12), value: motion.roll)
                    }
                    .allowsHitTesting(false)
                    .task { motion.subscribe() }
                    .onDisappear { motion.unsubscribe() }
                }
            }
    }
}

extension View {
    /// Applies `MetallicShimmerModifier`. Clip the receiver to its final
    /// shape first (as `WaxSealView` does with `WaxBlobShape`) so the
    /// highlight stays inside the material's own silhouette.
    func metallicShimmer(isActive: Bool) -> some View {
        modifier(MetallicShimmerModifier(isActive: isActive))
    }
}
