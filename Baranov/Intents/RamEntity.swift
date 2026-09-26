//
//  RamEntity.swift
//  Baranov
//
//  How Siri, Shortcuts and Spotlight see a carrier ram. Read-only: it is built
//  from the same on-disk flock snapshot the app writes (`FlockStore`), so an
//  intent never has to wait on the UI, the network or a live step count.
//

import AppIntents
import Foundation

nonisolated struct RamEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Ram")
    static let defaultQuery = RamEntityQuery()

    let id: UUID
    let name: String
    let status: String
    let currentCity: String
    let targetCity: String
    let stepsWalked: Int
    let totalStepsRequired: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(status) · \(currentCity) → \(targetCity)"
        )
    }

    /// Fraction of the current leg walked, clamped to 0...1.
    var progress: Double {
        guard totalStepsRequired > 0 else { return 0 }
        return min(max(Double(stepsWalked) / Double(totalStepsRequired), 0), 1)
    }

    /// Metres (1 step = 1 metre) still to walk on the current leg.
    var metresRemaining: Int { max(totalStepsRequired - stepsWalked, 0) }
}

extension RamEntity {
    @MainActor
    init(_ ram: Ram) {
        self.init(
            id: ram.id,
            name: ram.name,
            status: ram.status.displayName,
            currentCity: ram.currentCity,
            targetCity: ram.targetCity,
            stepsWalked: ram.stepsWalked,
            totalStepsRequired: ram.totalStepsRequired
        )
    }
}

nonisolated struct RamEntityQuery: EntityStringQuery {
    @MainActor
    private func rams() -> [Ram] {
        FlockStore.default.load()?.activeRams ?? []
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [RamEntity] {
        rams().filter { identifiers.contains($0.id) }.map(RamEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [RamEntity] {
        rams()
            .filter { $0.name.localizedStandardContains(string) }
            .map(RamEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [RamEntity] {
        rams().map(RamEntity.init)
    }
}
