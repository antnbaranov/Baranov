//
//  SavedCourierDetailView.swift
//  Baranov
//
//  A saved courier's page: when and where you first met (recorded
//  automatically when you saved them), where they're headed, and a free note.
//  System Form and semantic styles only.
//

import SwiftUI

struct SavedCourierDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SavedCourierStore.self) private var store

    let courierID: UUID
    @State private var note = ""
    @State private var showsRemoveConfirmation = false

    private var courier: SavedCourier? {
        store.couriers.first { $0.id == courierID }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let courier {
                    Section {
                        HStack(spacing: 14) {
                            CourierAvatarView(image: nil, name: courier.name, diameter: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(courier.name).font(.title3.weight(.semibold))
                                Text(courier.tripCity.isEmpty
                                     ? LocalizedStringKey("Open to carry")
                                     : LocalizedStringKey("Heading to \(courier.tripCity)"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section("First met") {
                        LabeledContent("When", value: courier.savedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: .appLanguage)))
                        if let place = courier.metPlace {
                            LabeledContent("Where", value: place)
                        }
                    }

                    Section("Notes") {
                        TextField("Where you talked, what they carry, anything worth remembering",
                                  text: $note, axis: .vertical)
                            .lineLimit(5...12)
                    }

                    Section {
                        Button("Remove from saved couriers", role: .destructive) {
                            showsRemoveConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(courier?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { note = courier?.note ?? "" }
            .onChange(of: note) { _, newValue in
                store.setNote(newValue, for: courierID)
            }
            .alert("Remove from saved couriers?", isPresented: $showsRemoveConfirmation, presenting: courier) { courier in
                Button("Remove", role: .destructive) {
                    store.remove(name: courier.name)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: { courier in
                Text("You won't see \(courier.name) as a saved courier anymore. Their trip note and first-met details go with them.")
            }
        }
    }
}
