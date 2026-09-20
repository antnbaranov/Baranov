//
//  CouriersView.swift
//  Baranov
//
//  The courier's profile screen, opened from the always-visible button on the
//  Journey map. It opens on the couriers themselves — a paging stack of
//  profile cards (portrait, status, route, steps, stamps, letters
//  carried) — then the passive "receiving" state (radar + who's sending
//  nearby), Share Receiving Code, and who can carry the selected ram
//  onward (matched carriers, Game Center friends, calendar trips). Presented by `RootView` as a sheet,
//  the same one-owner-per-modal rule Pasture follows.
//

import SwiftUI
import UIKit

struct CouriersView: View {
    @Environment(FlockViewModel.self) private var flockViewModel
    @Environment(LocationService.self) private var locationService
    @Environment(\.dismiss) private var dismiss

    @AppStorage("com.baranov.carrierDisplayName") private var carrierDisplayName = ""
    @AppStorage(AppAppearance.storageKey) private var appAppearanceRawValue = AppAppearance.system.rawValue

    @State private var carrierDirectory = KnownCarrierDirectory()
    @State private var calendarService = CalendarTripSuggestionService()
    private var gameCenterService: GameCenterService { .shared }
    @State private var ramCompanionStore = RamCompanionStore()
    @State private var gameCenterFriends: [GameCenterFriend] = []
    @State private var carrierPrefillName: String?
    @State private var isCarrierDirectoryPresented = false
    @State private var discovery = ProximityCodeDiscovery()
    @State private var avatarStore = CourierAvatarStore()
    @State private var codeStore = CourierCodeStore()
    @State private var isMemojiPickerPresented = false
    @State private var isRenamePresented = false
    @State private var copiedTick = 0

    /// Kept for the owner's call site; the profile screen no longer opens letters itself.
    var onOpenLetter: (Ram, String?) -> Void = { _, _ in }

    private var selectedRam: Ram? {
        flockViewModel.activeRams.first { $0.id == flockViewModel.selectedRamId }
            ?? flockViewModel.activeRams.first
    }

    private var appAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRawValue) ?? .system
    }

    private var addedTripSuggestionIDs: Set<UUID> {
        let carrierNames = Set(carrierDirectory.carriers.map(\.name))
        return Set(
            calendarService.suggestions
                .filter { carrierNames.contains("You (\($0.title))") }
                .map(\.id)
        )
    }

    private var displayName: String {
        let trimmed = carrierDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Courier") : trimmed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    profileHeader
                    courierCodeCard

                    AirDropSuggestionsCard(
                        ram: selectedRam,
                        matchedCarriers: selectedRam.map { carrierDirectory.matches(for: $0) } ?? [],
                        tripSuggestions: calendarService.suggestions,
                        onAddTripAsCarrier: { suggestion in
                            carrierDirectory.add(
                                name: "You (\(suggestion.title))",
                                destinationCity: suggestion.displayName,
                                destinationCoordinate: suggestion.coordinate
                            )
                        },
                        companionName: ramCompanionStore.companion?.name,
                        addedSuggestionIDs: addedTripSuggestionIDs,
                        friends: gameCenterFriends,
                        onFriendTapped: { friend in
                            carrierPrefillName = friend.displayName
                            isCarrierDirectoryPresented = true
                        },
                        knownCarrierCount: carrierDirectory.carriers.count,
                        onManageTapped: { isCarrierDirectoryPresented = true },
                        senderName: carrierDisplayName
                    )
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isCarrierDirectoryPresented = true } label: { Image(systemName: "person.2") }
                        .accessibilityLabel("Carriers")
                }
            }
            .sheet(isPresented: $isCarrierDirectoryPresented, onDismiss: { carrierPrefillName = nil }) {
                CarrierDirectoryView(
                    directory: carrierDirectory,
                    gameCenterService: gameCenterService,
                    prefilledName: carrierPrefillName
                )
                .preferredColorScheme(appAppearance.colorScheme)
            }
            .sheet(isPresented: $isMemojiPickerPresented) {
                MemojiPickerSheet { data in
                    Task { await avatarStore.set(from: data) }
                }
                .preferredColorScheme(appAppearance.colorScheme)
            }
            .sheet(isPresented: $isRenamePresented) {
                NameEditSheet(name: displayName == String(localized: "Courier") ? "" : displayName) { newName in
                    carrierDisplayName = newName
                }
                .preferredColorScheme(appAppearance.colorScheme)
            }
            .refreshable {
                if let coordinate = locationService.currentCoordinate {
                    await calendarService.refresh(near: coordinate)
                } else {
                    locationService.resolveCurrentLocation()
                }
            }
            .onDisappear { discovery.stop() }
            .task {
                gameCenterService.authenticateIfNeeded()
                locationService.resolveCurrentLocation()
                if let coordinate = locationService.currentCoordinate, calendarService.lastRefreshedAt == nil {
                    await calendarService.refresh(near: coordinate)
                }
                gameCenterFriends = await gameCenterService.loadFriends()
            }
        }
    }

    // MARK: - Profile header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            Button { isMemojiPickerPresented = true } label: {
                CourierAvatarView(image: avatarStore.image, name: displayName, diameter: 112)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "face.smiling")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .background(.regularMaterial, in: Circle())
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change Memoji")
            .contextMenu {
                if avatarStore.image != nil {
                    Button("Remove Memoji", systemImage: "trash", role: .destructive) { avatarStore.remove() }
                }
            }

            Button {
                isRenamePresented = true
            } label: {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Image(systemName: "pencil")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Name, \(displayName)"))
            .accessibilityHint(Text("Double tap to change"))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Courier code

    /// The courier's permanent code: shown at once, big and selectable, for
    /// receiving mail and transfers. Tap to copy; hand it over by message or
    /// to a phone nearby.
    private var courierCodeCard: some View {
        let code = codeStore.code
        return VStack(spacing: 14) {
            Label("Your Code", systemImage: "number")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                UIPasteboard.general.string = code
                copiedTick += 1
            } label: {
                Text(code)
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .kerning(2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Your code \(code)"))
            .accessibilityHint(Text("Double tap to copy"))
            .sensoryFeedback(.success, trigger: copiedTick)

            Text(copiedTick > 0 ? LocalizedStringKey("Copied") : LocalizedStringKey("Tap to copy. Use it to receive mail and transfers."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                ShareLink(item: String(localized: "My Baranov code: \(code)")) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(ShareCodeGlassButtonStyle(expands: true))

                Button {
                    if discovery.isBroadcasting {
                        discovery.stopBroadcasting()
                    } else {
                        discovery.startBroadcasting(code: code)
                    }
                } label: {
                    Label(discovery.isBroadcasting ? "Stop" : "Nearby",
                          systemImage: discovery.isBroadcasting ? "stop.fill" : "wave.3.right")
                }
                .buttonStyle(ShareCodeGlassButtonStyle(expands: true))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Name editor

private struct NameEditSheet: View {
    let name: String
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $draft)
                    .focused($focused)
                    .textContentType(.name)
                    .submitLabel(.done)
                    .onSubmit(save)
            }
            .navigationTitle("Your Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .disabled(trimmed.isEmpty)
                        .accessibilityLabel("Done")
                }
            }
            .onAppear { draft = name; focused = true }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}
