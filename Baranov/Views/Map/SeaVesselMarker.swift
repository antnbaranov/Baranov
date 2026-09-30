//
//  SeaVesselMarker.swift
//  Baranov
//
//  The ram's ride across water: a ferry for a sea or a strait, an
//  airplane for an ocean. Drawn as a plain SF Symbol on a system material,
//  so nothing but the vessel is on the map while the letter crosses.
//

import SwiftUI

struct SeaVesselMarker: View {
    let isAirplane: Bool
    let bearingDegrees: Double

    var body: some View {
        Image(systemName: isAirplane ? "airplane" : "ferry.fill")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.primary)
            // The airplane glyph points east; the ship stays upright.
            .rotationEffect(.degrees(isAirplane ? bearingDegrees - 90 : 0))
            .frame(width: 44, height: 44)
            .background(.regularMaterial, in: Circle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(isAirplane ? "Crossing by plane" : "Crossing by ship"))
    }
}
