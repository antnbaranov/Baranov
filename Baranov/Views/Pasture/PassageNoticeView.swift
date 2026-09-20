//
//  PassageNoticeView.swift
//  Baranov
//
//  The one piece of UI that explains the whole handoff model, shown
//  wherever a ram is standing at a port or out on the water.
//
//  The mechanic is easy to misread as "you must find a stranger or your
//  letter is stuck forever", which was never the intent. This view states
//  the actual deal in two lines: a packet is already booked and will carry
//  the letter across on its own, and handing the ram to a person is the
//  shortcut that skips the wait. Nothing here asks the person to do
//  anything — it is a sailing notice, not a call to action.
//

import SwiftUI

struct PassageNoticeView: View {
    let ram: Ram

    private var voyage: SeaVoyage? { ram.voyage }

    var body: some View {
        if let voyage {
            noticeCard(
                icon: ram.status == .atSea ? "sailboat.fill" : "ferry.fill",
                title: headline(for: voyage),
                detail: detail(for: voyage),
                showProgress: ram.status == .atSea,
                progress: voyage.progress()
            )
        } else {
            noticeCard(
                icon: "ferry.fill",
                title: "At the quay in \(ram.legDestinationCity)",
                detail: "No road goes further. Baranov is arranging the next packet — until it does, a carrier heading across can take \(ram.name) instead.",
                showProgress: false,
                progress: 0
            )
        }
    }

    @ViewBuilder
    private func noticeCard(icon: String, title: String, detail: String, showProgress: Bool, progress: Double) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if showProgress {
                    ProgressView(value: progress)
                        .tint(.blue)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func headline(for voyage: SeaVoyage) -> String {
        if ram.status == .atSea {
            return "At sea — \(voyage.departurePortName) to \(voyage.arrivalPortName)"
        }
        return "Packet to \(voyage.arrivalPortName)"
    }

    private func detail(for voyage: SeaVoyage) -> String {
        if ram.status == .atSea {
            return "Due ashore \(voyage.arrivesAt.formatted(.relative(presentation: .named))). Nothing to walk until it lands."
        }
        return "Sails \(voyage.departsAt.formatted(.relative(presentation: .named))) and lands \(voyage.arrivesAt.formatted(.relative(presentation: .named))). Hand \(ram.name) to someone crossing sooner and it skips the wait entirely."
    }
}

#Preview {
    let port = RamCoordinate(latitude: 47.5615, longitude: -52.7126)
    let shore = RamCoordinate(latitude: 53.3498, longitude: -6.2603)
    let ram = Ram(
        name: "Klaus",
        status: .waitingForHandoff,
        stepsWalked: 12_000,
        totalStepsRequired: 12_000,
        currentCity: "St. John's",
        targetCity: "Frankfurt",
        legDestinationCity: "St. John's",
        requiresHandoffAtLegEnd: true,
        voyage: SeaVoyage(
            departurePortName: "St. John's",
            arrivalPortName: "Dublin",
            departurePort: port,
            arrivalPort: shore,
            departsAt: Date().addingTimeInterval(3 * 3600),
            arrivesAt: Date().addingTimeInterval(40 * 3600)
        ),
        finalDestinationCoordinate: RamCoordinate(latitude: 50.1109, longitude: 8.6821)
    )
    VStack(spacing: 12) {
        PassageNoticeView(ram: ram)
    }
    .padding()
}
