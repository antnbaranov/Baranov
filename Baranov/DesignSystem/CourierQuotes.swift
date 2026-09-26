//
//  CourierQuotes.swift
//  Baranov
//
//  Old sayings about patience, walking and going the distance, shown on
//  the profile under the courier's name. Traditional proverbs and
//  classical sayings only, so nothing here is anyone's copyrighted
//  wording; anything with a disputed source is credited as a proverb.
//

import Foundation

struct CourierQuote: Identifiable, Hashable, Sendable {
    let text: String
    let source: String
    var id: String { text }
}

enum CourierQuotes {
    static let all: [CourierQuote] = [
        .init(text: "A journey of a thousand miles begins with a single step.", source: "Lao Tzu"),
        .init(text: "Hasten slowly.", source: "Festina lente"),
        .init(text: "Slow and steady wins the race.", source: "Aesop"),
        .init(text: "It does not matter how slowly you go, as long as you do not stop.", source: "Proverb"),
        .init(text: "Patience is bitter, but its fruit is sweet.", source: "Proverb"),
        .init(text: "The road is made by walking.", source: "Proverb"),
        .init(text: "Little by little, one travels far.", source: "Proverb"),
        .init(text: "Drop by drop, the bucket fills.", source: "Proverb"),
        .init(text: "Good things come to those who wait.", source: "Proverb"),
        .init(text: "Rome was not built in a day.", source: "Proverb"),
        .init(text: "He who walks with the wise grows wise.", source: "Proverb"),
        .init(text: "Do not hurry; the letter will arrive when it arrives.", source: "Baranov"),
    ]

    /// One saying per day, moved along by `offset` when the person taps for another.
    static func quote(on date: Date = .now, offset: Int = 0) -> CourierQuote {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        let index = ((day + offset) % all.count + all.count) % all.count
        return all[index]
    }
}
