//
//  FlockStore.swift
//  Baranov
//
//  The flock's on-disk home. A ram mid-journey is days or weeks of real
//  walking; losing it to an app relaunch would be the single worst thing
//  this app could do to someone, so `FlockViewModel` writes through here
//  on every mutation and reads back from here at launch.
//
//  Plain JSON in Application Support (not `UserDefaults` — a flock with
//  road polylines for three legs is far larger than a preferences blob
//  should be), written atomically so a crash mid-write leaves the
//  previous good file in place. Letters inside are ciphertext (see
//  `Letter`), so the cache holds nothing a backup or a curious file
//  browser could read.
//
//  Every operation is best-effort: a failed write logs and moves on, a
//  failed read starts an empty flock. Offline-first means the UI never
//  waits on, or crashes because of, the disk.
//

import Foundation
import os

struct FlockStore: Sendable {
    /// Everything the flock needs to come back exactly as it was.
    struct Snapshot: Codable, Sendable {
        var activeRams: [Ram]
        var selectedRamId: UUID?
        var savedAt: Date
    }

    let fileURL: URL

    private static let logger = Logger(subsystem: "com.baranov", category: "FlockStore")

    /// The real store, in the app's Application Support directory.
    static let `default` = FlockStore(fileURL: defaultFileURL())

    /// A throwaway store in a temp directory — for tests and previews.
    static func ephemeral() -> FlockStore {
        FlockStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("flock-\(UUID().uuidString).json"))
    }

    func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try Self.decoder.decode(Snapshot.self, from: data)
        } catch {
            Self.logger.error("Flock cache unreadable, starting empty: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func save(_ snapshot: Snapshot) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Self.logger.error("Couldn't save flock: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Baranov", isDirectory: true).appendingPathComponent("flock.json")
    }
}
