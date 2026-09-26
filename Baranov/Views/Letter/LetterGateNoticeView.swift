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

    @AppStorage("com.baranov.carrierDisplayName") private var storedDisplayName = ""
    @Environment(LocationService.self) private var locationService

    private var recipientName: String { ram.letter?.recipientName ?? "" }

    private var recipientNameMatches: Bool {
        !storedDisplayName.gateNormalized.isEmpty
            && recipientName.gateNormalized == storedDisplayName.gateNormalized
    }

    private var distanceToGate: CLLocationDistance? {
        guard let here = locationService.currentCoordinate else { return nil }
        return ram.distanceToGate(from: here)
    }

    /// `nil` while there is no location fix yet.
    private var isAtPickupSpot: Bool? {
        distanceToGate.map { $0 <= Ram.pickupRadiusMeters }
    }

    private var isVerified: Bool { recipientNameMatches && isAtPickupSpot == true }

    private var walkRowText: String {
        if isAtPickupSpot == true { return String(localized: "You're at the pick-up spot") }
        if let distance = distanceToGate {
            return String(localized: "Walk to \(ram.targetCity) — \(DistanceFormatter.string(forMeters: Int(distance))) to go")
        }
        return String(localized: "Walk to \(ram.targetCity)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isAtPickupSpot == nil {
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
                    recipientNameMatches ? "Addressed to you" : "Addressed to \(recipientName.isEmpty ? "someone else" : recipientName)")
                row(isAtPickupSpot == true, walkRowText)

                Text("The letter was left at the gate. Only the recipient can collect it — by really walking there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task {
            if locationService.currentCoordinate == nil { locationService.resolveCurrentLocation() }
            if isVerified { onVerified() }
        }
        .onChange(of: isVerified) { _, verified in
            if verified { onVerified() }
        }
        .accessibilityElement(children: .combine)
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
