//
//  RelayOutbox.swift
//  Baranov
//
//  The letters this person has published to the relay and is waiting on.
//  Kept on disk so a code survives a relaunch, and checked whenever the app
//  is in the foreground: the moment a recipient claims one, the sender is
//  told (a local notification — the relay never learns or shares where the
//  recipient chose to receive it).
//

import Foundation
import Observation

struct PublishedLetter: Identifiable, Codable, Hashable, Sendable {
    let id: UUID              // the letter's own id
    let code: String          // the relay lookup id (never the letter code itself)
    let recipientName: String
    let createdAt: Date
    var claimedAt: Date?
    /// Only the "just claimed" moment notifies; this makes it exactly once.
    var didNotify = false

    var isClaimed: Bool { claimedAt != nil }
}

@MainActor
@Observable
final class RelayOutbox {
    private(set) var letters: [PublishedLetter] = []

    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? base.appendingPathComponent("relay-outbox.json")
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode([PublishedLetter].self, from: data) {
            letters = decoded
        }
    }

    func add(letterID: UUID, code: String, recipientName: String) {
        letters.insert(PublishedLetter(id: letterID, code: code, recipientName: recipientName, createdAt: Date()), at: 0)
        persist()
    }

    /// Asks the relay about every unclaimed letter; `onClaimed` fires once
    /// per letter that has just been claimed. Failures are silent — the
    /// next foreground tick simply tries again.
    func refresh(using relay: LetterRelayService, onClaimed: (PublishedLetter) -> Void) async {
        for letter in letters where !letter.isClaimed {
            guard let claimed = try? await relay.isClaimed(id: letter.code), claimed else { continue }
            guard let index = letters.firstIndex(where: { $0.id == letter.id }) else { continue }
            letters[index].claimedAt = Date()
            if !letters[index].didNotify {
                letters[index].didNotify = true
                onClaimed(letters[index])
            }
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(letters) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
