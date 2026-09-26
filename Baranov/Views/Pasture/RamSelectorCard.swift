//
//  RamSelectorCard.swift
//  Baranov
//
//  The big card at the top of Pasture: the ram-selector slider itself,
//  plus a focused summary of whichever ram is currently selected — its
//  name (tap to rename it, right from here rather than only at compose
//  time) and how many letters it's delivered across its lifetime (from
//  `RamLedger`, since a single `Ram` only ever represents one journey).
//  Switching the slider's selection crossfades this summary to match,
//  rather than swapping it instantly.
//
//  The "Passport" and "Rankings" buttons that used to live here are
//  gone: Passport now opens from a luggage tag on the ram's own card
//  down in the Satchel (`RamCardView`), and Rankings/Game Center is
//  already one tap away from the Shepherds' Board card right below this
//  one — two separate doors to the same two rooms was clutter.
//

import SwiftUI

struct RamSelectorCard: View {
    let rams: [Ram]
    let capacity: Int
    let unlockedSlots: Int
    @Binding var selectedRamId: UUID?
    let onRentTapped: () -> Void
    let onRename: (Ram, String) -> Void
    let ledgerEntry: (Ram) -> RamLedgerEntry

    /// The person's own default ram, shown (and renameable, right here)
    /// even before any letter has ever been sent — onboarding guarantees
    /// it exists, so there's never a moment with nothing to show at all.
    let companion: RamCompanion?
    let onRenameCompanion: (String) -> Void
    /// Opens the selected ram's passport, right under the ram itself.
    var onPassportTapped: ((Ram) -> Void)? = nil

    @State private var isRenamePresented = false
    @State private var renameDraft = ""

    private var selectedRam: Ram? {
        rams.first { $0.id == selectedRamId } ?? rams.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RamSelectorSlider(
                rams: rams,
                capacity: capacity,
                unlockedSlots: unlockedSlots,
                selectedRamId: $selectedRamId,
                onRentTapped: onRentTapped,
                onNameTapped: { ram in
                    renameDraft = ram.name
                    isRenamePresented = true
                },
                companion: companion,
                onCompanionNameTapped: {
                    guard let companion else { return }
                    renameDraft = companion.name
                    isRenamePresented = true
                }
            )

            if let ram = selectedRam {
                Divider()

                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Button {
                            renameDraft = ram.name
                            isRenamePresented = true
                        } label: {
                            HStack(spacing: 4) {
                                Text(ram.name)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        Text(deliveredCountLabel(for: ledgerEntry(ram).lettersDelivered))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .id(ram.id)
                    .transition(.opacity.combined(with: .move(edge: .leading)))

                    Spacer(minLength: 8)

                    if let onPassportTapped {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onPassportTapped(ram)
                        } label: {
                            Image(systemName: "map.fill")
                        }
                        .glassIconButton()
                        .accessibilityLabel("Passport & Journeys")
                        .accessibilityHint("Shows every journey \(ram.name) has walked on a map, with its stamps")
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: ram.id)
            } else if let companion {
                // No real ram yet, but the person's own companion always
                // exists from the moment onboarding runs — shown here the
                // same way a selected ram would be, minus History/
                // Rankings, since there's no journey behind it yet.
                Divider()

                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Button {
                            renameDraft = companion.name
                            isRenamePresented = true
                        } label: {
                            HStack(spacing: 4) {
                                Text(companion.name)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        Text("\(companion.ageStage.displayName) · \(companion.ageDescription) · ready for a first letter")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    // The passport exists from day one, before any letter
                    // has walked: an empty book waiting for its first stamp.
                    if let onPassportTapped {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onPassportTapped(Ram.restingStub(for: companion))
                        } label: {
                            Image(systemName: "map.fill")
                        }
                        .glassIconButton()
                        .accessibilityLabel("Passport & Journeys")
                        .accessibilityHint("Opens \(companion.name)'s passport, ready for its first stamp")
                    }
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .alert("Rename Ram", isPresented: $isRenamePresented) {
            TextField("Ram's name", text: $renameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if let ram = selectedRam {
                    onRename(ram, trimmed)
                } else if companion != nil {
                    onRenameCompanion(trimmed)
                }
            }
        }
    }

    private func deliveredCountLabel(for count: Int) -> String {
        count == 1 ? "1 letter delivered" : "\(count) letters delivered"
    }
}

#Preview {
    @Previewable @State var selectedRamId: UUID? = FlockViewModel.preview.activeRams.first?.id
    RamSelectorCard(
        rams: FlockViewModel.preview.activeRams,
        capacity: FlockViewModel.pastureCapacity,
        unlockedSlots: 1,
        selectedRamId: $selectedRamId,
        onRentTapped: {},
        onRename: { _, _ in },
        ledgerEntry: { ram in RamLedger.preview.entry(forName: ram.name) },
        companion: RamCompanionStore.preview.companion,
        onRenameCompanion: { _ in },
        onPassportTapped: { _ in }
    )
    .padding()
}
