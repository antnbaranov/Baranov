//
//  BaranovIntents.swift
//  Baranov
//
//  Voice and Shortcuts surface for the flock: "Hey Siri, where is my ram in
//  Baranov?" These are plain App Intents (no App Schema), so they work in
//  Siri, Shortcuts, Spotlight and the Action button. Every intent is read-only
//  and offline-first: it answers from the flock snapshot on disk.
//

import AppIntents
import Foundation

// MARK: - Where is my ram?

nonisolated struct RamStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Check on a Ram"
    static let description = IntentDescription("Hear where a carrier ram is and how far it still has to walk.")

    @Parameter(title: "Ram", requestValueDialog: "Which ram?")
    var ram: RamEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Check on \(\.$ram)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let rams = (FlockStore.default.load()?.activeRams ?? []).map(RamEntity.init)
        guard !rams.isEmpty else {
            return .result(dialog: "Your pasture is empty. Write a letter and a ram will set off.")
        }
        let chosen = ram.flatMap { pick in rams.first { $0.id == pick.id } }
            ?? rams.first { $0.status == RamStatus.walking.displayName }
            ?? rams[0]
        let percent = Int((chosen.progress * 100).rounded())
        let remaining = Measurement(value: Double(chosen.metresRemaining), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
        return .result(dialog: "\(chosen.name) is \(chosen.status.lowercased()) near \(chosen.currentCity), \(percent) percent of the way to \(chosen.targetCity). About \(remaining) to go.")
    }
}

// MARK: - How is my flock?

nonisolated struct FlockSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "How Is My Flock?"
    static let description = IntentDescription("A spoken summary of every ram on the road.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let rams = (FlockStore.default.load()?.activeRams ?? []).map(RamEntity.init)
        guard !rams.isEmpty else {
            return .result(dialog: "No rams are out right now.")
        }
        let lines = rams.map { "\($0.name): \($0.status.lowercased()), \(Int(($0.progress * 100).rounded())) percent to \($0.targetCity)" }
        return .result(dialog: "\(rams.count) on the road. \(lines.joined(separator: ". ")).")
    }
}

// MARK: - Write a letter

nonisolated struct WriteLetterIntent: AppIntent {
    static let title: LocalizedStringResource = "Write a Letter"
    static let description = IntentDescription("Open Baranov to write a letter for a ram to carry.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

// MARK: - Open the pasture

nonisolated struct OpenPastureIntent: AppIntent {
    static let title: LocalizedStringResource = "Open My Pasture"
    static let description = IntentDescription("Open Baranov on your flock of rams.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingAppAction.request(.openPasture)
        return .result()
    }
}

// MARK: - Enter a receiving code

nonisolated struct EnterLetterCodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Enter an Ear Tag"
    static let description = IntentDescription("Open Baranov to type the ear tag for a letter that is waiting for you.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingAppAction.request(.enterLetterCode)
        return .result()
    }
}

// MARK: - Phrases

nonisolated struct BaranovShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RamStatusIntent(),
            phrases: [
                "Where is my ram in \(.applicationName)",
                "Check on my ram in \(.applicationName)",
                "How far has my ram walked in \(.applicationName)"
            ],
            shortTitle: "Check on a Ram",
            systemImageName: "figure.walk"
        )
        AppShortcut(
            intent: FlockSummaryIntent(),
            phrases: [
                "How is my flock in \(.applicationName)",
                "Flock report in \(.applicationName)"
            ],
            shortTitle: "Flock Report",
            systemImageName: "pawprint"
        )
        AppShortcut(
            intent: WriteLetterIntent(),
            phrases: [
                "Write a letter in \(.applicationName)",
                "Send a letter with \(.applicationName)"
            ],
            shortTitle: "Write a Letter",
            systemImageName: "envelope"
        )
        AppShortcut(
            intent: OpenPastureIntent(),
            phrases: [
                "Open my pasture in \(.applicationName)",
                "Show my rams in \(.applicationName)"
            ],
            shortTitle: "Open My Pasture",
            systemImageName: "pawprint.circle"
        )
        AppShortcut(
            intent: EnterLetterCodeIntent(),
            phrases: [
                "Enter an ear tag in \(.applicationName)",
                "I got a letter in \(.applicationName)"
            ],
            shortTitle: "Enter an Ear Tag",
            systemImageName: "key"
        )
    }
}
