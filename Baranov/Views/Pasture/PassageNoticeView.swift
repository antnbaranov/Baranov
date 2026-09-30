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
        } else if ram.status == .grazing || ram.status == .walking {
            // Still on land, heading for a port: say so now, while a friend
            // flying that way can still help, not once the ram is at the quay.
            noticeCard(
                icon: "water.waves",
                title: String(localized: "Water ahead at \(ram.legDestinationCity)", bundle: .appLanguage, locale: .appLanguage),
                detail: String(localized: "Walks to the port, then a packet carries the letter across. Flying that way sooner? Take \(ram.name) with you — once you land, the ram goes ashore too.", bundle: .appLanguage, locale: .appLanguage),
                showProgress: false,
                progress: 0
            )
        } else {
            noticeCard(
                icon: "ferry.fill",
                title: String(localized: "At the quay in \(ram.legDestinationCity)", bundle: .appLanguage, locale: .appLanguage),
                detail: String(localized: "No road goes further. Baranov is arranging the next packet — until it does, a carrier heading across can take \(ram.name) instead.", bundle: .appLanguage, locale: .appLanguage),
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
            return String(localized: "At sea — \(voyage.departurePortName) to \(voyage.arrivalPortName)", bundle: .appLanguage, locale: .appLanguage)
        }
        return String(localized: "Packet to \(voyage.arrivalPortName)", bundle: .appLanguage, locale: .appLanguage)
    }

    private func detail(for voyage: SeaVoyage) -> String {
        if ram.status == .atSea {
            return String(localized: "Due ashore \(voyage.arrivesAt.formatted(.relative(presentation: .named).locale(.appLanguage))). Nothing to walk until it lands.", bundle: .appLanguage, locale: .appLanguage)
        }
        return String(localized: "Sails \(voyage.departsAt.formatted(.relative(presentation: .named).locale(.appLanguage))) and lands \(voyage.arrivesAt.formatted(.relative(presentation: .named).locale(.appLanguage))). Hand \(ram.name) to someone crossing sooner and it skips the wait entirely.", bundle: .appLanguage, locale: .appLanguage)
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
