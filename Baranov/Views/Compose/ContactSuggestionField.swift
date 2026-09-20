//
//  ContactSuggestionField.swift
//  Baranov
//
//  A recipient-name field with live Contacts suggestions, shown as a
//  horizontal row of big picture-forward cards first — the same first
//  impression Messages' own "suggested contacts" strip makes — before
//  narrowing to a specific person. Once someone is picked, their real
//  postal addresses (if any) surface underneath as tappable blocks: for a
//  postal app, "who is this for" and "where is this going" are usually
//  the same question, so picking a contact can settle the destination
//  too via `onAddressSelected`.
//
//  Two ways to pick a recipient live side by side: type a few letters for
//  live card suggestions (needs Contacts access, requested lazily on
//  first focus), or tap the person-plus button to browse the full native
//  Contacts picker (`ContactPickerRepresentable`), which needs no
//  permission at all. Either way, only a display name (and, if chosen, an
//  address string) is ever copied out — no contact data is retained.
//

import Contacts
import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct ContactSuggestionField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String

    /// Fires when the sender taps one of a selected contact's addresses —
    /// hands back both the address text and a resolved coordinate, the
    /// same shape `PlaceSearchField`'s `onSelect` uses, so a caller can
    /// treat it as a destination pick.
    var onAddressSelected: ((String, CLLocationCoordinate2D) -> Void)? = nil

    @State private var service = ContactSuggestionService()
    @State private var isContactPickerPresented = false
    @State private var selectedContact: CNContact?
    @State private var isResolvingAddress = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            inputRow

            if isFocused && !service.results.isEmpty {
                bigContactCards
            }

            if let selectedContact, !selectedContact.formattedPostalAddresses.isEmpty {
                addressBlocks(for: selectedContact)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: service.results.count)
        .animation(.easeInOut(duration: 0.15), value: selectedContact?.identifier)
        // Zero-size `.background`, not `.sheet` — see
        // `ContactPickerRepresentable`'s own doc comment for why: a
        // second real SwiftUI sheet presented from in here (this field
        // lives inside the always-on docked panel sheet) was what
        // actually caused picking a contact to look like it randomly
        // kicked the sender back to Pasture.
        .background(
            ContactPickerRepresentable(
                isPresented: $isContactPickerPresented,
                onPick: { contact in
                    text = contact.suggestedDisplayName
                    selectedContact = contact
                },
                onCancel: {}
            )
            .frame(width: 0, height: 0)
        )
    }

    // MARK: - Input row

    private var inputRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .focused($isFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .onChange(of: text) { _, newValue in
                    service.updateQuery(newValue)
                }

            if !text.isEmpty {
                Button {
                    text = ""
                    selectedContact = nil
                    service.clearResults()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    isContactPickerPresented = true
                } label: {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose from Contacts")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.thinMaterial, in: Capsule())
        .onChange(of: isFocused) { _, focused in
            if focused {
                service.requestAccessIfNeeded()
            }
        }
    }

    // MARK: - Big contact cards

    private var bigContactCards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(service.results.enumerated()), id: \.offset) { _, contact in
                    bigContactCard(contact)
                }
            }
            .padding(.vertical, 2)
        }
        .transition(.opacity)
    }

    private func bigContactCard(_ contact: CNContact) -> some View {
        let isSelected = selectedContact?.identifier == contact.identifier

        return Button {
            select(contact)
        } label: {
            VStack(spacing: 8) {
                contactAvatar(contact, diameter: 64)

                Text(contact.suggestedDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 88)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func contactAvatar(_ contact: CNContact, diameter: CGFloat) -> some View {
        Group {
            if let data = contact.thumbnailImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(diameter * 0.12)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .frame(width: diameter, height: diameter)
        .background(.regularMaterial, in: Circle())
        .clipShape(Circle())
    }

    // MARK: - Address blocks

    /// The selected contact's real postal addresses — specific delivery
    /// points, not just a city name — surfaced as its own set of blocks
    /// underneath, matching `PlaceSearchField`'s suggestion-card look.
    private func addressBlocks(for contact: CNContact) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Address")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(contact.formattedPostalAddresses, id: \.id) { address in
                    Button {
                        Task { await selectAddress(address.text) }
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(.secondary.opacity(0.15))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "mappin")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(address.text)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)

                            Spacer()

                            if isResolvingAddress {
                                ProgressView()
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isResolvingAddress)
                }
            }
        }
    }

    // MARK: - Selection

    private func select(_ contact: CNContact) {
        text = contact.suggestedDisplayName
        selectedContact = contact
        isFocused = false
        service.clearResults()
    }

    /// Resolves a tapped address string to a real coordinate the same way
    /// `PlaceSearchCompleter` resolves a place suggestion — a real MapKit
    /// lookup, not a guess — then hands both up via `onAddressSelected`.
    private func selectAddress(_ addressText: String) async {
        guard let onAddressSelected, !isResolvingAddress else { return }
        isResolvingAddress = true
        defer { isResolvingAddress = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = addressText

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let coordinate = response.mapItems.first?.placemark.location?.coordinate else { return }
            onAddressSelected(addressText, coordinate)
        } catch {
            // Leave the destination untouched — the sender can still pick
            // one normally from the destination search field above.
        }
    }
}

#Preview {
    @Previewable @State var text = ""
    return ContactSuggestionField(placeholder: "Who is this for?", text: $text)
        .padding()
}
