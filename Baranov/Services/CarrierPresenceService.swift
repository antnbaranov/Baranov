//
//  CarrierPresenceService.swift
//  Baranov
//
//  Lets a sender see, on their own map, roughly where the courier carrying
//  their ram is — but only when that courier has said yes.
//
//  Two halves, both offline-first (a failure is silently retried next tick):
//
//  - Publishing (opt-in, OFF by default — Settings → "Share my location with
//    senders"): while this phone carries rams that belong to someone else,
//    it posts a coarse position (~1 km) and the ids of those rams to
//    `POST /telemetry/carrier-presence`. When it carries none, or the switch
//    is turned off, it posts an empty list, which makes the receiver forget
//    it at once. The receiver also expires every entry after 30 minutes.
//
//  - Watching: for the rams this person has handed on, it asks
//    `GET /telemetry/carrier-presence?ram_ids=…` — only ids it names, so
//    nobody can browse couriers, and a ram id is an unguessable UUID.
//
//  A ram that comes from anyone but you counts as "someone else's".
//

import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class CarrierPresenceService {
    struct Sighting: Identifiable, Hashable, Sendable {
        let ramID: UUID
        let carrierName: String
        let latitude: Double
        let longitude: Double
        let lastSeen: Date

        var id: UUID { ramID }
        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    nonisolated static let shareKey = "com.baranov.shareCarrierPresence"

    private(set) var sightings: [Sighting] = []

    @ObservationIgnored private let baseURL: URL
    @ObservationIgnored private let carrierUserID: UUID
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var lastPublishedNonEmpty = false
    @ObservationIgnored private var lastPublishAt = Date.distantPast
    @ObservationIgnored private var lastFetchAt = Date.distantPast

    init(baseURL: URL, carrierUserID: UUID, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.carrierUserID = carrierUserID
        self.session = session
    }

    func sighting(for ramID: UUID) -> Sighting? {
        sightings.first { $0.ramID == ramID }
    }

    /// Call about once a minute while the app is in the foreground.
    func tick(rams: [Ram], myName: String, coordinate: CLLocationCoordinate2D?) async {
        await publish(rams: rams, myName: myName, coordinate: coordinate)
        await fetch(rams: rams)
    }

    // MARK: - Publishing

    private struct PublishBody: Encodable {
        let carrier_user_id: UUID
        let carrier_name: String
        let ram_ids: [UUID]
        let latitude: Double
        let longitude: Double
    }

    private func publish(rams: [Ram], myName: String, coordinate: CLLocationCoordinate2D?) async {
        let sharing = UserDefaults.standard.bool(forKey: Self.shareKey)
        let name = myName.trimmingCharacters(in: .whitespacesAndNewlines)

        let carrying: [UUID] = sharing ? rams.filter { ram in
            guard let sender = ram.letter?.senderName else { return false }
            let isMine = sender.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(name) == .orderedSame
            switch ram.status {
            case .grazing, .walking, .waitingForHandoff, .atSea: return !isMine
            default: return false
            }
        }.map(\.id) : []

        // Nothing to say, and nothing was said before: stay quiet.
        if carrying.isEmpty && !lastPublishedNonEmpty { return }
        guard Date().timeIntervalSince(lastPublishAt) > 90 || (carrying.isEmpty && lastPublishedNonEmpty) else { return }

        // When stopping, any coordinate will do — the receiver just deletes the entry.
        guard let coordinate = coordinate ?? (carrying.isEmpty ? CLLocationCoordinate2D(latitude: 0, longitude: 0) : nil) else { return }

        let body = PublishBody(
            carrier_user_id: carrierUserID,
            carrier_name: String(name.prefix(64)),
            ram_ids: Array(carrying.prefix(20)),
            latitude: (coordinate.latitude * 100).rounded() / 100,
            longitude: (coordinate.longitude * 100).rounded() / 100
        )
        var request = URLRequest(url: baseURL.appending(path: "telemetry/carrier-presence"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try? JSONEncoder().encode(body)

        if let (_, response) = try? await session.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 201 {
            lastPublishedNonEmpty = !carrying.isEmpty
            lastPublishAt = Date()
        }
    }

    // MARK: - Watching

    private struct Reply: Decodable {
        struct Carrier: Decodable {
            let ram_id: UUID
            let carrier_name: String
            let latitude: Double
            let longitude: Double
            let last_seen: String
        }
        let carriers: [Carrier]
    }

    private func fetch(rams: [Ram]) async {
        let watched = rams.filter { $0.status == .handedOff }.map(\.id)
        guard !watched.isEmpty else {
            if !sightings.isEmpty { sightings = [] }
            return
        }
        guard Date().timeIntervalSince(lastFetchAt) > 45 else { return }
        lastFetchAt = Date()

        var components = URLComponents(url: baseURL.appending(path: "telemetry/carrier-presence"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "ram_ids", value: watched.prefix(20).map { $0.uuidString }.joined(separator: ","))]
        guard let url = components?.url else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return }

        sightings = reply.carriers.map { carrier in
            Sighting(
                ramID: carrier.ram_id,
                carrierName: carrier.carrier_name,
                latitude: carrier.latitude,
                longitude: carrier.longitude,
                lastSeen: Date()   // the receiver already drops anything older than 30 minutes
            )
        }
    }
}
