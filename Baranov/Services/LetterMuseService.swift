//
//  LetterMuseService.swift
//  Baranov
//
//  Apple's on-device foundation model (iOS 26, `FoundationModels`), used
//  for the two things a slow post can honestly use a language model for —
//  and pointedly *not* for writing the letter:
//
//  1. **A nudge for the blank page.** One sentence, written for *this*
//     letter: who it's to, where it's going, how far the ram will walk,
//     what season it is. Never a template; the person writes every word.
//  2. **The road, told.** When a letter is opened, its passport stamps —
//     the real places the ram passed and who carried it — become two or
//     three sentences of travelogue under the letter.
//
//  Everything runs on the device; nothing leaves it. The letter body is
//  never given to the model at all — only names, places and distances.
//  On iOS 18 and on devices without Apple Intelligence, `isSupported` is
//  false and every call returns `nil`, and the app reads exactly as it
//  did before: static prompts, a plain stamp list.
//

import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

@Observable
@MainActor
final class LetterMuseService {

    /// Whether the on-device model can be used right now — false on iOS 18,
    /// on devices without Apple Intelligence, while the model is still
    /// downloading, or when the person has it switched off.
    static var isSupported: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            // Also needs to write the app's language; otherwise the
            // translated static text reads better than an English reply.
            if case .available = SystemLanguageModel.default.availability,
               AppLanguage.modelSupportsAppLanguage {
                return true
            }
        }
        #endif
        return false
    }

    /// What a nudge is written from. No letter text, ever.
    struct LetterContext: Sendable, Equatable {
        var recipientName: String
        var senderName: String
        var destinationCity: String
        var originCity: String
        var distanceMeters: Int
        var needsHandoff: Bool
    }

    private(set) var isThinking = false

    /// One sentence for the blank page, or `nil` when the model isn't
    /// available or declines — the caller falls back to its static prompts.
    func nudge(for context: LetterContext) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), Self.isSupported else { return nil }
        isThinking = true
        defer { isThinking = false }

        let distance = DistanceFormatter.string(forMeters: context.distanceMeters)
        let month = Date().formatted(.dateTime.month(.wide).locale(Locale(identifier: "en")))
        let session = LanguageModelSession(instructions: """
            You give a spark for a letter, never the letter. \
            Reply with ONE short sentence of at most 15 words, in the second person, naming one thing to write about or ask. \
            No greeting, no sign-off, no quotation marks, no emoji, no second sentence. \
            \(AppLanguage.modelInstruction)
            """)
        let prompt = """
            Letter to \(context.recipientName.isEmpty ? "someone" : context.recipientName) in \(context.destinationCity), \
            about \(distance) away. Month: \(month). One-line idea only.
            """
        do {
            // A hard token cap is what keeps this instant: the model
            // physically cannot ramble into a draft of the letter.
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(temperature: 0.9, maximumResponseTokens: 36)
            )
            return Self.spark(response.content)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Two or three sentences telling the road from the passport stamps,
    /// or `nil` when the model isn't available.
    func narrate(ram: Ram, stamps: [JourneyStamp]) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), Self.isSupported, !stamps.isEmpty else { return nil }
        isThinking = true
        defer { isThinking = false }

        let legs = stamps.map { stamp -> String in
            let when = stamp.timestamp.formatted(.dateTime.day().month(.abbreviated).locale(.appLanguage))
            let weatherPart = stamp.weather.map { w in
                ", \(Int(w.temperatureCelsius.rounded()))°C and \(w.condition.lowercased())"
            } ?? ""
            return "\(stamp.kind.rawValue) at \(stamp.displayPlaceName) on \(when), carried by \(stamp.carrierName), \(DistanceFormatter.string(forMeters: stamp.stepsAtStamp)) into the walk\(weatherPart)"
        }.joined(separator: "; ")

        let session = LanguageModelSession(instructions: """
            You write the short travelogue stamped inside a letter's passport. \
            Reply with two or three plain sentences, under 70 words total, past tense, third person, naming the real places and carriers given. \
            When a stop has a temperature and condition, you may weave it in naturally (e.g. the weather it walked through), but only using the exact figures given. \
            Do not invent places, people, weather or events. No emoji, no exclamation marks, no headings. \
            \(AppLanguage.modelInstruction)
            """)
        let prompt = """
            The ram \(ram.name) carried a letter from \(ram.letter?.senderName ?? "the sender") to \(ram.letter?.recipientName ?? "the recipient"), \
            setting out from \(ram.routeHistory.first?.cityName ?? ram.currentCity) toward \(ram.targetCity). \
            Its passport stamps, in order: \(legs). Tell the road.
            """
        do {
            let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.6))
            return Self.cleaned(response.content)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    /// One fresh, playful sentence comparing the distance walked to something
    /// you can picture (or, at 0 m, teasing a ram that hasn't left the pen).
    /// `nil` when the model isn't available or declines.
    func compare(ramName: String, totalMeters: Int, avoiding previous: String?) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), Self.isSupported else { return nil }
        isThinking = true
        defer { isThinking = false }

        let session = LanguageModelSession(instructions: """
            You write one witty, gentle line for a ram's travel passport. \
            Reply with ONE sentence of at most 22 words. \
            If the distance is above zero, compare it to a real, well-known thing of matching size with a correct rough number. \
            If the distance is zero, tease the ram for not having left yet. \
            No quotation marks, no emoji, no second sentence. \
            \(AppLanguage.modelInstruction)
            """)
        let distance = DistanceFormatter.string(forMeters: totalMeters)
        var prompt = "The ram \(ramName) has walked \(totalMeters > 0 ? distance : "0 m")."
        if let previous, !previous.isEmpty { prompt += " Say it differently from: \(previous)" }
        do {
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(temperature: 1.0, maximumResponseTokens: 50)
            )
            return Self.spark(response.content)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    /// One short line: first sentence only, at most 20 words.
    private static func spark(_ text: String) -> String? {
        guard let line = cleaned(text) else { return nil }
        let firstLine = line.split(whereSeparator: \.isNewline).first.map(String.init) ?? line
        var sentence = firstLine
        if let end = firstLine.firstIndex(where: { ".!?".contains($0) }) {
            sentence = String(firstLine[...end])
        }
        let words = sentence.split(separator: " ")
        if words.count > 20 {
            sentence = words.prefix(20).joined(separator: " ") + "…"
        }
        return cleaned(sentence)
    }

    /// Strips the quotation marks and stray whitespace models like to add.
    /// Also drops a reply that came back in the wrong language, so the
    /// caller shows its translated fallback instead.
    private static func cleaned(_ text: String) -> String? {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'«»„"))
        guard !trimmed.isEmpty, AppLanguage.isInAppLanguage(trimmed) else { return nil }
        return trimmed
    }
}
