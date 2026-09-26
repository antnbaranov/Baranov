//
//  CarrierDirectoryView.swift
//  Baranov
//
//  Manage the manually-maintained list of "people already headed
//  somewhere" that `KnownCarrierDirectory` matches rams against. Adding
//  one reuses the exact same search fields the compose flow already
//  uses: `ContactSuggestionField` for a name (with the same lazy Contacts
//  access + native picker fallback), `PlaceSearchField` for a real,
//  resolved destination — never a freeform city name that might not
//  match anything later. A signed-in Game Center friend is a second,
//  even faster way to fill in just the name — GameKit has no idea where
//  anyone's actually headed, so the destination still has to be picked
//  by hand either way.
//
//  Dismissed via a trailing, bold "Done" (`.confirmationAction`) — the
//  standard HIG placement for the one affirmative way out of a form-style
//  sheet like this one, not a leading `.cancellationAction` button, which
//  reads as "discard" rather than "I'm finished."
//

import CoreLocation
import SwiftUI

struct CarrierDirectoryView: View {
    /// What the sheet is for. `.couriers` manages other people you know are
    /// headed somewhere; `.myTrip` registers the person's own trip, which
    /// needs a destination and nothing else.
    enum Mode { case couriers, myTrip }

    let directory: KnownCarrierDirectory
    var mode: Mode = .couriers
    var gameCenterService: GameCenterService? = nil
    var prefilledName: String? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var destinationCity = ""
    @State private var destinationCoordinate: CLLocationCoordinate2D?

    @State private var gameCenterFriends: [GameCenterFriend] = []
    @State private var hasLoadedGameCenterFriends = false

    @State private var addTick = 0
    @State private var pendingDelete: KnownCarrier?
    @State private var showsDeleteConfirmation = false
    @FocusState private var isFormFocused: Bool

    private var canAdd: Bool {
        destinationCoordinate != nil && (mode == .myTrip || !name.trimmed.isEmpty)
    }

    /// The person's own trips are managed from Profile, so they stay out of
    /// the list of other couriers.
    private var otherCouriers: [KnownCarrier] {
        directory.carriers.filter { !$0.name.hasPrefix("You (") }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if mode == .couriers {
                        ContactSuggestionField(placeholder: "Their Name", text: $name)
                    }

                    PlaceSearchField(
                        placeholder: mode == .myTrip ? "Where are you headed?" : "Where are they headed?",
                        text: $destinationCity
                    ) { title, coordinate in
                        destinationCity = title
                        destinationCoordinate = coordinate
                    }

                    Button {
                        add()
                    } label: {
                        if mode == .myTrip {
                            Label("Add Trip", systemImage: "airplane.departure")
                        } else {
                            Label("Add Courier", systemImage: "person.badge.plus")
                        }
                    }
                    .disabled(!canAdd)
                } header: {
                    Text(mode == .myTrip ? LocalizedStringKey("Your Trip") : LocalizedStringKey("Add a Courier"))
                } footer: {
                    if mode == .myTrip {
                        Text("Letters heading somewhere near your destination can be handed to you.")
                    } else {
                        Text("A letter waiting for a handoff can be AirDropped straight to anyone here whose destination matches, or is within \(KnownCarrierDirectory.matchRadiusKm) km of, where it's actually going.")
                    }
                }
                .listRowSeparator(.hidden)

                if mode == .couriers, !gameCenterFriends.isEmpty {
                    Section {
                        ForEach(gameCenterFriends) { friend in
                            Button {
                                name = friend.displayName
                            } label: {
                                Label(friend.displayName, systemImage: "gamecontroller")
                            }
                        }
                    } header: {
                        Text("From Game Center")
                    } footer: {
                        Text("Fills in their name — you still pick where they're headed.")
                    }
                }

                if mode == .couriers, !otherCouriers.isEmpty {
                    Section("Your Couriers") {
                        ForEach(otherCouriers) { carrier in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(carrier.name)
                                    .font(.subheadline.weight(.medium))
                                Text("Heading to \(carrier.destinationCity)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    pendingDelete = carrier
                                    showsDeleteConfirmation = true
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(mode == .myTrip ? LocalizedStringKey("Add a Trip") : LocalizedStringKey("Couriers"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .confirmationDialog("Remove Courier?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let carrier = pendingDelete {
                        withAnimation { directory.remove(carrier) }
                    }
                    pendingDelete = nil
                }
            }
            .sensoryFeedback(.success, trigger: addTick)
            .task {
                if mode == .couriers, name.isEmpty, let prefilledName {
                    name = prefilledName
                }
                guard mode == .couriers, !hasLoadedGameCenterFriends, let gameCenterService else { return }
                hasLoadedGameCenterFriends = true
                gameCenterFriends = await gameCenterService.loadFriends()
            }
        }
    }

    private func add() {
        guard let destinationCoordinate else { return }
        let city = destinationCity.trimmed
        directory.add(
            name: mode == .myTrip ? "You (\(city))" : name.trimmed,
            destinationCity: city,
            destinationCoordinate: RamCoordinate(destinationCoordinate)
        )
        addTick += 1
        if mode == .myTrip {
            dismiss()
            return
        }
        withAnimation(.snappy) {
            name = ""
            destinationCity = ""
            self.destinationCoordinate = nil
        }
        isFormFocused = false
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

#Preview {
    CarrierDirectoryView(directory: .preview)
}
