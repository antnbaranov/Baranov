//
//  LetterDraftStore.swift
//  Baranov
//
//  Where an unsent letter waits (see `LetterDraft`). One draft at a time
//  — Compose is a single form, and the draft is that form's contents set
//  aside, not a mailbox. Written as JSON in Application Support next to
//  the flock cache, atomically, and read back when Compose appears.
//
//  Best-effort like `FlockStore`: a failed write logs and the form keeps
//  its state in memory; a failed read means no draft, never a crash.
//

import Foundation
import Observation
import os

@Observable
@MainActor
final class LetterDraftStore {
    /// The current draft, if any. Observed by Compose so a "Saved to
    /// Drafts" notice can appear and clear itself.
    private(set) var draft: LetterDraft?

    private let fileURL: URL
    private static let logger = Logger(subsystem: "com.baranov", category: "LetterDraftStore")

    /// The real store, in the app's Application Support directory.
    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        fileURL = base
            .appendingPathComponent("Baranov", isDirectory: true)
            .appendingPathComponent("letter-draft.json")
        draft = load()
    }

    /// A throwaway store in a temp directory — for previews and tests.
    init(ephemeral: Bool) {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("letter-draft-\(UUID().uuidString).json")
        draft = nil
    }

    var hasDraft: Bool { draft?.hasContent == true }

    /// Keeps `draft` and writes it through. An empty form clears instead.
    func save(_ newDraft: LetterDraft) {
        guard newDraft.hasContent else {
            clear()
            return
        }
        draft = newDraft
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(newDraft)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Self.logger.error("Couldn't save letter draft: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The letter went out (or the sender threw it away): nothing left to
    /// restore.
    func clear() {
        draft = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func load() -> LetterDraft? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let stored = try decoder.decode(LetterDraft.self, from: data)
            return stored.hasContent ? stored : nil
        } catch {
            Self.logger.error("Letter draft unreadable, ignoring: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
