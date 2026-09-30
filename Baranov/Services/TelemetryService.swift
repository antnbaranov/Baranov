//
//  TelemetryService.swift
//  Baranov
//
//  Background telemetry client for the ACIT3855 course receiver.
//

import Foundation

/// Posts course telemetry (ram hops and flock metrics) to the ACIT3855
/// Lab 1 receiver.
///
/// This service is fully offline-first: every failure mode — a timed-out
/// connection, a refused connection, an unreachable host, or a decoding
/// error — is caught internally and logged. Callers can fire-and-forget
/// these calls from anywhere in the app (including background contexts)
/// without risking a crash or an interruption to step recording, ram
/// travel, or any other user-facing flow.
final class TelemetryService: Sendable {

    // MARK: - Configuration

    /// The base URL of the ACIT3855 telemetry receiver.
    let baseURL: URL

    /// The deployed receiver, from the `TelemetryBaseURL` Info.plist key —
    /// the same key `Analytics` reads — so one setting points telemetry,
    /// the letter relay, carrier presence and recalls at the same server.
    /// Falls back to the local development receiver, which a real phone
    /// can't reach: set the key before testing on a device.
    /// Whether a real receiver is configured. Without one the app stays
    /// fully usable — steps, handoffs, the packet, guests all live on the
    /// phone — and simply skips every network round-trip instead of
    /// hammering a localhost that isn't there.
    static var isServerConfigured: Bool {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "TelemetryBaseURL") as? String,
           let url = URL(string: configured.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.scheme != nil {
            return true
        }
        // The localhost fallback only means something where localhost is
        // the developer's Mac: the Simulator, during coursework.
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    static var configuredBaseURL: URL {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "TelemetryBaseURL") as? String,
           let url = URL(string: configured.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.scheme != nil {
            return url
        }
        return URL(string: "http://localhost:8080")!
    }

    private let session: URLSession
    private let encoder: JSONEncoder

    /// Creates a telemetry client.
    /// - Parameters:
    ///   - baseURL: The receiver's base URL. Defaults to the local
    ///     development receiver used during coursework.
    ///   - session: The `URLSession` used for requests. Defaults to
    ///     `.shared`; inject a custom session for testing.
    init(baseURL: URL = TelemetryService.configuredBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.ISO8601Format())
        }
        self.encoder = encoder
    }

    // MARK: - Wire payloads

    /// Body for `POST /telemetry/ram-hop`.
    private struct RamHopPayload: Encodable {
        let ramId: UUID
        let carrierUserId: UUID
        let stepsTraveled: Int
        let timestamp: Date

        enum CodingKeys: String, CodingKey {
            case ramId = "ram_id"
            case carrierUserId = "carrier_user_id"
            case stepsTraveled = "steps_traveled"
            case timestamp
        }
    }

    /// Body for `POST /telemetry/flock-metric`.
    private struct FlockMetricPayload: Encodable {
        let carrierUserId: UUID
        let activeRamsCount: Int
        let totalLettersDelivered: Int
        let timestamp: Date

        enum CodingKeys: String, CodingKey {
            case carrierUserId = "carrier_user_id"
            case activeRamsCount = "active_rams_count"
            case totalLettersDelivered = "total_letters_delivered"
            case timestamp
        }
    }

    // MARK: - Public API

    /// Reports that a ram advanced by `stepsTraveled` meters/steps
    /// toward its destination.
    ///
    /// - Note: This method matches the ACIT3855 Lab 1 contract by being
    ///   marked `throws`, but it never actually propagates an error —
    ///   every failure is caught and logged internally so it is always
    ///   safe to call with `try?` (or await it directly) from any
    ///   call site, including background step-tracking callbacks.
    func sendRamHop(ramId: UUID, carrierUserId: UUID, stepsTraveled: Int) async throws {
        let payload = RamHopPayload(
            ramId: ramId,
            carrierUserId: carrierUserId,
            stepsTraveled: stepsTraveled,
            timestamp: Date()
        )
        await post(payload, to: "telemetry/ram-hop")
    }

    /// Reports a snapshot of the carrier's current flock state.
    ///
    /// - Note: Same resilience contract as `sendRamHop(_:_:_:)` — all
    ///   failures are swallowed and logged, never thrown.
    func sendFlockMetric(carrierUserId: UUID, activeRamsCount: Int, totalDelivered: Int) async throws {
        let payload = FlockMetricPayload(
            carrierUserId: carrierUserId,
            activeRamsCount: activeRamsCount,
            totalLettersDelivered: totalDelivered,
            timestamp: Date()
        )
        await post(payload, to: "telemetry/flock-metric")
    }

    // MARK: - Private networking

    private func post(_ payload: some Encodable, to path: String) async {
        guard Self.isServerConfigured else { return }
        let url = baseURL.appendingPathComponent(path)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        do {
            request.httpBody = try encoder.encode(payload)
        } catch {
            log("Failed to encode payload for \(path): \(error.localizedDescription)")
            return
        }

        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                log("POST \(path) returned unexpected status \(httpResponse.statusCode)")
            }
        } catch {
            // Timeout, connection refused, offline, DNS failure, etc.
            // Telemetry is best-effort — never let this reach the caller
            // as a fatal error or interrupt the app's primary flows.
            log("POST \(path) failed: \(error.localizedDescription)")
        }
    }

    private func log(_ message: String) {
        #if DEBUG
        print("[TelemetryService] \(message)")
        #endif
    }
}
