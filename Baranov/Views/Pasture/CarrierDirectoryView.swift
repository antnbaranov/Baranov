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
    let directory: KnownCarrierDirectory
    var gameCenterService: GameCenterService? = nil
    /// A name to start the form with — a Game Center friend tapped in the
    /// Pasture's carriers card lands here with their name already filled.
    var prefilledName: String? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var destinationCity = ""
    @State private var destinationCoordinate: CLLocationCoordinate2D?

    @State private var gameCenterFriends: [GameCenterFriend] = []
    @State private var hasLoadedGameCenterFriends = false

    private var canAdd: Bool {
        !name.trimmed.isEmpty && destinationCoordinate != nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ContactSuggestionField(placeholder: "Their Name", text: $name)

                    PlaceSearchField(placeholder: "Where are they headed?", text: $destinationCity) { title, coordinate in
                        destinationCity = title
                        destinationCoordinate = coordinate
                    }

                    Button {
                        addCarrier()
                    } label: {
                        Label("Add Carrier", systemImage: "person.badge.plus")
                    }
                    .disabled(!canAdd)
                } header: {
                    Text("Add a Carrier")
                } footer: {
                    Text("A letter waiting for a handoff can be AirDropped straight to anyone here whose destination matches, or is within 800 km of, where it's actually going.")
                }
                .listRowSeparator(.hidden)

                if !gameCenterFriends.isEmpty {
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

                if !directory.carriers.isEmpty {
                    Section("Known Carriers") {
                        ForEach(directory.carriers) { carrier in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(carrier.name)
                                    .font(.subheadline.weight(.medium))
                                Text("Heading to \(carrier.destinationCity)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            directory.remove(at: offsets)
                        }
                    }
                }
            }
            .navigationTitle("Carriers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                if name.isEmpty, let prefilledName {
                    name = prefilledName
                }
                guard !hasLoadedGameCenterFriends, let gameCenterService else { return }
                hasLoadedGameCenterFriends = true
                gameCenterFriends = await gameCenterService.loadFriends()
            }
        }
    }

    private func addCarrier() {
        guard let destinationCoordinate else { return }
        directory.add(
            name: name.trimmed,
            destinationCity: destinationCity.trimmed,
            destinationCoordinate: RamCoordinate(destinationCoordinate)
        )
        name = ""
        destinationCity = ""
        self.destinationCoordinate = nil
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

#Preview {
    CarrierDirectoryView(directory: .preview)
}
