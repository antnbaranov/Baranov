//
//  LiquidGlass.swift
//  Baranov
//
//  One glass surface for the app's floating controls: real Liquid Glass
//  (`glassEffect`, with the system's own specular highlight and
//  refraction) on iOS 26+, a system Material with a hairline edge below
//  that. No gradients, no coloured shadows.
//

import SwiftUI

enum PastureTheme {
    /// Natural pasture green — only ever a light tint over system glass.
    static let green = Color(red: 0.33, green: 0.60, blue: 0.36)
}

struct LiquidGlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive: Bool
    var pressed: Bool
    var fallbackMaterial: Material

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content
                .background {
                    ZStack {
                        shape.fill(fallbackMaterial)
                        if let tint { shape.fill(tint.opacity(0.22)) }
                    }
                }
                .overlay { shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
                .scaleEffect(pressed ? 0.97 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pressed)
        }
    }
}

extension View {
    func liquidGlass<S: InsettableShape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = true,
        pressed: Bool = false,
        fallbackMaterial: Material = .ultraThinMaterial
    ) -> some View {
        modifier(LiquidGlassSurface(shape: shape, tint: tint, interactive: interactive,
                                    pressed: pressed, fallbackMaterial: fallbackMaterial))
    }
}

// MARK: - "Share Receiving Code" — clear glass capsule

struct ShareCodeGlassButtonStyle: ButtonStyle {
    /// Light tint over the glass (pasture green in the satchel).
    var tint: Color? = nil
    /// Fill the available width (satchel card) instead of hugging the label.
    var expands = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .symbolRenderingMode(.hierarchical)
            .padding(.horizontal, 20)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: 48)
            .liquidGlass(in: Capsule(style: .continuous), tint: tint?.opacity(0.55),
                         pressed: configuration.isPressed, fallbackMaterial: .regularMaterial)
            .contentShape(Capsule(style: .continuous))
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, new in new }
    }
}
