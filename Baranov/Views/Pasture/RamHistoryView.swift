//
//  RamHistoryView.swift
//  Baranov
//
//  One named ram's full story, opened from the "Passport" button on its
//  selector card: the passport page itself (every place it has actually
//  walked past, as pressed stamps), this journey's route log from the
//  live `Ram`, and lifetime stats from `RamLedger` — letters delivered
//  and every waypoint logged across every journey walked under this name,
//  not just the current one.
//
//  Stamps are read from two places and merged (see `passportStamps`):
//  the ledger holds everything from journeys already delivered, while the
//  `Ram` itself still carries the stamps of a journey in flight — which is
//  also what lets them travel through an AirDrop handoff.
//

import SwiftUI

struct RamHistoryView: View {
    let ram: Ram
    let ledgerEntry: RamLedgerEntry

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PassportStampGrid(stamps: passportStamps, ramName: ram.name)
                } header: {
                    Text("Passport")
                } footer: {
                    if !passportStamps.isEmpty {
                        Text(passportSummary)
                    }
                }
                .listRowSeparator(.hidden)

                Section("This Journey") {
                    LabeledContent("Route", value: "\(ram.currentCity) → \(ram.targetCity)")
                    LabeledContent("Status", value: ram.status.displayName)

                    if let letter = ram.letter {
                        if letter.isEncrypted {
                            receivingCodeRow(for: letter)
                        } else {
                            LabeledContent("Letter", value: "Open postcard — no code needed")
                        }
                    }

                    if ram.routeHistory.isEmpty {
                        Text("No waypoints logged yet on this journey.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(ram.routeHistory) { node in
                            waypointRow(node)
                        }
                    }
                }

                Section("Lifetime") {
                    LabeledContent("Experience", value: "\(ledgerEntry.experiencePoints) XP")
                    LabeledContent("Letters Delivered", value: "\(ledgerEntry.lettersDelivered)")
                    LabeledContent("Total Steps Walked", value: "\(ledgerEntry.totalStepsWalked)")
                    LabeledContent("Places Stamped", value: "\(ledgerEntry.distinctPlacesVisited)")

                    if !ledgerEntry.waypoints.isEmpty {
                        ForEach(ledgerEntry.waypoints.sorted(by: { $0.timestamp > $1.timestamp })) { node in
                            waypointRow(node)
                        }
                    }
                }
            }
            .navigationTitle(ram.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// The full passport: stamps already folded into this name's lifetime
    /// ledger (delivered journeys) plus the ones the ram is still carrying
    /// on the journey in flight. Merged by id rather than concatenated —
    /// a delivered ram that is still in `activeRams` appears in both — and
    /// shown newest first, the way a real passport's latest page is the
    /// one you open to.
    private var passportStamps: [JourneyStamp] {
        var seen = Set<UUID>()
        return (ram.stamps + ledgerEntry.stamps)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Plain-string rather than inflected markup: the count is built at
    /// runtime from live data, so the singular/plural is decided here
    /// once instead of relying on grammar-agreement markup resolving
    /// correctly for every language this app ships in.
    private var passportSummary: String {
        let count = Set(passportStamps.map { $0.placeName.lowercased() }).count
        let noun = count == 1 ? "place" : "places"
        return "\(count) \(noun) stamped across every journey walked as \(ram.name)."
    }

    /// Surfaces the letter's receiving code here too — not just at the
    /// moment it was written — so a sender who skipped sharing it right
    /// away (or wants to send it again) can always find it again by
    /// opening this ram's own history.
    private func receivingCodeRow(for letter: Letter) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Receiving Code")
                    .font(.subheadline)
                Text(letter.receivingCode ?? "Kept on the sender's phone")
                    .font(.subheadline.weight(.semibold).monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let shareMessage = letter.shareMessage(carrierName: ram.name) {
                ShareLink(item: shareMessage) {
                    Image(systemName: "message.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Share Receiving Code")
            }
        }
    }

    private func waypointRow(_ node: RouteNode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(node.cityName)
                .font(.subheadline.weight(.medium))
            Text("\(node.stepsContributed) steps • \(node.timestamp.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    RamHistoryView(
        ram: FlockViewModel.preview.activeRams[0],
        ledgerEntry: RamLedger.preview.entry(forName: "Klaus")
    )
}
