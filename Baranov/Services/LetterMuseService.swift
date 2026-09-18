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
            if case .available = SystemLanguageModel.default.availability {
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
        let month = Date().formatted(.dateTime.month(.wide))
        let session = LanguageModelSession(instructions: """
            You help someone start a handwritten-style letter that will be carried slowly, on foot, by a virtual ram. \
            Reply with exactly one sentence, under 22 words, in the second person, suggesting one concrete thing they could write about. \
            Do not write the letter. Do not use quotation marks, emoji, exclamation marks, or the word "journey". \
            Be warm, specific and plain.
            """)
        let prompt = """
            The letter is from \(context.senderName.isEmpty ? "the sender" : context.senderName) to \(context.recipientName.isEmpty ? "someone" : context.recipientName). \
            It leaves \(context.originCity.isEmpty ? "here" : context.originCity) for \(context.destinationCity) — about \(distance) of walking\(context.needsHandoff ? ", then a hand-off across water" : ""). \
            It is \(month). Suggest one thing to write about.
            """
        do {
            let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.9))
            return Self.cleaned(response.content)
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
            let when = stamp.timestamp.formatted(.dateTime.day().month(.abbreviated))
            return "\(stamp.kind.rawValue) at \(stamp.placeName) on \(when), carried by \(stamp.carrierName), \(DistanceFormatter.string(forMeters: stamp.stepsAtStamp)) into the walk"
        }.joined(separator: "; ")

        let session = LanguageModelSession(instructions: """
            You write the short travelogue stamped inside a letter's passport. \
            Reply with two or three plain sentences, under 70 words total, past tense, third person, naming the real places and carriers given. \
            Do not invent places, people, weather or events. No emoji, no exclamation marks, no headings.
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

    /// Strips the quotation marks and stray whitespace models like to add.
    private static func cleaned(_ text: String) -> String? {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'"))
        return trimmed.isEmpty ? nil : trimmed
    }
}
