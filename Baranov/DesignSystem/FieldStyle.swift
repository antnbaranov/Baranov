//
//  FieldStyle.swift
//  Baranov
//
//  The pill/capsule and material-backed field surfaces used throughout
//  the compose sheet, shared so every text field reads as one consistent
//  Apple-Maps-style surface — rather than a mix of the search fields'
//  `.thinMaterial`-in-`Capsule()` look and a plain system `.roundedBorder`
//  box, which is what "Your Name," "Message," and the custom ram-name
//  field looked like before this file existed.
//

import SwiftUI

extension View {
    /// The single-line pill background used by `PlaceSearchField`,
    /// `ContactSuggestionField`, and the confirmed-destination /
    /// current-location summary chips. Pair with `.textFieldStyle(.plain)`
    /// on a `TextField` so the system doesn't also draw its own border.
    func pillFieldBackground() -> some View {
        modifier(PillFieldBackground())
    }

    /// The material-backed rounded-rectangle field background for
    /// multi-line fields (like the letter's message body) where a full
    /// stadium capsule would look wrong.
    func materialFieldBackground(cornerRadius: CGFloat = 16) -> some View {
        modifier(MaterialFieldBackground(cornerRadius: cornerRadius))
    }
}

private struct PillFieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            // One line of `.body` text (what the `TextField` rows are) is
            // ~22 pt; pinning every pill's content to that minimum keeps a
            // row that only holds a `.subheadline` label (the confirmed
            // destination chip, the ram row) exactly the same height as
            // the text-field rows — Apple Maps' directions sheet keeps
            // all of its rows one uniform height regardless of content.
            .frame(minHeight: 22)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(.thinMaterial, in: Capsule())
    }
}

private struct MaterialFieldBackground: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Compact glass buttons

extension View {
    /// Small capsule button: Liquid Glass on iOS 26+, the system
    /// bordered style on iOS 18–25.
    @ViewBuilder
    func compactGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(.secondary)
        } else {
            self.buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .tint(.secondary)
        }
    }

    /// Icon-only round glass button (Liquid Glass on iOS 26+, a bordered
    /// circle on iOS 18–25).
    @ViewBuilder
    func glassIconButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
        } else {
            self.buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .tint(.secondary)
        }
    }
}
