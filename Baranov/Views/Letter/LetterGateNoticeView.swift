//
//  LetterGateNoticeView.swift
//  Baranov
//
//  The "is this letter for me?" check from `LetterArrivalView`, shown
//  *inline* inside a satchel card instead of behind a separate sheet.
//  While the city is still resolving it says so; once resolved and
//  everything matches it hands control back (`onVerified`) so the
//  caller can open the real seal ritual; otherwise it explains, in
//  place, what doesn't match.
//

import CoreLocation
import SwiftUI

struct LetterGateNoticeView: View {
    let ram: Ram
    var onVerified: () -> Void

    @Environment(LocationService.self) private var locationService

    private var recipientName: String { ram.letter?.recipientName ?? "" }

    /// Any of the person's active names (name, nickname, pen name).
    private var recipientNameMatches: Bool { NameProfile.matches(recipientName) }

    /// Only a letter the sender left at a Precise Geo Drop holds the recipient to a spot.
    private var isPreciseDrop: Bool { ram.letter?.geofence != nil }

    /// `nil` while there is no location fix yet; always `true` for a standard letter.
    private var isAtSpot: Bool? {
        guard isPreciseDrop else { return true }
        guard let here = locationService.currentCoordinate, let letter = ram.letter else { return nil }
        return !letter.isOutsideGeofence(of: here)
    }

    private var isVerified: Bool { recipientNameMatches && isAtSpot == true }

    private var walkRowText: String {
        if isAtSpot == true { return String(localized: "You're at the pick-up spot", bundle: .appLanguage, locale: .appLanguage) }
        if let remaining = ram.letter?.geofenceDistanceRemaining(from: locationService.currentCoordinate) {
            return String(localized: "Walk to the spot the sender chose. \(DistanceFormatter.string(forMeters: Int(remaining))) to go.", bundle: .appLanguage, locale: .appLanguage)
        }
        return String(localized: "Walk to the spot the sender chose", bundle: .appLanguage, locale: .appLanguage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isAtSpot == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Finding where you are…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label(recipientNameMatches ? "Left at the Gate for You" : "This Letter Isn't for You",
                      systemImage: recipientNameMatches ? "figure.walk" : "lock.shield")
                    .font(.subheadline.weight(.semibold))

                row(recipientNameMatches,
                    recipientNameMatches ? String(localized: "Addressed to you", bundle: .appLanguage, locale: .appLanguage) : String(localized: "Addressed to \(recipientName.isEmpty ? String(localized: "someone else", bundle: .appLanguage, locale: .appLanguage) : recipientName)", bundle: .appLanguage, locale: .appLanguage))
                if isPreciseDrop {
                    row(isAtSpot == true, walkRowText)
                }

                if !recipientNameMatches, ram.letter?.requiresNameMatch == true {
                    Text("The sender made this letter for one name only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !recipientNameMatches {
                    Text("Not one of your names? The ear tag code still opens it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: onVerified) {
                        Label("I have the code", systemImage: "key.fill")
                    }
                    .buttonStyle(ShareCodeGlassButtonStyle(expands: true))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task {
            if isPreciseDrop, locationService.currentCoordinate == nil { locationService.resolveCurrentLocation() }
            if isVerified { onVerified() }
        }
        .onChange(of: isVerified) { _, verified in
            if verified { onVerified() }
        }
        .accessibilityElement(children: .contain)
    }

    private func row(_ isMatch: Bool, _ label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isMatch ? .green : .red)
            Text(label).font(.subheadline)
        }
    }
}

private extension String {
    var gateNormalized: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
