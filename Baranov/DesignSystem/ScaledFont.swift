import SwiftUI

/// A fixed-design font that still honours Dynamic Type.
///
/// The point size scales with the user's text-size setting (relative to `textStyle`),
/// capped at `maxScale` times the base size so tightly designed cards such as the
/// passport and stamp layouts keep working at the largest accessibility sizes.
private struct ScaledFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let base: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    private let maxScale: CGFloat

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, textStyle: Font.TextStyle, maxScale: CGFloat) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        base = size
        self.weight = weight
        self.design = design
        self.maxScale = maxScale
    }

    func body(content: Content) -> some View {
        content.font(.system(size: min(size, base * maxScale), weight: weight, design: design))
    }
}

extension View {
    /// Drop-in replacement for `.font(.system(size:weight:design:))` that scales with Dynamic Type.
    func scaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: Font.TextStyle = .body,
        maxScale: CGFloat = 1.6
    ) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, design: design, textStyle: textStyle, maxScale: maxScale))
    }
}
