//
//  RecallService.swift
//  Baranov
//
//  "Take it back": the original sender of a handed-on letter asks for it
//  back, and whoever is carrying it gives it up the next time their phone
//  is online.
//
//  Sender:  POST /recalls {letter_id, token}         -> marks the ram "asking"
//           GET  /recalls?letter_ids=…  (acknowledged?) -> the ram comes home
//  Carrier: GET  /recalls?letter_ids=…  for every guest letter aboard
//           the recall's hash must equal the letter's `recallTokenHash`
//           POST /recalls/{id}/ack {token_hash}        -> then the guest leaves
//
//  The carrier acknowledges BEFORE letting go, so a failed request can never
//  leave the letter on neither phone. Offline-first: every failure is
//  silently retried on the next tick.
//

import Foundation
import Observation

@MainActor
@Observable
final class RecallService {
    /// Rams whose "Take it back" request is in flight right now.
    private(set) var requesting: Set<UUID> = []
    /// Set when a request couldn't reach the relay, for the bag to show.
    private(set) var failedRamID: UUID?

    @ObservationIgnored private let baseURL: URL
    @ObservationIgnored private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Sender

    /// Asks for a handed-on letter back. Returns whether the relay has the
    /// request; the ram itself only comes home once the carrier gives it up.
    @discardableResult
    func takeBack(_ ram: Ram, flock: FlockViewModel) async -> Bool {
        guard flock.canTakeBack(ram), let letter = ram.letter,
              let token = RecallTokenVault.token(for: letter.id) else { return false }
        requesting.insert(ram.id)
        failedRamID = nil
        defer { requesting.remove(ram.id) }

        var request = URLRequest(url: baseURL.appending(path: "recalls"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try? JSONEncoder().encode(RecallBody(letter_id: letter.id, token: token))

        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            failedRamID = ram.id
            return false
        }
        flock.markRecallRequested(ramId: ram.id)
        await tick(flock: flock)
        return true
    }

    // MARK: - Both sides

    /// Call about once a minute while the app is in the foreground.
    /// - Parameters:
    ///   - onReleased: carrier side — a guest left this mailbag (ram name, sender name).
    ///   - onCameHome: sender side — a ram asked back is home again (ram name).
    func tick(
        flock: FlockViewModel,
        onReleased: (String, String) -> Void = { _, _ in },
        onCameHome: (String) -> Void = { _ in }
    ) async {
        let guests = flock.guestRams.compactMap { ram -> Letter? in
            guard let letter = ram.letter, letter.recallTokenHash != nil else { return nil }
            return letter
        }
        let asking = flock.activeRams.filter { $0.status == .handedOff && $0.recallRequestedAt != nil }
            .compactMap { $0.letter?.id }

        let ids = Array((guests.map(\.id) + asking).prefix(20))
        guard !ids.isEmpty, let recalls = await fetch(ids) else { return }

        for recall in recalls {
            // Carrier: someone's letter in my mailbag has been asked back.
            if let letter = guests.first(where: { $0.id == recall.letter_id }),
               letter.recallTokenHash?.lowercased() == recall.token_hash.lowercased() {
                if await acknowledge(letterID: letter.id, tokenHash: recall.token_hash),
                   let name = flock.releaseRecalled(letterID: letter.id, tokenHash: recall.token_hash) {
                    onReleased(name, letter.senderName)
                }
            }
            // Sender: the carrier gave it up — my ram comes home.
            if recall.acknowledged, asking.contains(recall.letter_id),
               let name = flock.restoreRecalled(letterID: recall.letter_id) {
                onCameHome(name)
            }
        }
    }

    // MARK: - Wire

    private struct RecallBody: Encodable {
        let letter_id: UUID
        let token: String
    }

    private struct AckBody: Encodable {
        let token_hash: String
    }

    private struct Reply: Decodable {
        struct Recall: Decodable {
            let letter_id: UUID
            let token_hash: String
            let acknowledged: Bool
        }
        let recalls: [Recall]
    }

    private func fetch(_ letterIDs: [UUID]) async -> [Reply.Recall]? {
        var components = URLComponents(url: baseURL.appending(path: "recalls"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(
            name: "letter_ids",
            value: letterIDs.map { $0.uuidString.lowercased() }.joined(separator: ",")
        )]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return nil }
        return reply.recalls
    }

    private func acknowledge(letterID: UUID, tokenHash: String) async -> Bool {
        var request = URLRequest(url: baseURL.appending(path: "recalls/\(letterID.uuidString.lowercased())/ack"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try? JSONEncoder().encode(AckBody(token_hash: tokenHash.lowercased()))
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
}
