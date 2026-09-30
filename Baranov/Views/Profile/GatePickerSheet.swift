//
//  GatePickerSheet.swift
//  Baranov
//
//  "Choose another town": sets the gate by hand, for a person whose home
//  isn't where the phone happens to be. One search field with live place
//  suggestions; picking a suggestion moves the gate there (town-level,
//  rounded to about 1 km by `LetterGate`, like the automatic one).
//

import CoreLocation
import SwiftUI

struct GatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Called with the chosen town and its point.
    var onPick: (String, CLLocationCoordinate2D) -> Void

    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Search for the town letters to you should walk to. Only the town is shared.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    PlaceSearchField(placeholder: "Search for a town", text: $query) { name, coordinate in
                        onPick(name, coordinate)
                        dismiss()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Your gate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
