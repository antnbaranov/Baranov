//
//  SharingInvitationView.swift
//  Baranov
//
//  The one-time offer to be reachable by people nearby (see
//  `SharingInvitation` for when it appears). Says plainly what is shared and
//  what never is, and that it lives in Settings afterwards. "Not Now" is as
//  easy to tap as "Turn On" and the offer is not repeated.
//
//  System materials and semantic styles only.
//

import SwiftUI

struct SharingInvitationView: View {
    let onTurnOn: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Help letters find their way")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Let people nearby hand you their ram, and let senders see roughly where a ram you carry is.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                row("figure.2", "Open to carry", "Nearby senders see your name and first trip while the profile is open.")
                row("location.circle", "Approximate location", "Senders see the area of a ram you carry, never your exact position.")
                row("dot.radiowaves.left.and.right", "Nearby on the map", "You see when someone close has a letter for you.")
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(spacing: 10) {
                Button(action: onTurnOn) {
                    Text("Turn On").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)

                Button(action: onNotNow) {
                    Text("Not Now").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)

                Text("You can change this any time in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
