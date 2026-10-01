//
//  RamGoal.swift
//  Baranov
//
//  A milestone the person writes themselves: "Walk to my mum's place",
//  "Cross a bridge without looking down". Words can't be verified, so the
//  person says when it happened — unless they also set a distance, in which
//  case the milestone completes itself once the ram has walked that much
//  further than it had when the goal was written.
//
//  Stored on the phone (UserDefaults, JSON) — no account, no network.
//

import Foundation
import Observation

struct RamGoal: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let ramID: UUID
    var title: String
    /// "Walk this much more" — nil for a goal that only the person can tick off.
    var targetMeters: Int?
    /// The ram's lifetime distance when the goal was written.
    var startMeters: Int
    var createdAt: Date
    var completedAt: Date?
    /// The sky when the person ticked it off, if a stamp had weather by then.
    var completionWeather: StampWeather?

    func isDone(totalMeters: Int) -> Bool {
        if completedAt != nil { return true }
        guard let targetMeters else { return false }
        return totalMeters - startMeters >= targetMeters
    }

    func progress(totalMeters: Int) -> Double? {
        guard let targetMeters, targetMeters > 0 else { return nil }
        return min(1, max(0, Double(totalMeters - startMeters) / Double(targetMeters)))
    }

    func metersToGo(totalMeters: Int) -> Int? {
        guard let targetMeters else { return nil }
        return max(0, targetMeters - (totalMeters - startMeters))
    }
}

/// Funny starting points, so a blank text field is never the first thing
/// someone sees. `kilometers` makes the suggestion a distance goal too.
struct RamGoalSuggestion: Identifiable, Hashable, Sendable {
    let title: String
    let kilometers: Int?
    var id: String { title }

    /// Suggestions shuffled, with the ones that fit the current sky first.
    static func ordered(for weather: StampWeather?, count: Int = 4) -> [RamGoalSuggestion] {
        let fitting = weather.map(weatherSuggestions(for:)) ?? []
        let rest = all.filter { item in !fitting.contains(where: { $0.id == item.id }) }.shuffled()
        return Array((fitting.shuffled() + rest).prefix(count))
    }

    static func weatherSuggestions(for weather: StampWeather) -> [RamGoalSuggestion] {
        if weather.isWet {
            return [
                .init(title: String(localized: "Get a stamp in the rain and refuse to complain", bundle: .appLanguage, locale: .appLanguage), kilometers: nil),
                .init(title: String(localized: "Keep the letter dry through a proper downpour", bundle: .appLanguage, locale: .appLanguage), kilometers: 3),
            ]
        }
        if weather.temperatureCelsius <= 3 {
            return [.init(title: String(localized: "Walk on through the cold and earn a warm drink", bundle: .appLanguage, locale: .appLanguage), kilometers: 3)]
        }
        if weather.temperatureCelsius >= 26 {
            return [.init(title: String(localized: "Beat the heat and find a shady spot for the letter", bundle: .appLanguage, locale: .appLanguage), kilometers: 3)]
        }
        return [.init(title: String(localized: "Make the most of this weather with a long walk", bundle: .appLanguage, locale: .appLanguage), kilometers: 6)]
    }

    static var all: [RamGoalSuggestion] {
        [
            .init(title: String(localized: "Deliver a letter to someone who misses me", bundle: .appLanguage, locale: .appLanguage), kilometers: nil),
            .init(title: String(localized: "Walk to the nearest bakery. For the letter, obviously.", bundle: .appLanguage, locale: .appLanguage), kilometers: 2),
            .init(title: String(localized: "Cross a bridge without looking down", bundle: .appLanguage, locale: .appLanguage), kilometers: nil),
            .init(title: String(localized: "Get a stamp in the rain and refuse to complain", bundle: .appLanguage, locale: .appLanguage), kilometers: nil),
            .init(title: String(localized: "Reach the next city before my coffee gets cold", bundle: .appLanguage, locale: .appLanguage), kilometers: 10),
            .init(title: String(localized: "Visit three places I can't pronounce", bundle: .appLanguage, locale: .appLanguage), kilometers: nil),
            .init(title: String(localized: "Walk 5 km before breakfast", bundle: .appLanguage, locale: .appLanguage), kilometers: 5),
            .init(title: String(localized: "Make one stranger say “aww”", bundle: .appLanguage, locale: .appLanguage), kilometers: nil),
            .init(title: String(localized: "Arrive at my mum's door, on hoof", bundle: .appLanguage, locale: .appLanguage), kilometers: nil),
            .init(title: String(localized: "Outwalk a very confident goose", bundle: .appLanguage, locale: .appLanguage), kilometers: 3),
            .init(title: String(localized: "Get chased by a dog and win", bundle: .appLanguage, locale: .appLanguage), kilometers: nil),
            .init(title: String(localized: "Deliver a letter that makes someone cry (happy tears only)", bundle: .appLanguage, locale: .appLanguage), kilometers: nil),
            .init(title: String(localized: "Find a hill dramatic enough for a photo", bundle: .appLanguage, locale: .appLanguage), kilometers: 4),
            .init(title: String(localized: "Beat my own record out of sheer spite", bundle: .appLanguage, locale: .appLanguage), kilometers: 8),
            .init(title: String(localized: "Nap heroically halfway through", bundle: .appLanguage, locale: .appLanguage), kilometers: nil),
        ]
    }
}

@MainActor
@Observable
final class RamGoalStore {
    private static let key = "baranov.ramGoals.v1"

    private(set) var goals: [RamGoal] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([RamGoal].self, from: data) {
            goals = decoded
        }
    }

    func goals(for ramID: UUID) -> [RamGoal] {
        goals.filter { $0.ramID == ramID }.sorted { $0.createdAt > $1.createdAt }
    }

    func add(title: String, kilometers: Int?, ramID: UUID, currentMeters: Int) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        goals.append(RamGoal(
            id: UUID(), ramID: ramID, title: String(trimmed.prefix(90)),
            targetMeters: kilometers.map { $0 * 1_000 },
            startMeters: currentMeters, createdAt: Date(), completedAt: nil, completionWeather: nil
        ))
        save()
    }

    func markDone(_ goal: RamGoal, weather: StampWeather? = nil) {
        guard let index = goals.firstIndex(where: { $0.id == goal.id }), goals[index].completedAt == nil else { return }
        goals[index].completedAt = Date()
        goals[index].completionWeather = weather
        save()
    }

    func delete(_ goal: RamGoal) {
        goals.removeAll { $0.id == goal.id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(goals) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
