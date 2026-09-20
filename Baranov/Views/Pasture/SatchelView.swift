//
//  SatchelView.swift
//  Baranov
//
//  The Satchel — the letters your rams are carrying — as its own screen,
//  pushed from Pasture. Same inset-grouped list as Pasture and Settings so
//  the three read as one family. The courier itself lives on the main map
//  screen; this is only the record of letters.
//

import SwiftUI

struct SatchelView: View {
    @Environment(FlockViewModel.self) private var flockViewModel
    @Environment(EntitlementService.self) private var entitlementService
    @Environment(LocationService.self) private var locationService

    @AppStorage(AppAppearance.storageKey) private var appAppearanceRawValue = AppAppearance.system.rawValue

    @State private var carrierDirectory = KnownCarrierDirectory()
    @State private var ramLedger = RamLedger()
    @State private var ramCompanionStore = RamCompanionStore()
    @State private var letterRam: Ram?
    @State private var historyRam: Ram?
    @State private var query = ""
    /// The ram whose "is this letter for you?" check is open inline.
    @State private var gateRamId: UUID?
    /// Which ram's card is on top of the swipe stack.
    @State private var deckTopId: UUID?

    private var appAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRawValue) ?? .system
    }

    private var deliveredRams: [Ram] {
        flockViewModel.activeRams.filter { $0.status == .delivered }
    }

    /// Swipe sorting only earns its place once there are enough letters.
    private static let swipeDeckThreshold = 3

    private var filteredRams: [Ram] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return flockViewModel.activeRams }
        return flockViewModel.activeRams.filter { ram in
            [ram.name, ram.currentCity, ram.targetCity,
             ram.letter?.recipientName ?? "", ram.letter?.senderName ?? ""]
                .contains { $0.localizedStandardContains(q) }
        }
    }

    /// Opens the letter: straight to the seal ritual when this device's
    /// owner is the verified recipient at the gate, otherwise the check
    /// expands inline inside the card — no separate screen.
    private func openLetter(_ ram: Ram) {
        guard ram.status == .arrivedAtGate || ram.status == .delivered else { return }
        withAnimation(.snappy) {
            gateRamId = (gateRamId == ram.id) ? nil : ram.id
        }
    }

    /// The card, wired up the same wherever it's shown (stack or plain list).
    private func ramCard(_ ram: Ram) -> some View {
        RamCardView(
            ram: ram,
            isSelected: ram.id == flockViewModel.selectedRamId,
            matchedCarriers: carrierDirectory.matches(for: ram),
            onBreakSeal: { openLetter(ram) },
            onMarkHandedOff: {
                flockViewModel.markHandedOff(ramId: ram.id, to: nil)
            },
            gateExpanded: gateRamId == ram.id,
            onGateVerified: {
                gateRamId = nil
                letterRam = ram
            }
        )
        .contentShape(Rectangle())
        .onTapGesture { openLetter(ram) }
        .contextMenu {
            Button {
                historyRam = ram
            } label: {
                Label("Passport", systemImage: "person.text.rectangle")
            }
        }
    }

    /// One compact line of the full list; tapping brings that letter's
    /// card to the top of the stack.
    private func listRow(_ ram: Ram, proxy: ScrollViewProxy) -> some View {
        Button {
            query = ""
            withAnimation(.snappy) {
                deckTopId = ram.id
                proxy.scrollTo("deck", anchor: .top)
            }
        } label: {
            HStack(spacing: 12) {
                RamPortraitView(name: ram.name, diameter: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ram.letter.map { "To \($0.recipientName)" } ?? ram.name)
                        .font(.body).foregroundStyle(.primary).lineLimit(1)
                    Text("\(ram.currentCity) → \(ram.targetCity)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(ram.status.displayName)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        let useStack = flockViewModel.activeRams.count >= Self.swipeDeckThreshold
        ScrollViewReader { proxy in
            List {
                if !deliveredRams.isEmpty {
                    Section {
                        DeliveredLettersCarousel(rams: deliveredRams)
                            .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                if flockViewModel.activeRams.isEmpty {
                    Section {
                        ContentUnavailableView {
                            if let companion = ramCompanionStore.companion {
                                Label("\(companion.name) Hasn't Sent Anything Yet", systemImage: "bag")
                            } else {
                                Label("No Rams Yet", systemImage: "bag")
                            }
                        } description: {
                            Text("Send your first letter from the map to fill the satchel.")
                        }
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("Letters")
                    }
                } else if useStack {
                    if query.isEmpty {
                        Section {
                            RamSwipeDeck(rams: flockViewModel.activeRams, topId: $deckTopId) { ram in
                                ramCard(ram)
                            }
                            .id("deck")
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        } header: {
                            Text("Letters")
                        } footer: {
                            Text("Swipe a card away to see the next one.")
                        }
                    }

                    Section {
                        if filteredRams.isEmpty {
                            ContentUnavailableView.search(text: query)
                                .listRowBackground(Color.clear)
                        }
                        ForEach(filteredRams) { ram in
                            listRow(ram, proxy: proxy)
                        }
                    } header: {
                        Text("All Letters (\(filteredRams.count))")
                    }
                } else {
                    Section {
                        if filteredRams.isEmpty {
                            ContentUnavailableView.search(text: query)
                                .listRowBackground(Color.clear)
                        }
                        ForEach(filteredRams) { ram in
                            ramCard(ram)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        Text("All Letters (\(filteredRams.count))")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { searchBar }
        }
        .navigationTitle("Satchel")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $letterRam) { ram in
            LetterArrivalView(ram: ram)
                .environment(flockViewModel)
                .environment(entitlementService)
                .environment(locationService)
                .preferredColorScheme(appAppearance.colorScheme)
        }
        .sheet(item: $historyRam) { ram in
            RamHistoryView(ram: ram, ledgerEntry: ramLedger.entry(forName: ram.name))
                .preferredColorScheme(appAppearance.colorScheme)
        }
    }

    // MARK: - Bottom search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search letters", text: $query)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}
