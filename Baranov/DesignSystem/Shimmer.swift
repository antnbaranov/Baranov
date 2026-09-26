//
//  Shimmer.swift
//  Baranov
//
//  A soft diagonal highlight that sweeps across a loading placeholder —
//  system-native looking, no third-party effects, no third-party frameworks.
//  Used wherever content is still being prepared and a static card (or a
//  frozen frame of real content) would read as broken rather than loading.
//

import SwiftUI

private struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.5

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.32), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: proxy.size.width * 0.5)
                        .rotationEffect(.degrees(18))
                        .offset(x: phase * proxy.size.width * 1.8)
                        .blendMode(.plusLighter)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipped()
            .task {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    /// A moving highlight over the view, marking it as a loading
    /// placeholder rather than finished content. Stays still under Reduce
    /// Motion.
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}
