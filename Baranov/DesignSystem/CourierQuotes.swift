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
    /// Computed so the sayings follow the language picked in the app.
    static var all: [CourierQuote] { [
        .init(text: String(localized: "A journey of a thousand miles begins with a single step.", bundle: .appLanguage, locale: .appLanguage), source: String(localized: "Lao Tzu", bundle: .appLanguage, locale: .appLanguage)),
        .init(text: String(localized: "Hasten slowly.", bundle: .appLanguage, locale: .appLanguage), source: String(localized: "Festina lente", bundle: .appLanguage, locale: .appLanguage)),
        .init(text: String(localized: "Slow and steady wins the race.", bundle: .appLanguage, locale: .appLanguage), source: String(localized: "Aesop", bundle: .appLanguage, locale: .appLanguage)),
        .init(text: String(localized: "It does not matter how slowly you go, as long as you do not stop.", bundle: .appLanguage, locale: .appLanguage), source: String(localized: "Proverb", bundle: .appLanguage, locale: .appLanguage)),
        .init(text: String(localized: "Patience is bitter, but its fruit is sweet.", bundle: .appLanguage, locale: .appLanguage), source: String(localized: "Proverb", bundle: .appLanguage, locale: .appLanguage)),
        .init(text: String(localized: "The road is made by walking.", bundle: .appLanguage, locale: .appLanguage), source: String(localized: "Proverb", bundle: .appLanguage, locale: .appLanguage)),
        .init(text: String(localized: "Little by little, one travels far.", bundle: .appLanguage, locale: .appLanguage), source: String(localized: "Proverb", bundle: .appLanguage, locale: .appLanguage)),
        .init(text: String(localized: "Drop by drop, the bucket fills.", bundle: .appLanguage, locale: .appLanguage), source: String(localized: "Proverb", bundle: .appLanguage, locale: .appLanguage)),
        .init(text: String(localized: "Good things come to those who wait.", bundle: .appLanguage, locale: .appLanguage), source: String(localized: "Proverb", bundle: .appLanguage, locale: .appLanguage)),
        .init(text: String(localized: "Rome was not built in a day.", bundle: .appLanguage, locale: .appLanguage), source: String(localized: "Proverb", bundle: .appLanguage, locale: .appLanguage)),
        .init(text: String(localized: "He who walks with the wise grows wise.", bundle: .appLanguage, locale: .appLanguage), source: String(localized: "Proverb", bundle: .appLanguage, locale: .appLanguage)),
        .init(text: String(localized: "Do not hurry; the letter will arrive when it arrives.", bundle: .appLanguage, locale: .appLanguage), source: "Baranov"),
    ] }

    /// One saying per day, moved along by `offset` when the person taps for another.
    static func quote(on date: Date = .now, offset: Int = 0) -> CourierQuote {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        let index = ((day + offset) % all.count + all.count) % all.count
        return all[index]
    }
}
