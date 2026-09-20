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

    private var cityMatches: Bool? {
        guard let city = locationService.currentCityName else { return nil }
        return city.gateNormalized == ram.targetCity.gateNormalized
    }

    private var isVerified: Bool { recipientNameMatches && cityMatches == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if cityMatches == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking you're at the gate…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("This Letter Isn't for You", systemImage: "lock.shield")
                    .font(.subheadline.weight(.semibold))

                row(recipientNameMatches,
                    recipientNameMatches ? "Addressed to you" : "Addressed to \(recipientName.isEmpty ? "someone else" : recipientName)")
                row(cityMatches == true,
                    cityMatches == true ? "You're at the right gate" : "This gate is in \(ram.targetCity)")

                Text("The seal can only be broken by the recipient, standing at the destination city.")
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
