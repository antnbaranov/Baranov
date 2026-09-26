//
//  SharingInvitation.swift
//  Baranov
//
//  When to ask, once, whether the person wants to be reachable by people
//  nearby. The three switches behind it (share my location with senders,
//  show nearby senders on the map, open to carry) stay OFF until the person
//  says yes: they change what other people can see, so they are never on
//  by default. This only decides the moment to offer.
//
//  The moment is chosen so the offer lands when its point is obvious:
//  - the third time the app comes to the foreground, by which point they
//    know what the app is for; or
//  - the next time it opens after the first letter left — a person who has
//    just sent something understands why someone else might hand a letter on.
//  Never during the session in which the first letter is sent (that has its
//  own celebration), never before onboarding is done, and never again after
//  it has been shown once, whatever the answer.
//

import Foundation

enum SharingInvitation {
    private static let sessionsKey = "com.baranov.sessionCount"
    private static let letterSessionKey = "com.baranov.firstLetterSession"
    private static let askedKey = "com.baranov.sharingInviteAsked"
    private static let nearbyRadarKey = "com.baranov.nearbyRadar"
    private static let openToCarryKey = "com.baranov.openToCarry"

    /// Foreground sessions before the offer, when no letter has been sent.
    static let sessionsBeforeAsking = 3

    private static var defaults: UserDefaults { .standard }

    /// Count one launch or return from the background.
    static func registerSession() {
        defaults.set(defaults.integer(forKey: sessionsKey) + 1, forKey: sessionsKey)
    }

    /// A letter just left. Remembers which session that was, once.
    static func noteLetterSent() {
        guard defaults.integer(forKey: letterSessionKey) == 0 else { return }
        defaults.set(max(1, defaults.integer(forKey: sessionsKey)), forKey: letterSessionKey)
    }

    static func markAsked() {
        defaults.set(true, forKey: askedKey)
    }

    /// Already sharing something: nothing to ask.
    private static var isAnySwitchOn: Bool {
        defaults.bool(forKey: CarrierPresenceService.shareKey)
            || defaults.bool(forKey: nearbyRadarKey)
            || defaults.bool(forKey: openToCarryKey)
    }

    static var isDue: Bool {
        guard !defaults.bool(forKey: askedKey), !isAnySwitchOn else { return false }
        let sessions = defaults.integer(forKey: sessionsKey)
        if sessions >= sessionsBeforeAsking { return true }
        let letterSession = defaults.integer(forKey: letterSessionKey)
        return letterSession > 0 && sessions > letterSession
    }

    /// "Turn On": the three switches, all changeable later in Settings and Profile.
    static func turnOn() {
        defaults.set(true, forKey: CarrierPresenceService.shareKey)
        defaults.set(true, forKey: nearbyRadarKey)
        defaults.set(true, forKey: openToCarryKey)
    }
}
