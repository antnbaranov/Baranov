//
//  RamReelWriter.swift
//  Baranov
//
//  Makes every reel different. Each reel gets a random NARRATOR — a nature
//  documentary, a sports commentator, a noir detective, a passive-aggressive
//  HR email, a medieval herald… — and Apple's on-device foundation model
//  writes the reel's few lines in that voice, from the ram's real numbers
//  and places. "Remix" rolls a new voice, so two reels are never alike, and
//  "which voice did you get?" is the reason to post it.
//
//  Runs entirely on the device. Only the ram's name, distance, place names
//  and personality go in — never a letter. Without Apple Intelligence
//  (or on iOS 18) the same voices are written from hand-made lines, so the
//  reel still varies; it is just not freshly written.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum RamReelVoice: CaseIterable {
    case natureDocumentary, sportsCommentator, noirDetective, passiveAggressiveHR, medievalHerald, overexcitedGPS

    var name: String {
        switch self {
        case .natureDocumentary: String(localized: "Nature documentary", bundle: .appLanguage, locale: .appLanguage)
        case .sportsCommentator: String(localized: "Sports commentator", bundle: .appLanguage, locale: .appLanguage)
        case .noirDetective: String(localized: "Noir detective", bundle: .appLanguage, locale: .appLanguage)
        case .passiveAggressiveHR: String(localized: "Passive-aggressive HR", bundle: .appLanguage, locale: .appLanguage)
        case .medievalHerald: String(localized: "Medieval herald", bundle: .appLanguage, locale: .appLanguage)
        case .overexcitedGPS: String(localized: "Overexcited GPS", bundle: .appLanguage, locale: .appLanguage)
        }
    }

    var symbol: String {
        switch self {
        case .natureDocumentary: "binoculars.fill"
        case .sportsCommentator: "megaphone.fill"
        case .noirDetective: "magnifyingglass"
        case .passiveAggressiveHR: "envelope.badge"
        case .medievalHerald: "flag.fill"
        case .overexcitedGPS: "location.fill"
        }
    }

    /// How the model should sound.
    fileprivate var style: String {
        switch self {
        case .natureDocumentary: "a hushed nature-documentary narrator observing a rare animal in the wild"
        case .sportsCommentator: "a breathless sports commentator calling a championship final"
        case .noirDetective: "a weary 1940s noir detective narrating in short, moody sentences"
        case .passiveAggressiveHR: "a passive-aggressive corporate HR email that is secretly very proud"
        case .medievalHerald: "a medieval herald announcing news to the whole kingdom"
        case .overexcitedGPS: "an overexcited GPS voice that is thrilled about every single metre"
        }
    }

    /// Hand-made lines for when the model isn't available.
    fileprivate func fallback(name: String, distance: String) -> RamReelLines {
        switch self {
        case .natureDocumentary:
            RamReelLines(intro: String(localized: "Here, in the wild, we observe \(name).", bundle: .appLanguage, locale: .appLanguage),
                         fact: String(localized: "Over \(distance), the ram moves with quiet purpose.", bundle: .appLanguage, locale: .appLanguage),
                         closer: String(localized: "Truly, nature at its fluffiest.", bundle: .appLanguage, locale: .appLanguage))
        case .sportsCommentator:
            RamReelLines(intro: String(localized: "And here comes \(name) down the final stretch!", bundle: .appLanguage, locale: .appLanguage),
                         fact: String(localized: "\(distance) on the board. The crowd is going wild!", bundle: .appLanguage, locale: .appLanguage),
                         closer: String(localized: "Absolutely unbelievable scenes.", bundle: .appLanguage, locale: .appLanguage))
        case .noirDetective:
            RamReelLines(intro: String(localized: "The name was \(name). Trouble followed. Slowly.", bundle: .appLanguage, locale: .appLanguage),
                         fact: String(localized: "\(distance) of rain-slicked road. Nobody asked why.", bundle: .appLanguage, locale: .appLanguage),
                         closer: String(localized: "The letter got through. It always does.", bundle: .appLanguage, locale: .appLanguage))
        case .passiveAggressiveHR:
            RamReelLines(intro: String(localized: "Just circling back on \(name)'s performance.", bundle: .appLanguage, locale: .appLanguage),
                         fact: String(localized: "Per my last email, \(distance) has been walked. Great job, I guess.", bundle: .appLanguage, locale: .appLanguage),
                         closer: String(localized: "Kindly keep trotting. Best regards.", bundle: .appLanguage, locale: .appLanguage))
        case .medievalHerald:
            RamReelLines(intro: String(localized: "Hear ye! Hear ye! Behold, \(name)!", bundle: .appLanguage, locale: .appLanguage),
                         fact: String(localized: "\(distance) hath been trod upon the kingdom's roads!", bundle: .appLanguage, locale: .appLanguage),
                         closer: String(localized: "Long live the ram. Long live the post.", bundle: .appLanguage, locale: .appLanguage))
        case .overexcitedGPS:
            RamReelLines(intro: String(localized: "Recalculating… oh! It is \(name)!", bundle: .appLanguage, locale: .appLanguage),
                         fact: String(localized: "\(distance) travelled! Keep going! Keep going!", bundle: .appLanguage, locale: .appLanguage),
                         closer: String(localized: "You have arrived. Please arrive again.", bundle: .appLanguage, locale: .appLanguage))
        }
    }
}

struct RamReelLines: Sendable {
    let intro: String
    let fact: String
    let closer: String
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct GeneratedReel {
    @Guide(description: "One short line introducing the ram by name, at most 10 words.")
    var intro: String
    @Guide(description: "One or two short sentences about the distance walked, using the exact distance given, at most 22 words.")
    var fact: String
    @Guide(description: "One short closing line, at most 10 words.")
    var closer: String
}
#endif

@MainActor
enum RamReelWriter {
    /// A fresh narrator and fresh lines. `previous` is skipped so a remix
    /// never repeats the voice you just saw.
    static func write(for data: RamReelData, avoiding previous: RamReelVoice? = nil, using chosen: RamReelVoice? = nil) async -> RamReelData {
        let voice = chosen ?? RamReelVoice.allCases.filter { $0 != previous }.randomElement() ?? .natureDocumentary
        let distance = DistanceFormatter.string(forMeters: data.totalMeters)
        var lines: RamReelLines
        if let written = await generated(voice: voice, data: data, distance: distance) {
            lines = written
        } else {
            // No Apple Intelligence: the narrator's hand-made intro and
            // closer, plus one of the five stock comparisons (giraffes,
            // football fields, Eiffel Towers, seawall laps, marathons) that
            // the distance actually reaches, so reels still differ.
            lines = voice.fallback(name: data.ramName, distance: distance)
            let reached = DistanceComparison.allCases.filter { Double(data.totalMeters) / $0.meters >= 1 }
            if data.totalMeters > 0, let pick = reached.randomElement() {
                lines = RamReelLines(intro: lines.intro, fact: pick.sentence(for: data.totalMeters), closer: lines.closer)
            }
        }
        return data.withVoice(voice, lines: lines, variant: Int.random(in: 0..<ReelTheme.all.count))
    }

    private static func generated(voice: RamReelVoice, data: RamReelData, distance: String) async -> RamReelLines? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), LetterMuseService.isSupported, data.totalMeters > 0 else { return nil }
        guard AppLanguage.code.hasPrefix("en") else { return nil }
        let session = LanguageModelSession(instructions: """
            You write the captions of a short, funny social video about a courier ram that delivers letters on foot. \
            Write in the voice of \(voice.style). Keep it warm, clever and family-friendly. \
            Use only the facts given: never invent places, numbers, people or events. No emoji, no hashtags. \
            \(AppLanguage.modelInstruction)
            """)
        var facts = "Ram name: \(data.ramName). Distance walked: \(distance). Personality: \(data.personality.title)."
        if !data.places.isEmpty { facts += " Places it passed: \(data.places.suffix(3).joined(separator: ", "))." }
        if let goal = data.goal {
            facts += " Mission the owner wrote for the ram: \"\(goal)\" (\(data.goalDone ? "completed" : "still in progress")). The fact and closer lines should nod to this mission."
        }
        do {
            let response = try await session.respond(
                to: "\(facts) Write the three captions.",
                generating: GeneratedReel.self,
                options: GenerationOptions(temperature: 1.0)
            )
            let reel = response.content
            let lines = RamReelLines(
                intro: reel.intro.trimmingCharacters(in: .whitespacesAndNewlines),
                fact: reel.fact.trimmingCharacters(in: .whitespacesAndNewlines),
                closer: reel.closer.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            // A caption that came back empty, or in the wrong language,
            // falls back to the hand-made (translated) set.
            let all = [lines.intro, lines.fact, lines.closer]
            guard !all.contains(where: \.isEmpty),
                  AppLanguage.isInAppLanguage(all.joined(separator: " "))
            else { return nil }
            return lines
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
