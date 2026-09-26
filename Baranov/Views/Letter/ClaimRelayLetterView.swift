//
//  ClaimRelayLetterView.swift
//  Baranov
//
//  The recipient's half of "letter by code": who it's from, where it started,
//  and — the point of the screen — where THEY want the ram to arrive. Home,
//  a campus gate, a park: it's their choice, so nobody has to share an
//  address to send a letter. Move the map under the pin, then send the ram
//  on its way. It walks from the sender's starting point to the chosen spot
//  on this person's own steps.
//
//  System materials and semantic styles only.
//

import CoreLocation
import MapKit
import SwiftUI

struct ClaimRelayLetterView: View {
    @Environment(FlockViewModel.self) private var flockViewModel
    @Environment(LocationService.self) private var locationService

    /// The relay lookup id the letter is filed under.
    let relayID: String
    /// The letter code the person typed, kept on this phone so the same code
    /// opens the seal on arrival. `nil` when the phone already holds it
    /// (a letter that came through the mailbag).
    let code: String?
    let preview: RelayLetterPreview
    let relay: LetterRelayService
    /// Called once the ram has been dispatched; the owner dismisses.
    let onClaimed: () -> Void

    private enum SpotKind: String, CaseIterable, Identifiable {
        case home, campus, park
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .home: "Home"
            case .campus: "Campus"
            case .park: "Park"
            }
        }
        var label: String {
            switch self {
            case .home: String(localized: "Home")
            case .campus: String(localized: "Campus")
            case .park: String(localized: "Park")
            }
        }
        var symbol: String {
            switch self {
            case .home: "house.fill"
            case .campus: "building.columns.fill"
            case .park: "tree.fill"
            }
        }
    }

    @State private var camera: MapCameraPosition = .automatic
    @State private var dropSpot: CLLocationCoordinate2D?
    @State private var placeName = ""
    @State private var kind: SpotKind = .home
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var sentTick = 0

    private var straightLineMeters: Int? {
        guard let dropSpot else { return nil }
        let from = CLLocation(latitude: preview.origin.latitude, longitude: preview.origin.longitude)
        let to = CLLocation(latitude: dropSpot.latitude, longitude: dropSpot.longitude)
        return Int(from.distance(from: to))
    }

    var body: some View {
        Form {
            Section {
                Label("Letter from \(preview.senderName) (\(preview.originName))", systemImage: "envelope.fill")
            }

            Section {
                mapPicker
                    .listRowInsets(EdgeInsets())
                Picker("Kind of place", selection: $kind) {
                    ForEach(SpotKind.allCases) { spot in
                        Label(spot.title, systemImage: spot.symbol).tag(spot)
                    }
                }
            } header: {
                Text("Where should the ram arrive?")
            } footer: {
                Text("Move the map — the pin stays in the middle. Only you see this spot.")
            }

            if !placeName.isEmpty || straightLineMeters != nil {
                Section {
                    if !placeName.isEmpty {
                        Label(placeName, systemImage: "mappin.and.ellipse")
                    }
                    if let meters = straightLineMeters {
                        Label("About \(DistanceFormatter.string(forMeters: meters)) as the crow flies", systemImage: "figure.walk")
                    }
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .navigationTitle("Choose Where It Arrives")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { sendBar }
        .sensoryFeedback(.success, trigger: sentTick)
        .onAppear(perform: centerOnUser)
    }

    // MARK: - Map

    private var mapPicker: some View {
        ZStack {
            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                UserAnnotation()
            }
            .mapStyle(.standard)
            .onMapCameraChange(frequency: .onEnd) { context in
                dropSpot = context.region.center
                Task { await resolveName(for: context.region.center) }
            }

            Image(systemName: "mappin")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .offset(y: -17)
                .allowsHitTesting(false)
        }
        .frame(height: 260)
        .overlay(alignment: .bottomTrailing) {
            Button(action: centerOnUser) {
                Image(systemName: "location.fill").padding(10)
            }
            .background(.regularMaterial, in: Circle())
            .padding(10)
            .accessibilityLabel("My location")
        }
    }

    private func centerOnUser() {
        locationService.resolveCurrentLocation()
        if let here = locationService.currentCoordinate {
            camera = .region(MKCoordinateRegion(center: here, latitudinalMeters: 1500, longitudinalMeters: 1500))
        }
    }

    private func resolveName(for coordinate: CLLocationCoordinate2D) async {
        let pin = await DroppedDestination.resolve(coordinate)
        placeName = pin.name
    }

    // MARK: - Send

    private var sendBar: some View {
        Button {
            Task { await sendRamOnItsWay() }
        } label: {
            Group {
                if isWorking {
                    ProgressView()
                } else {
                    Label("Send the Ram on Its Way", systemImage: "figure.walk.departure")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(Color.wax)
        .disabled(dropSpot == nil || isWorking)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func sendRamOnItsWay() async {
        guard let dropSpot else { return }
        errorMessage = nil

        let letter = preview.payload
        guard !flockViewModel.activeRams.contains(where: { $0.letter?.id == letter.id }) else {
            errorMessage = String(localized: "You already claimed this letter.")
            return
        }
        guard flockViewModel.hasFreeRamSlot else {
            errorMessage = String(localized: "Your pasture is full. Free a slot or expand the pasture, then try again.")
            return
        }

        isWorking = true
        defer { isWorking = false }

        let origin = preview.originCoordinate
        let dropName = placeName.isEmpty ? kind.label : "\(kind.label) · \(placeName)"
        let ramName = (preview.ramName?.isEmpty == false ? preview.ramName : nil) ?? String(localized: "Courier")

        // Same routing rules as sending a letter: a road all the way if there
        // is one, otherwise walk to the nearest port and wait for a crossing.
        let leg: ResolvedRoute
        var legEndName = dropName
        var needsHandoff = false
        do {
            leg = try await RouteService.drivingRoute(from: origin, to: dropSpot)
        } catch RouteResolutionError.noDrivableRoute {
            guard let plan = await HandoffGatewayService.plan(from: origin, toward: dropSpot) else {
                errorMessage = String(localized: "No road or nearby port connects those two places.")
                return
            }
            leg = plan.leg
            legEndName = plan.gateway.name
            needsHandoff = true
        } catch {
            errorMessage = String(localized: "Couldn't work out a route right now. Check your connection and try again.")
            return
        }

        // Tell the post office first: if that fails nothing has been spent locally.
        do {
            try await relay.claim(id: relayID, dropSpot: dropSpot)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
            return
        }
        // One code, both jobs: keep it so the wax seal opens on arrival
        // without asking for it a second time.
        if let code, letter.isEncrypted {
            SealKeyVault.store(code, for: letter.id)
        }

        let ram = Ram(
            name: ramName,
            totalStepsRequired: leg.distanceMeters,
            currentCity: preview.originName,
            targetCity: dropName,
            legDestinationCity: legEndName,
            routeHistory: [RouteNode(
                cityName: preview.originName,
                latitude: origin.latitude,
                longitude: origin.longitude,
                carrierName: ramName,
                stepsContributed: 0
            )],
            routeCoordinates: leg.coordinates,
            requiresHandoffAtLegEnd: needsHandoff,
            letter: letter,
            finalDestinationCoordinate: RamCoordinate(dropSpot)
        )

        guard flockViewModel.dispatch(ram) else {
            errorMessage = String(localized: "Your pasture is full. Free a slot or expand the pasture, then try again.")
            return
        }
        SoundEffectPlayer.shared.play(.dispatchWhoosh)
        sentTick += 1
        onClaimed()
    }
}
