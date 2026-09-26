//
//  RamHistoryView.swift
//  Baranov
//
//  A ram's field passport, opened from the "Passport" button on its
//  selector card: an analog travel journal rather than a settings table.
//  ID page, the stamp collection, the ram's own notes on the road, and
//  the equipment it has earned — laid on the linen tabletop the letters
//  use, so the two objects belong to the same desk.
//
//  Stamps are read from two places and merged (see `passportStamps`):
//  the ledger holds everything from journeys already delivered, while the
//  `Ram` itself still carries the stamps of a journey in flight — which is
//  also what lets them travel through an AirDrop handoff.
//
//  Pushed inside Pasture's navigation stack, so it owns no close button.
//

import SwiftUI

struct RamHistoryView: View {
    let ram: Ram
    let ledgerEntry: RamLedgerEntry

    @State private var isReelPresented = false
    private var job: ReelJobStore { .shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PassportStampsSection(stamps: passportStamps, ramName: ram.name)

                fieldMap

                // Full-bleed: the carousel scrolls edge to edge past the page margins.
                PassportNotesSection(ramName: ram.name, stamps: passportStamps)
                    .padding(.horizontal, -16)

                PassportEquipmentSection(
                    ramID: ram.id,
                    ramName: ram.name,
                    totalMeters: lifetimeMeters,
                    lettersDelivered: ledgerEntry.lettersDelivered,
                    stamps: passportStamps
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .symbolVariant(.fill)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .onAppear { job.suppressesOverlay = true }
        .onDisappear { if job.ramName == ram.name { job.suppressesOverlay = false } }
        .navigationTitle(ram.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isReelPresented = true } label: {
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                }
                .accessibilityLabel("Make a reel")
            }
        }
        .sheet(isPresented: $isReelPresented) {
            RamReelSheet(base: RamReelData.make(
                ramName: ram.name,
                totalMeters: lifetimeMeters,
                lettersDelivered: ledgerEntry.lettersDelivered,
                stamps: passportStamps
            ))
        }
    }

    // MARK: - Data

    /// Delivered journeys (ledger) plus the one in flight.
    private var lifetimeMeters: Int {
        ledgerEntry.totalStepsWalked + (ram.status == .delivered ? 0 : ram.journeyStepsSoFar)
    }

    /// The full passport: stamps already folded into this name's lifetime
    /// ledger plus the ones the ram is still carrying. Merged by id — a
    /// delivered ram that is still in `activeRams` appears in both — and
    /// newest first, the way a real passport's latest page is the one you
    /// open to.
    private var passportStamps: [JourneyStamp] {
        var seen = Set<UUID>()
        return (ram.stamps + ledgerEntry.stamps)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Field map

    private var fieldMap: some View {
        VStack(alignment: .leading, spacing: 14) {
            JournalHeading(title: "Journeys", symbol: "map.fill")
            RamJourneysMap(
                ramName: ram.name,
                stamps: passportStamps,
                plannedRoute: ram.status == .delivered ? [] : ram.routeCoordinates.map(\.clLocationCoordinate),
                totalMeters: lifetimeMeters
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard()
    }
}

#Preview {
    NavigationStack {
        RamHistoryView(
            ram: FlockViewModel.preview.activeRams[0],
            ledgerEntry: RamLedger.preview.entry(forName: "Klaus")
        )
    }
}
