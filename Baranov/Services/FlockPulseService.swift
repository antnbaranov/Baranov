//
//  FlockPulseService.swift
//  Baranov
//
//  The only way other people are ever visible in this app: as a count,
//  never as a dot.
//
//  A ram's polyline starts at a real sender's doorstep and ends at a real
//  recipient's, so plotting other players' rams on the map would be
//  plotting strangers' home addresses. This service reads an aggregate
//  instead — how many rams are walking right now, and roughly which
//  regions they are walking in — from the same ACIT3855 receiver the app
//  already posts `flock-metric` snapshots to. Nothing it fetches can be
//  resolved back to a person, a letter, or a household: a region is a
//  named area with a count, and the count is all that is drawn.
//
//  Reading it is a `GET /telemetry/flock-pulse` against the receiver's own
//  base URL — the read-side counterpart of the metrics the client already
//  writes, which is what lets the coursework's receiver do real product
//  work instead of sitting off to one side collecting numbers nobody sees.
//
//  Offline-first like every other network path here: a receiver that
//  isn't running, isn't reachable, or doesn't implement this endpoint yet
//  leaves `activeRams` at 0 and `regions` empty, and every piece of UI
//  that reads this service simply doesn't render. There is no error
//  state, because there is nothing a person could do about it.
//

import Foundation
import Observation

@Observable
@MainActor
final class FlockPulseService {

    /// A coarse, named area with rams moving in it — a province, state or
    /// metro area, resolved server-side. Deliberately not a precise point:
    /// the coordinate is the region's own center, shared by every ram
    /// counted in it.
    struct Region: Identifiable, Hashable, Sendable {
        let name: String
        let coordinate: RamCoordinate
        let activeRams: Int

        var id: String { name }
    }

    private(set) var activeRams = 0
    private(set) var activeCarriers = 0
    private(set) var regions: [Region] = []
    private(set) var lastUpdatedAt: Date?

    /// Whether there is anything real to show. False before the first
    /// successful fetch, and false whenever the honest answer is "nobody
    /// else is out right now" — an empty social surface is worse than no
    /// social surface, so the UI hides itself rather than printing a 0.
    var hasPulse: Bool {
        lastUpdatedAt != nil && activeRams > 0
    }

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Wire payload

    private struct PulsePayload: Decodable {
        struct RegionPayload: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let activeRams: Int

            enum CodingKeys: String, CodingKey {
                case name, latitude, longitude
                case activeRams = "active_rams"
            }
        }

        let activeRams: Int
        let activeCarriers: Int
        let regions: [RegionPayload]

        enum CodingKeys: String, CodingKey {
            case activeRams = "active_rams"
            case activeCarriers = "active_carriers"
            case regions
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            activeRams = try container.decodeIfPresent(Int.self, forKey: .activeRams) ?? 0
            activeCarriers = try container.decodeIfPresent(Int.self, forKey: .activeCarriers) ?? 0
            regions = try container.decodeIfPresent([RegionPayload].self, forKey: .regions) ?? []
        }
    }

    // MARK: - Public API

    /// Fetches one snapshot. Never throws: a failure leaves the last known
    /// values in place rather than blanking the UI on a single dropped
    /// request, and the very first failure simply leaves `hasPulse` false.
    func refresh() async {
        var request = URLRequest(url: baseURL.appendingPathComponent("telemetry/flock-pulse"))
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                log("GET flock-pulse returned status \(httpResponse.statusCode)")
                return
            }

            let payload = try JSONDecoder().decode(PulsePayload.self, from: data)

            activeRams = max(0, payload.activeRams)
            activeCarriers = max(0, payload.activeCarriers)
            // A region with an out-of-range centroid would make MapKit throw
            // (an invalid `Annotation` coordinate is an ObjC exception, not
            // a Swift error), so anything the server sends that isn't a real
            // place on Earth is dropped here rather than drawn.
            regions = payload.regions
                .filter { $0.activeRams > 0 }
                .filter { $0.latitude.isFinite && $0.longitude.isFinite && abs($0.latitude) <= 90 && abs($0.longitude) <= 180 }
                .map {
                    Region(
                        name: $0.name,
                        coordinate: RamCoordinate(latitude: $0.latitude, longitude: $0.longitude),
                        activeRams: $0.activeRams
                    )
                }
            lastUpdatedAt = Date()
        } catch {
            log("GET flock-pulse failed: \(error.localizedDescription)")
        }
    }

    /// Refreshes on a loop until the calling `Task` is cancelled — drive
    /// it from a SwiftUI `.task`, which cancels it automatically when the
    /// view goes away, so there is never a timer left running behind a
    /// screen nobody is looking at.
    func poll(every interval: Duration = .seconds(60)) async {
        while !Task.isCancelled {
            await refresh()
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
        }
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[FlockPulseService] \(message)")
        #endif
    }
}
