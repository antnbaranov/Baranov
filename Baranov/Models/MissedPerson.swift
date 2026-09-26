//
//  MissedPerson.swift
//  Baranov
//
//  The one person the new user says they wish they'd written to, chosen
//  on the second onboarding page. It costs nothing to answer and it turns
//  every later screen from "a letter" into "a letter to Grandma": the walk
//  page, the arrival alert preview, and the moment after the first letter
//  is sent all speak about this person until the sender types a real name.
//

import Foundation

enum MissedPerson: String, CaseIterable, Identifiable, Sendable {
    case grandma
    case parents
    case friend
    case partner
    case sibling
    case someone

    static let storageKey = "com.baranov.onboardingMissedPerson"

    var id: String { rawValue }

    /// How the person reads in a sentence ("walks it to Grandma").
    var label: String {
        switch self {
        case .grandma: return String(localized: "Grandma")
        case .parents: return String(localized: "Mom & Dad")
        case .friend: return String(localized: "an old friend")
        case .partner: return String(localized: "someone you love")
        case .sibling: return String(localized: "your sibling")
        case .someone: return String(localized: "someone")
        }
    }

    /// The short chip title.
    var chipTitle: String {
        switch self {
        case .grandma: return String(localized: "Grandma")
        case .parents: return String(localized: "Parents")
        case .friend: return String(localized: "A friend")
        case .partner: return String(localized: "Partner")
        case .sibling: return String(localized: "Sibling")
        case .someone: return String(localized: "Someone else")
        }
    }

    var symbolName: String {
        switch self {
        case .grandma: return "figure.and.child.holdinghands"
        case .parents: return "house.fill"
        case .friend: return "person.2.fill"
        case .partner: return "heart.fill"
        case .sibling: return "person.3.fill"
        case .someone: return "envelope.fill"
        }
    }

    /// The last thing most people actually sent them — the pain, made
    /// specific — and how long ago.
    var lastMessage: (text: String, ago: String) {
        switch self {
        case .grandma: return ("🎂", String(localized: "3 weeks ago"))
        case .parents: return ("ok 👍", String(localized: "2 weeks ago"))
        case .friend: return ("lol we should catch up", String(localized: "2 months ago"))
        case .partner: return ("miss you", String(localized: "yesterday"))
        case .sibling: return ("call me when you're free?", String(localized: "5 weeks ago"))
        case .someone: return ("👍", String(localized: "a while ago"))
        }
    }

    /// The Messages tapback they answered with instead of writing back
    /// (an SF Symbol name), when the last message got one.
    var lastMessageReaction: String? {
        switch self {
        case .friend, .partner, .sibling: return "hand.thumbsup.fill"
        default: return nil
        }
    }

    /// Possessive for "…'s gate": the label itself for a relative, a
    /// neutral word otherwise.
    var possessive: String {
        switch self {
        case .grandma: return String(localized: "Grandma's")
        case .parents: return String(localized: "Mom & Dad's")
        default: return String(localized: "their")
        }
    }
}
