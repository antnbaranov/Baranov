//
//  ProfileView.swift
//  Baranov
//
//  Who you are as a courier, and nothing else: a shepherd portrait, a name and a
//  creed you can edit, your permanent postal code (to share, or to broadcast to a phone
//  nearby), and the trips you'll be making — the ones that make you a
//  natural carrier for other people's letters.
//
//  Everything about mail in transit lives in the mailbag drawer on the map,
//  receiving a letter starts from the "Enter Code" button above the map, and
//  the shepherd's side (rams, rankings, settings) is Pasture. So there are
//  no rams lists, code-entry fields or how-it-works paragraphs here.
//
//  Presented by `RootView` as a sheet, the same one-owner-per-modal rule
//  Pasture follows. System materials and semantic styles only.
//

import MapKit
import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(LocationService.self) private var locationService
    @Environment(\.dismiss) private var dismiss
    @State private var gateMovedTick = 0
    /// Set when the button was tapped before the phone had a fix; the gate moves as soon as one arrives.
    @State private var gateAwaitingFix = false
    @State private var isPickingGate = false

    @AppStorage("com.baranov.carrierDisplayName") private var carrierDisplayName = ""

    @State private var codeStore = CourierCodeStore()
    @State private var discovery = ProximityCodeDiscovery()
    @State private var carrierDirectory = KnownCarrierDirectory()
    @State private var calendarService = CalendarTripSuggestionService()

    @State private var isAddingTrip = false
    @State private var tripQuery = ""
    @Environment(NearbyCourierService.self) private var nearby
    @Environment(SavedCourierStore.self) private var savedCouriers
    /// The courier whose card is open (see `NearbyCourierCard`).
    @State private var selectedCourier: NearbyCourier?
    /// The saved courier whose notes page is open.
    @State private var detailCourier: SavedCourier?
    @State private var pendingCourierRemoval: SavedCourier?
    /// `nil` when there is no ram to hand over right now.
    private let onHandOver: ((NearbyCourier) -> Void)?
    /// Opens Compose with the courier's trip destination filled in.
    private let onSendLetter: ((NearbyCourier) -> Void)?
    @AppStorage("com.baranov.openToCarry") private var openToCarry = false
    @State private var copiedTick = 0
    @AppStorage(NearbyCourierService.introSeenKey) private var nearbyIntroSeen = false
    @State private var isShowingNearbyIntro = false

    init(onHandOver: ((NearbyCourier) -> Void)? = nil, onSendLetter: ((NearbyCourier) -> Void)? = nil) {
        self.onHandOver = onHandOver
        self.onSendLetter = onSendLetter
    }

    private var displayName: String {
        let trimmed = carrierDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Courier", bundle: .appLanguage, locale: .appLanguage) : trimmed
    }

    // MARK: - Trips

    /// Trips the person has already registered as a carrier: entries added
    /// from the calendar ("You (Conference)") or by hand under their own name.
    private var registeredTrips: [KnownCarrier] {
        carrierDirectory.carriers.filter { $0.name.hasPrefix("You (") || $0.name == displayName }
    }

    private var registeredTripNames: Set<String> {
        Set(carrierDirectory.carriers.map(\.name))
    }

    /// Calendar trips not registered yet — one tap adds them.
    private var pendingSuggestions: [TripSuggestion] {
        calendarService.suggestions.filter { !registeredTripNames.contains("You (\($0.title))") }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ProfileHeaderView()
                    courierCodeCard
                    gateCard
                    nearbyCouriersCard
                    savedCouriersCard
                    tripsCard
                }
                .padding(.vertical, 8)
            }
            .symbolVariant(.fill)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            .refreshable { await refreshTrips() }
            .overlay(alignment: .top) {
                if let courier = selectedCourier {
                    NearbyCourierCard(
                        courier: courier,
                        isSaved: savedCouriers.isSaved(name: courier.name),
                        onToggleSave: { savedCouriers.toggle(courier, at: locationService.currentCoordinate) },
                        onHandOver: onHandOver.map { handOver in
                            {
                                selectedCourier = nil
                                dismiss()
                                handOver(courier)
                            }
                        },
                        onSendLetter: onSendLetter.map { sendLetter in
                            {
                                selectedCourier = nil
                                dismiss()
                                sendLetter(courier)
                            }
                        },
                        onClose: { withAnimation(.snappy) { selectedCourier = nil } }
                    )
                    .padding(.top, 8)
                }
            }
            .sheet(item: $detailCourier) { saved in
                SavedCourierDetailView(courierID: saved.id)
                    .environment(savedCouriers)
            }
            .alert("Remove from saved couriers?", isPresented: Binding(
                get: { pendingCourierRemoval != nil },
                set: { if !$0 { pendingCourierRemoval = nil } }
            ), presenting: pendingCourierRemoval) { saved in
                Button("Remove", role: .destructive) {
                    withAnimation(.snappy) { savedCouriers.remove(name: saved.name) }
                    pendingCourierRemoval = nil
                }
                Button("Cancel", role: .cancel) { pendingCourierRemoval = nil }
            } message: { saved in
                Text("You won't see \(saved.name) as a saved courier anymore. Their trip note and first-met details go with them.")
            }
            .onChange(of: nearby.couriers) { _, couriers in
                if let selected = selectedCourier, !couriers.contains(selected) {
                    withAnimation(.snappy) { selectedCourier = nil }
                }
            }
            .task {
                if !nearbyIntroSeen { isShowingNearbyIntro = true }
            }
            .sheet(isPresented: $isShowingNearbyIntro) {
                NearbyIntroSheet {
                    nearbyIntroSeen = true
                    nearby.start(announce: nil)
                } onSkip: {
                    nearbyIntroSeen = true
                }
            }
            .onDisappear {
                discovery.stop()
                // Stop advertising this device once Profile isn't open to
                // read it — browsing (what fills this screen's and the
                // main map's courier markers) keeps running for as long
                // as the app is active.
                nearby.start(announce: nil)
            }
            .onChange(of: openToCarry) { restartNearby() }
            .task {
                locationService.resolveCurrentLocation()
                restartNearby()
                if calendarService.lastRefreshedAt == nil { await refreshTrips() }
            }
        }
    }

    private func restartNearby() {
        nearby.start(announce: openToCarry
                     ? (name: displayName,
                        tripCity: registeredTrips.first?.destinationCity ?? "",
                        trip: registeredTrips.first?.destinationCoordinate)
                     : nil)
    }

    private func refreshTrips() async {
        if let coordinate = locationService.currentCoordinate {
            await calendarService.refresh(near: coordinate)
        } else {
            locationService.resolveCurrentLocation()
        }
    }

    // MARK: - Postal code card

    /// The courier's permanent code: shown at once, big and selectable.
    /// Tap to copy; hand it over by message, or to a phone nearby.
    private var courierCodeCard: some View {
        let code = codeStore.code
        return VStack(spacing: 14) {
            Label("Your address", systemImage: "number")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                UIPasteboard.general.string = code
                copiedTick += 1
            } label: {
                Text(code)
                    .scaledFont(size: 40, weight: .semibold, design: .monospaced)
                    .kerning(2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Your Shepherd ID \(code)"))
            .accessibilityHint(Text("Double tap to copy"))
            .sensoryFeedback(.success, trigger: copiedTick)

            Text(copiedTick > 0
                 ? LocalizedStringKey("Copied")
                 : LocalizedStringKey("Share your Shepherd ID so friends can send you letters. They arrive in your mailbag."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            HStack(spacing: 10) {
                ShareLink(item: String(localized: "Send me a letter on Baranov. My Shepherd ID: \(code)", bundle: .appLanguage, locale: .appLanguage)) {
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
                          systemImage: discovery.isBroadcasting ? "stop.fill" : "wave.3.forward")
                }
                .buttonStyle(ShareCodeGlassButtonStyle(expands: true))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Gate

    /// Where letters to this Shepherd ID walk. Town-level, set from where
    /// the phone first was; movable to where it is now.
    private var gateCard: some View {
        let gate = GateStore.shared.gate
        return VStack(alignment: .leading, spacing: 10) {
            Label("Your gate", systemImage: "signpost.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(gate?.city ?? String(localized: "Not set yet", bundle: .appLanguage, locale: .appLanguage))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Letters sent to your Shepherd ID walk here, on the sender's steps. Only the town is shared.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: moveGateHere) {
                Label(gate == nil ? "Set my gate here" : "Move my gate here", systemImage: "location")
            }
            .buttonStyle(ShareCodeGlassButtonStyle(expands: true))

            Button { isPickingGate = true } label: {
                Label("Choose another town", systemImage: "magnifyingglass")
            }
            .buttonStyle(ShareCodeGlassButtonStyle(expands: true))
            .sensoryFeedback(.success, trigger: gateMovedTick)
            .sheet(isPresented: $isPickingGate) {
                GatePickerSheet { name, coordinate in
                    gateAwaitingFix = false
                    GateStore.shared.move(to: coordinate, city: name)
                    gateMovedTick += 1
                }
            }
            .onChange(of: locationService.currentCoordinate?.latitude) { _, _ in applyGateIfAwaiting() }
            .onChange(of: locationService.currentCityName) { _, _ in applyGateIfAwaiting() }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }

    /// Moves the gate to where the phone is. With no fix yet it asks for one
    /// and finishes by itself when it lands; with location off it opens Settings.
    private func moveGateHere() {
        if locationService.authorizationDenied, locationService.currentCoordinate == nil {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            return
        }
        gateAwaitingFix = true
        locationService.resolveCurrentLocation()
        applyGateIfAwaiting()
    }

    private func applyGateIfAwaiting() {
        guard gateAwaitingFix, let here = locationService.currentCoordinate else { return }
        GateStore.shared.move(to: here, city: locationService.currentCityName)
        gateMovedTick += 1
        // Keep listening until the town name resolves, then stop.
        if let name = locationService.currentCityName, !name.isEmpty,
           name != String(localized: "Current Location", bundle: .appLanguage, locale: .appLanguage) {
            gateAwaitingFix = false
        }
    }

    // MARK: - Nearby couriers

    /// Couriers within Bluetooth range. Multipeer knows who is close, not
    /// where, so they are placed inside the range ring around you.
    private var nearbyCouriersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Couriers Nearby", systemImage: "person.2.wave.2")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Other shepherds close enough to hand a ram to")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            nearbyMap

            ForEach(nearby.couriers) { courier in
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.snappy) { selectedCourier = courier }
                    } label: {
                        HStack(spacing: 12) {
                            CourierAvatarView(image: nil, name: courier.name, diameter: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(courier.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(courier.tripCity.isEmpty
                                     ? LocalizedStringKey("Open to carry")
                                     : LocalizedStringKey("Heading to \(courier.tripCity)"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    let isSaved = savedCouriers.isSaved(name: courier.name)
                    Button { savedCouriers.toggle(courier, at: locationService.currentCoordinate) } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(isSaved ? Color.accentColor : Color.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSaved ? Text("Remove from saved couriers") : Text("Save courier"))
                }
            }

            Toggle(isOn: $openToCarry) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open to carry")
                        .font(.subheadline.weight(.medium))
                    Text("Nearby senders see your name and first trip while this screen is open. Never your position.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(Color.accentColor)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
        .sensoryFeedback(.selection, trigger: nearby.couriers.count)
    }

    private static let rangeMeters: CLLocationDistance = 100

    @ViewBuilder
    private var nearbyMap: some View {
        if let center = locationService.currentCoordinate {
            Map(initialPosition: .camera(MapCamera(centerCoordinate: center, distance: 450)),
                interactionModes: []) {
                UserAnnotation()
                MapCircle(center: center, radius: Self.rangeMeters)
                    .foregroundStyle(.tint.opacity(0.12))
                    .stroke(.tint, lineWidth: 1)
                ForEach(nearby.couriers) { courier in
                    Annotation(courier.name, coordinate: courier.placed(around: center)) {
                        NearbyCourierMarker(courier: courier, diameter: 34) {
                            withAnimation(.snappy) { selectedCourier = courier }
                        }
                    }
                    .annotationTitles(.visible)
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                if nearby.couriers.isEmpty {
                    Text("Nobody in range yet")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            .accessibilityLabel(Text("Map of couriers nearby"))
        } else {
            Text("Waiting for your location")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Saved couriers

    /// Couriers you chose to keep. Tapping one who is in range right now opens the same card as the map.
    @ViewBuilder
    private var savedCouriersCard: some View {
        if !savedCouriers.couriers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Saved couriers", systemImage: "bookmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(savedCouriers.couriers) { saved in
                    let nearbyNow = nearby.couriers.first {
                        $0.name.caseInsensitiveCompare(saved.name) == .orderedSame
                    }
                    HStack(spacing: 12) {
                        Button {
                            detailCourier = saved
                        } label: {
                            HStack(spacing: 12) {
                                CourierAvatarView(image: nil, name: saved.name, diameter: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(saved.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    savedSubtitle(saved, nearbyNow: nearbyNow)
                                        .lineLimit(1)
                                        .font(.caption)
                                        .foregroundStyle(nearbyNow != nil ? Color.accentColor : Color.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            pendingCourierRemoval = saved
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Remove from saved couriers"))
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 16)
        }
    }

    /// "Nearby now", else the first thing you wrote about them, else where or when you first met.
    private func savedSubtitle(_ saved: SavedCourier, nearbyNow: NearbyCourier?) -> Text {
        if nearbyNow != nil { return Text("Nearby now") }
        let note = saved.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { return Text(verbatim: note) }
        if let place = saved.metPlace { return Text("Met in \(place)") }
        return Text("Met \(saved.savedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: .appLanguage)))")
    }

    // MARK: - Trips card

    private var tripsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("My Trips", systemImage: "airplane")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Become a companion for letters along your travels")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if !isAddingTrip {
                    Button {
                        withAnimation(.snappy) { isAddingTrip = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .glassIconButton()
                    .accessibilityLabel("Add Trip")
                    .transition(.opacity)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(registeredTrips) { trip in
                        tripChip(
                            title: trip.destinationCity,
                            symbol: "checkmark",
                            onTap: nil,
                            onRemove: { withAnimation(.snappy) { carrierDirectory.remove(trip) } }
                        )
                    }
                    ForEach(pendingSuggestions) { suggestion in
                        tripChip(
                            title: suggestion.displayName,
                            symbol: "calendar",
                            onTap: {
                                withAnimation(.snappy) {
                                    carrierDirectory.add(
                                        name: "You (\(suggestion.title))",
                                        destinationCity: suggestion.displayName,
                                        destinationCoordinate: suggestion.coordinate
                                    )
                                }
                            },
                            onRemove: { withAnimation(.snappy) { calendarService.dismiss(suggestion) } }
                        )
                    }
                }
            }
            .animation(.snappy, value: registeredTrips.count + pendingSuggestions.count)

            if isAddingTrip {
                HStack(alignment: .top, spacing: 12) {
                    PlaceSearchField(placeholder: "Where are you headed?", text: $tripQuery) { title, coordinate in
                        addTrip(city: title, coordinate: coordinate)
                    }
                    Button("Cancel") {
                        withAnimation(.snappy) {
                            isAddingTrip = false
                            tripQuery = ""
                        }
                    }
                    .font(.body)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .frame(height: 44)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
        .sensoryFeedback(.success, trigger: registeredTrips.count)
    }

    private func addTrip(city: String, coordinate: CLLocationCoordinate2D) {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(.snappy) {
            if !registeredTripNames.contains("You (\(trimmed))") {
                carrierDirectory.add(
                    name: "You (\(trimmed))",
                    destinationCity: trimmed,
                    destinationCoordinate: RamCoordinate(coordinate)
                )
            }
            isAddingTrip = false
            tripQuery = ""
        }
    }

    /// A trip chip with an always-visible remove button. Tapping the label
    /// adds a suggested trip; the trailing xmark removes (or dismisses) it.
    private func tripChip(
        title: String,
        symbol: String,
        onTap: (() -> Void)?,
        onRemove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Button { onTap?() } label: {
                HStack(spacing: 4) {
                    Image(systemName: symbol)
                    Text(title).lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .allowsHitTesting(onTap != nil)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove trip")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.vertical, 4)
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .background(.thinMaterial, in: Capsule())
        .contextMenu {
            Button("Remove trip", systemImage: "trash", role: .destructive, action: onRemove)
        }
    }
}

/// Shown once, the first time Profile opens, before iOS asks for Local Network access.
private struct NearbyIntroSheet: View {
    let onContinue: () -> Void
    let onSkip: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            Image(systemName: "wave.3.forward")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Find shepherds nearby")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Baranov looks for other shepherds close to you over Wi‑Fi and Bluetooth, so a ram or a code can reach you without the internet. iOS will ask next to let Baranov find devices on your local network.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                Button {
                    onContinue()
                    dismiss()
                } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(ShareCodeGlassButtonStyle(tint: .accentColor, expands: true))
                Button {
                    onSkip()
                    dismiss()
                } label: {
                    Text("Not now").frame(maxWidth: .infinity)
                }
                .buttonStyle(ShareCodeGlassButtonStyle(expands: true))
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }
}

#Preview {
    ProfileView()
        .environment(LocationService())
        .environment(SavedCourierStore())
}
