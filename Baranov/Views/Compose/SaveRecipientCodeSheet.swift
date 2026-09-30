//
//  SaveRecipientCodeSheet.swift
//  Baranov
//
//  Saves a Shepherd ID for next time: a name (required), and two optional
//  fields purely for the sender's own memory — where they met, and a
//  note. Nothing here is sent anywhere or shown to the recipient.
//

import CoreLocation
import SwiftUI

struct SaveRecipientCodeSheet: View {
    let code: String
    /// A name to start from (say, what is already in "Who is this for?"). Editable.
    var suggestedName = ""
    /// A saved code being edited: every field starts from it.
    var existing: SavedRecipientCode?
    let onSave: (_ name: String, _ locationName: String?, _ locationCoordinate: CLLocationCoordinate2D?, _ notes: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var locationName = ""
    @State private var locationCoordinate: CLLocationCoordinate2D?
    @State private var notes = ""
    @FocusState private var isNameFocused: Bool

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Shepherd ID") {
                        Text(code)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField("Name", text: $name)
                        .focused($isNameFocused)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Who is this?")
                }

                Section {
                    PlaceSearchField(
                        placeholder: "Where you met, or where you hand off",
                        text: $locationName,
                        onSelect: { title, coordinate in
                            locationName = title
                            locationCoordinate = coordinate
                        },
                        onClear: {
                            locationCoordinate = nil
                        }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Location (optional)")
                }

                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Notes (optional)")
                }
            }
            .navigationTitle(existing == nil ? LocalizedStringKey("Save this code") : LocalizedStringKey("Edit saved code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if #available(iOS 26.0, *) {
                        Button(role: .close) { dismiss() }
                    } else {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Cancel")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            name,
                            locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : locationName,
                            locationCoordinate,
                            notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if let existing {
                    name = existing.name
                    locationName = existing.locationName ?? ""
                    locationCoordinate = existing.locationCoordinate?.clLocationCoordinate
                    notes = existing.notes ?? ""
                } else if name.isEmpty {
                    name = suggestedName
                }
                isNameFocused = existing == nil && name.isEmpty
            }
        }
        .presentationDetents([.medium, .large])
    }
}
