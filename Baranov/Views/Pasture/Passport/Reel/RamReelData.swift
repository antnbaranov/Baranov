//
//  RamReelData.swift
//  Baranov
//
//  What a ram's reel is made from: its real distance, its real stamps, and
//  a personality worked out from them — the joke is only funny if it is
//  true, so nothing here is invented beyond the phrasing.
//

import Foundation

enum RamReelPersonality: CaseIterable {
    case soggyOptimist, nightOwl, reluctantSwimmer, relayDiva, professionalTourist, marathonMenace, fluffyBeginner

    var title: String {
        switch self {
        case .soggyOptimist: String(localized: "The Soggy Optimist")
        case .nightOwl: String(localized: "The Night Owl")
        case .reluctantSwimmer: String(localized: "The Reluctant Swimmer")
        case .relayDiva: String(localized: "The Relay Diva")
        case .professionalTourist: String(localized: "The Professional Tourist")
        case .marathonMenace: String(localized: "The Marathon Menace")
        case .fluffyBeginner: String(localized: "The Fluffy Beginner")
        }
    }

    var tagline: String {
        switch self {
        case .soggyOptimist: String(localized: "Wool: soaked. Spirit: undefeated.")
        case .nightOwl: String(localized: "Delivers after dark. Sleeps on the job, never.")
        case .reluctantSwimmer: String(localized: "Crossed water. Has opinions about it.")
        case .relayDiva: String(localized: "Will only walk if someone else takes the next leg.")
        case .professionalTourist: String(localized: "Many stamps. Zero souvenirs. Great posture.")
        case .marathonMenace: String(localized: "Has walked further than your last vacation.")
        case .fluffyBeginner: String(localized: "Just getting started. Already fluffy.")
        }
    }

    var symbol: String {
        switch self {
        case .soggyOptimist: "cloud.rain.fill"
        case .nightOwl: "moon.stars.fill"
        case .reluctantSwimmer: "water.waves"
        case .relayDiva: "hand.wave.fill"
        case .professionalTourist: "signpost.right.fill"
        case .marathonMenace: "figure.run"
        case .fluffyBeginner: "leaf.fill"
        }
    }
}

struct RamReelData {
    let ramName: String
    let totalMeters: Int
    /// Short place names, oldest first.
    let places: [String]
    let latestStamp: JourneyStamp?
    let personality: RamReelPersonality
    let comparison: String
    /// The narrator and the lines written in their voice (see `RamReelWriter`).
    var voice: RamReelVoice?
    var intro: String = String(localized: "and they have been busy.")
    var closer: String = String(localized: "Send one with your own two feet.")
    /// Which colour theme this reel wears (index into `ReelTheme.all`).
    var variant: Int = 0
    /// Where the stamps are, oldest first — the raw material for the map beat.
    var placeCoordinates: [ReelPlace] = []
    /// The rendered map beat, once built (see `RamReelMapBuilder`).
    var map: RamReelMap?
    /// A milestone the person wrote, when the reel is made about one.
    var goal: String?
    var goalDone = false

    @MainActor
    static func make(ramName: String, totalMeters: Int, lettersDelivered: Int, stamps: [JourneyStamp]) -> RamReelData {
        let ordered = stamps.sorted { $0.timestamp < $1.timestamp }
        let calendar = Calendar.current
        let night = ordered.contains {
            let hour = calendar.component(.hour, from: $0.timestamp)
            return hour >= 21 || hour < 5
        }
        let places = Set(ordered.map { $0.placeName.lowercased() }).count

        let personality: RamReelPersonality
        if ordered.contains(where: { $0.weather?.isWet == true }) { personality = .soggyOptimist }
        else if night { personality = .nightOwl }
        else if ordered.contains(where: { $0.kind == .water }) { personality = .reluctantSwimmer }
        else if ordered.contains(where: { $0.kind == .handoff }) { personality = .relayDiva }
        else if totalMeters >= 10_000 { personality = .marathonMenace }
        else if places >= 3 { personality = .professionalTourist }
        else { personality = .fluffyBeginner }

        // The most impressive comparison that still reads as a whole number.
        let comparison = DistanceComparison.allCases
            .filter { Double(totalMeters) / $0.meters >= 1 }
            .max { $0.meters < $1.meters }
            ?? .giraffes

        return RamReelData(
            ramName: ramName,
            totalMeters: totalMeters,
            places: ordered.map(\.shortPlaceName),
            latestStamp: ordered.last,
            personality: personality,
            comparison: totalMeters > 0
                ? comparison.sentence(for: totalMeters)
                : String(localized: "Has not gone anywhere yet. Suspiciously relaxed."),
            placeCoordinates: ordered.map { ReelPlace(name: $0.shortPlaceName, latitude: $0.latitude, longitude: $0.longitude) }
        )
    }
}

extension RamReelData {
    /// The same reel, narrated by `voice`. The fun-fact line becomes the
    /// narrator's line about the distance.
    func withVoice(_ voice: RamReelVoice, lines: RamReelLines, variant: Int) -> RamReelData {
        RamReelData(
            ramName: ramName, totalMeters: totalMeters, places: places, latestStamp: latestStamp,
            personality: personality,
            comparison: totalMeters > 0 ? lines.fact : comparison,
            voice: voice, intro: lines.intro, closer: lines.closer, variant: variant,
            placeCoordinates: placeCoordinates, map: map,
            goal: goal, goalDone: goalDone
        )
    }
}
