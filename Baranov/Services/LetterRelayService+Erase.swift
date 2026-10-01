//
//  LetterRelayService+Erase.swift
//  Baranov
//
//  The relay's half of "Delete all data & reset" (App Store Review
//  Guideline 5.1.1(v)). Baranov has no accounts, so the only thing the
//  relay holds about a person is what hangs off their Shepherd ID:
//
//  - the address itself, with its public key and inbox token hash;
//  - the gate (town-level coordinates) published under it;
//  - the APNs device tokens registered under it;
//  - letters still waiting for it, and tracked letters it sent that have not
//    reached their gate yet.
//
//  `POST /addresses/{address}/erase` (proved with the inbox token, the same
//  proof every other address call uses) removes all of that in one go. The
//  carrier-presence entry is dropped the way the app always drops it: an
//  empty ram list.
//
//  Offline-first, and never a gate: the whole thing gives up after a few
//  seconds and reports `.failed`, and the caller wipes the phone anyway. A
//  person must always be able to clear their own device.
//

import Foundation

/// How the relay's side of "delete all data" went.
enum RemoteEraseOutcome: Sendable, Equatable {
    /// The relay confirmed, or no longer knew this Shepherd ID.
    case erased
    /// Nothing to ask for: no relay is configured, or this phone never
    /// registered a Shepherd ID with it.
    case skipped
    /// Offline, timed out or refused. The local wipe goes ahead regardless.
    case failed
}

extension LetterRelayService {
    /// The relay the rest of the app talks to.
    static let shared = LetterRelayService(baseURL: TelemetryService.configuredBaseURL)

    /// Asks the relay to forget this phone: unregisters the Shepherd ID,
    /// revokes the APNs token, removes the published gate coordinates and
    /// purges pending and undelivered letters from the queue.
    ///
    /// Must run **before** the Keychain is wiped (the inbox token is what
    /// proves the Shepherd ID is ours). Never throws and never takes longer
    /// than about `timeout` seconds; on any failure the caller carries on
    /// with the local wipe.
    func deleteUserData(timeout: TimeInterval = 8) async -> RemoteEraseOutcome {
        guard TelemetryService.isServerConfigured else { return .skipped }

        let address = RecipientKeyring.myAddress
        let inboxToken = AddressKeychain.inboxToken
        let presenceID = UserDefaults.standard.string(forKey: "com.baranov.carrierUserId").flatMap(UUID.init(uuidString:))
        guard (address != nil && inboxToken != nil) || presenceID != nil else { return .skipped }

        // Fails fast when offline, and caps each request, so a dead network
        // never keeps the person waiting.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        let client = LetterRelayService(baseURL: baseURL, session: URLSession(configuration: configuration))

        // `BestEffort` also covers a request that never calls back at all.
        let outcome = await BestEffort.run(seconds: timeout + 1) { () async -> RemoteEraseOutcome in
            await client.erase(address: address, inboxToken: inboxToken, presenceID: presenceID)
        }
        return outcome ?? .failed
    }

    // MARK: - Requests

    fileprivate func erase(address: String?, inboxToken: String?, presenceID: UUID?) async -> RemoteEraseOutcome {
        async let presenceStopped: Void = stopSharingPresence(carrierUserID: presenceID)
        var outcome = RemoteEraseOutcome.skipped
        if let address, let inboxToken {
            outcome = await eraseAddress(address, inboxToken: inboxToken)
        }
        await presenceStopped
        return outcome
    }

    private struct EraseBody: Encodable {
        let token: String
    }

    private func eraseAddress(_ address: String, inboxToken: String) async -> RemoteEraseOutcome {
        var request = URLRequest(url: baseURL.appending(path: "addresses/\(address)/erase"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(EraseBody(token: inboxToken))
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed }
            // 404: the relay never had it, or an earlier attempt already got through.
            return http.statusCode == 200 || http.statusCode == 404 ? .erased : .failed
        } catch {
            return .failed
        }
    }

    private struct PresenceStopBody: Encodable {
        let carrier_user_id: UUID
        let carrier_name: String
        let ram_ids: [UUID]
        let latitude: Double
        let longitude: Double
    }

    /// An empty ram list is how a carrier stops sharing: the receiver
    /// forgets the entry at once (it would expire within 30 minutes anyway).
    private func stopSharingPresence(carrierUserID: UUID?) async {
        guard let carrierUserID else { return }
        var request = URLRequest(url: baseURL.appending(path: "telemetry/carrier-presence"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(PresenceStopBody(
            carrier_user_id: carrierUserID, carrier_name: "", ram_ids: [], latitude: 0, longitude: 0
        ))
        _ = try? await session.data(for: request)
    }
}
