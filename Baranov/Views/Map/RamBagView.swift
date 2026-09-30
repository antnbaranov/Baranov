//
//  RamBagView.swift
//  Baranov
//
//  The ram's bag: what opens when you tap a ram in the mailbag. A plain
//  inset list — who is carrying, how far it has come, the route, and the
//  letter. Opening the letter pushes it right here inside the sheet
//  (`LetterDetailView`, embedded), so the seal ritual happens where you
//  tapped rather than in a second sheet. The receiving code is shared from
//  the toolbar.
//
//  Reads the live ram out of the flock by id, so progress and status keep
//  updating while the sheet is open. System materials and semantic styles.
//

import SwiftUI

struct RamBagView: View {
    let ramId: UUID
    /// Starts the shake handoff from inside the letter (owned by `RootView`).
    var onShakeHandoff: (() -> Void)? = nil
    /// Pushed inside another `NavigationStack` (the mailbag page of the
    /// docked sheet): no stack of its own and no close button — the
    /// system back button returns to the list.
    var isEmbedded = false

    @Environment(FlockViewModel.self) private var flockViewModel
    @Environment(RecallService.self) private var recallService: RecallService?
    @Environment(\.dismiss) private var dismiss

    private var ram: Ram? {
        flockViewModel.activeRams.first { $0.id == ramId }
    }

    var body: some View {
        if isEmbedded {
            screen
        } else {
            NavigationStack { screen }
        }
    }

    private var screen: some View {
        Group {
            if let ram {
                content(for: ram)
            } else {
                ContentUnavailableView("This ram is no longer in the pasture", systemImage: "bag")
            }
        }
        .navigationTitle(ram?.name ?? "Ram's Bag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isEmbedded {
                ToolbarItem(placement: .topBarLeading) {
                    CloseToolbarButton { dismiss() }
                }
            }
            if let message = ram?.letterShareMessage {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: message) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share Ear Tag")
                }
            }
        }
    }

    // MARK: - Content

    private func content(for ram: Ram) -> some View {
        let origin = (ram.routeHistory.first?.cityName ?? ram.currentCity).mailbagShortName
        return List {
            Section {
                HStack(spacing: 12) {
                    RamPortraitView(name: ram.name, diameter: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ram.name).font(.headline)
                        MailbagStatusBadge(ram: ram)
                    }
                }
                if ram.isEnRoute {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: min(max(ram.progress, 0), 1)).tint(Color.accentColor)
                        HStack {
                            Text("\(DistanceFormatter.string(forMeters: ram.journeyStepsSoFar)) walked")
                            Spacer()
                            Text("\(DistanceFormatter.string(forMeters: ram.remainingSteps)) to go")
                        }
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Route") {
                LabeledContent("From", value: origin)
                LabeledContent("To", value: ram.targetCity.mailbagShortName)
            }

            if ram.isGuest {
                guestSection(for: ram)
            } else if ram.status == .handedOff, !ram.wasDeliveredInPerson {
                takeBackSection(for: ram)
            }

            if let letter = ram.letter {
                Section("Letter") {
                    NavigationLink {
                        LetterDetailView(ram: ram, onShakeHandoff: onShakeHandoff, isEmbedded: true)
                    } label: {
                        Label(ram.status == .arrivedAtGate ? "Open the Letter" : "View the Letter",
                              systemImage: ram.status == .arrivedAtGate ? "envelope.open" : "envelope")
                    }
                    if !letter.senderName.isEmpty {
                        LabeledContent("From", value: letter.senderName)
                    }
                    if !letter.recipientName.isEmpty {
                        LabeledContent("To", value: letter.recipientName)
                    }
                }
            }

            if !ram.passengerLetters.isEmpty {
                Section("Also in the Bag") {
                    ForEach(ram.passengerLetters, id: \.id) { passenger in
                        LabeledContent("For \(passenger.recipientName)", value: passenger.senderName)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(isEmbedded ? .hidden : .automatic)
    }

    // MARK: - Someone else's letter

    /// A letter this phone is only carrying: it rides with the person's own
    /// ram and its sender can ask for it back.
    private func guestSection(for ram: Ram) -> some View {
        let sender = ram.letter?.senderName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Section {
            Label {
                Text(sender.isEmpty
                     ? String(localized: "Carrying it for someone else", bundle: .appLanguage, locale: .appLanguage)
                     : String(localized: "Carrying it for \(sender)", bundle: .appLanguage, locale: .appLanguage))
            } icon: {
                Image(systemName: "envelope.badge.person.crop")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("It rides in your mailbag and moves with your steps, without taking a pen in your pasture. The sender can ask for it back at any time.")
        }
    }

    // MARK: - Taking it back

    /// The sender's side of a letter handed on to someone else.
    @ViewBuilder
    private func takeBackSection(for ram: Ram) -> some View {
        let isRequesting = recallService?.requesting.contains(ram.id) ?? false
        if ram.recallRequestedAt != nil {
            Section {
                Label {
                    Text("Asking for it back")
                } icon: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("\(ram.name) comes home the next time the carrier's phone is online.")
            }
        } else if flockViewModel.canTakeBack(ram), let recallService, TelemetryService.isServerConfigured {
            Section {
                Button {
                    Task { await recallService.takeBack(ram, flock: flockViewModel) }
                } label: {
                    HStack {
                        Label("Take it back", systemImage: "arrow.uturn.backward")
                        Spacer()
                        if isRequesting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRequesting)
            } footer: {
                if recallService.failedRamID == ram.id {
                    Text("Couldn't reach the post office. Check your connection and try again.")
                } else {
                    Text("Not going the right way? Ask for the letter back. \(ram.name) returns to where you handed it on. You can also meet the carrier and have them hand it back.")
                }
            }
        } else {
            // Works with no server at all: the carrier hands it back the
            // same way it left — a shake, Hand over, or AirDrop. It comes
            // home as the sender's own ram, not a guest.
            Section {
                Label {
                    Text("Want it back? Meet the carrier and ask them to hand it over.")
                } icon: {
                    Image(systemName: "hand.wave")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("It comes back to you as your own letter, and \(ram.name) walks on from where it is.")
            }
        }
    }
}


// MARK: - Resting ram

/// The bag of the person's own ram when nothing is out: no letters aboard,
/// and one prominent way to put the first one in. Pushed from the idle row
/// of the mailbag, so it lives inside the sheet like every other bag.
struct IdleRamBagView: View {
    let name: String
    let onWriteLetter: () -> Void

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    RamPortraitView(name: name, diameter: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.headline)
                        Text("Ready for a letter")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Section("Letters") {
                // A quiet row, not a full-height empty state: the bag is
                // small and the call to action sits right under it.
                Label {
                    Text("The bag is empty. Write a letter and \(name) will carry it on foot.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "tray")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        // The call to action is pinned under the list, with no bar
        // material behind it — just the button floating over the list.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onWriteLetter) {
                Label("Write a letter", systemImage: "pencil.line")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
