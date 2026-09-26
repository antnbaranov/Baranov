//
//  GlassCloseButton.swift
//  Baranov
//
//  The app's close control: an `xmark` in a Liquid Glass circle (a
//  Material circle below iOS 26). Used wherever a header is drawn by hand;
//  inside a real navigation bar the bar supplies the glass itself, so
//  those use `CloseToolbarButton` (icon only, never the word "Close").
//

import SwiftUI

struct GlassCloseButton: View {
    var label: LocalizedStringKey = "Close"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .liquidGlass(in: Circle(), fallbackMaterial: .thinMaterial)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// For `ToolbarItem`s: the bar wraps an icon-only button in glass on iOS 26.
struct CloseToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: "xmark") }
            .accessibilityLabel("Close")
    }
}
