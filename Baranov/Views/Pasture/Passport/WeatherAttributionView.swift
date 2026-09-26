//
//  WeatherAttributionView.swift
//  Baranov
//
//  The Apple Weather mark and legal link that WeatherKit's terms require
//  next to any weather it supplied. Renders nothing until the attribution
//  loads, and nothing at all if it can't (offline) — the stamp's own
//  weather line is already saved and readable either way.
//

import SwiftUI
import WeatherKit

struct WeatherAttributionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var attribution: WeatherAttribution?

    var body: some View {
        HStack(spacing: 6) {
            if let attribution {
                AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(height: 12)

                Link("Data sources", destination: attribution.legalPageURL)
                    .font(.system(size: 10, design: .serif))
            }
        }
        .task {
            if attribution == nil { attribution = await WeatherSnapshotService.attribution() }
        }
    }
}
