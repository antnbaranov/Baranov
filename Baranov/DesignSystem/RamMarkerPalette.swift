//
//  RamMarkerPalette.swift
//  Baranov
//
//  Flat, literal brand colors for the ram mascot itself (its actual fleece/
//  horn/seal coloring, not UI chrome) — distinct from the semantic
//  `.primary`/`.secondary`/System Material rules that govern the rest of
//  Baranov's interface. No gradients, glows, or glassmorphism: just flat
//  fills, each with a light/dark variant so the marker still reads clearly
//  on a dark-mode map.
//
//  Placeholder note: once real branded art/colors exist (likely as Asset
//  Catalog color sets so they can be tuned without a code change), replace
//  the literal values below with `Color("RamFleece")` etc. — nothing that
//  reads `RamMarkerPalette.fleece` elsewhere needs to change.
//

import SwiftUI
import UIKit

public enum RamMarkerPalette {
    public static let fleece = Color(
        light: Color(red: 0.94, green: 0.90, blue: 0.80),
        dark: Color(red: 0.80, green: 0.75, blue: 0.62)
    )
    public static let fleeceShadowLeg = Color(
        light: Color(red: 0.82, green: 0.77, blue: 0.64),
        dark: Color(red: 0.62, green: 0.57, blue: 0.46)
    )
    public static let horn = Color(
        light: Color(red: 0.80, green: 0.64, blue: 0.28),
        dark: Color(red: 0.90, green: 0.74, blue: 0.36)
    )
    public static let envelope = Color(
        light: Color(white: 0.98),
        dark: Color(white: 0.92)
    )
    public static let wax = Color(
        light: Color(red: 0.70, green: 0.14, blue: 0.14),
        dark: Color(red: 0.80, green: 0.22, blue: 0.20)
    )
    /// The walked route itself — a deep, muted ink-brown (not the app's
    /// interactive `accentColor`) so the trail on the map reads as a
    /// track left in the ground, distinct from anything tappable.
    public static let routeTrail = Color(
        light: Color(red: 0.36, green: 0.27, blue: 0.17),
        dark: Color(red: 0.82, green: 0.69, blue: 0.50)
    )
}

private extension Color {
    /// A simple light/dark adaptive color, without needing an Asset Catalog
    /// entry — useful for a small set of brand-literal (non-semantic)
    /// colors like the mascot's own coloring.
    init(light: Color, dark: Color) {
        self = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
