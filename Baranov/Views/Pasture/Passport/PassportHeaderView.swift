//
//  PassportHeaderView.swift
//  Baranov
//
//  The ID page of a ram's field passport: portrait with a wax monogram
//  seal, name and breed in serif type, and a luggage tag that says where
//  the ram is right now.
//

import SwiftUI

struct PassportHeaderView: View {
    let ram: Ram

    private var monogram: String {
        String(ram.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    private var tag: (text: String, tint: Color, symbol: String) {
        switch ram.status {
        case .arrivedAtGate: (String(localized: "At the Gate", bundle: .appLanguage, locale: .appLanguage), PassportInk.green, "seal.fill")
        case .walking: (String(localized: "On the Way", bundle: .appLanguage, locale: .appLanguage), PassportInk.blue, "figure.walk")
        case .waitingForHandoff: (String(localized: "At the Port", bundle: .appLanguage, locale: .appLanguage), PassportInk.blue, "ferry")
        case .atSea: (String(localized: "At Sea", bundle: .appLanguage, locale: .appLanguage), PassportInk.blue, "sailboat")
        case .handedOff: (String(localized: "Handed On", bundle: .appLanguage, locale: .appLanguage), Color.secondary, "hand.wave")
        case .delivered: (String(localized: "Delivered", bundle: .appLanguage, locale: .appLanguage), PassportInk.green, "checkmark.seal.fill")
        case .grazing: (String(localized: "Resting", bundle: .appLanguage, locale: .appLanguage), Color.secondary, "leaf.fill")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SHEPHERD'S FIELD PASSPORT")
                .font(.system(.caption2).weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(PassportInk.inkSoft)

            HStack(alignment: .center, spacing: 16) {
                RamPortraitView(name: ram.name, diameter: 76)
                    .overlay(alignment: .bottomTrailing) { waxMonogram.offset(x: 8, y: 8) }
                    .padding(.trailing, 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(ram.name)
                        .font(.title.weight(.bold))
                        .foregroundStyle(PassportInk.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text("Alpine Courier Ram")
                        .font(.subheadline)
                        .foregroundStyle(PassportInk.inkSoft)
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .center, spacing: 12) {
                luggageTag
                if ram.isEnRoute {
                    Text(String(localized: "Bound for \(ram.targetCity)", bundle: .appLanguage, locale: .appLanguage))
                        .font(.footnote)
                        .foregroundStyle(PassportInk.inkSoft)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard()
    }

    private var waxMonogram: some View {
        Text(monogram)
            .scaledFont(size: 15, weight: .black, design: .serif)
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 30, height: 30)
            .background(PassportInk.red, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1).padding(3))
            .accessibilityHidden(true)
    }

    private var luggageTag: some View {
        Label(tag.text, systemImage: tag.symbol)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tag.tint)
            .lineLimit(1)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(tag.tint.opacity(0.15), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}
