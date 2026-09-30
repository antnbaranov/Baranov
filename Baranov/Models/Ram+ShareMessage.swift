//
//  Ram+ShareMessage.swift
//  Baranov
//
//  The code message the sender shares, now with a link that tells the
//  recipient's Baranov a letter is on its way — who from, which ram,
//  where to and roughly when (see `ExpectedLetter`).
//

import Foundation

extension Ram {
    /// Rough arrival at the carrier's usual pace. Only a hint: carriers
    /// change and the packet sails on its own clock.
    var expectedArrival: Date? {
        guard status == .grazing || status == .walking || status == .waitingForHandoff || status == .atSea else { return nil }
        if status == .atSea, let voyage { return voyage.arrivesAt }
        let days = WalkingPaceService.days(toWalk: Double(remainingSteps), dailySteps: WalkingPaceService.cachedDailySteps)
        return Calendar.current.date(byAdding: .day, value: days, to: Date())
    }

    /// What the sender sends the recipient: the tracking link for a letter
    /// the post office follows, otherwise the code message plus the "on its
    /// way" link.
    var letterShareMessage: String? {
        guard let letter else { return nil }
        if let tracked = letter.trackingShareMessage(ramName: name, city: targetCity, expectedBy: expectedArrival) {
            return tracked
        }
        guard let message = letter.shareMessage(carrierName: name) else { return nil }
        guard let link = ExpectedLetter.link(
            letterID: letter.id,
            senderName: letter.senderName,
            ramName: name,
            city: targetCity,
            expectedBy: expectedArrival,
            code: letter.receivingCode
        ) else { return message }
        return message + "\n\n" + String(localized: "Follow it in Baranov: \(link.absoluteString)", bundle: .appLanguage, locale: .appLanguage)
    }
}

extension Letter {
    /// The message for a letter whose recipient's gate isn't known yet:
    /// opening the link tells the sender's ram where to walk.
    func awaitingGateShareMessage(ramName: String) -> String? {
        guard relayTicket != nil, let code = SealKeyVault.code(for: id),
              let link = ExpectedLetter.link(letterID: id, senderName: senderName, ramName: ramName,
                                             city: "", expectedBy: nil, code: code) else { return nil }
        let formatted = LetterCode.format(code)
        return String(localized: "\(senderName) sent you a letter. Open this link so \(ramName) knows where your gate is, then follow it in Baranov: \(link.absoluteString)\n\nYour ear tag, if the app asks: \(formatted)", bundle: .appLanguage, locale: .appLanguage)
    }

    /// The tracking message for a letter the post office follows: a link that
    /// puts an incoming card on the recipient's phone, and the ear tag for
    /// anyone who'd rather type it. `nil` for an untracked letter, or on any
    /// phone that doesn't hold the ear tag (a courier).
    func trackingShareMessage(ramName: String, city: String, expectedBy: Date?) -> String? {
        guard relayTicket != nil, let code = SealKeyVault.code(for: id),
              let link = ExpectedLetter.link(letterID: id, senderName: senderName, ramName: ramName,
                                             city: city, expectedBy: expectedBy, code: code) else { return nil }
        let formatted = LetterCode.format(code)
        return String(localized: "\(senderName) sent you a letter. \(ramName) is walking it to \(city). Follow it in Baranov, and it lands in your mailbag when \(ramName) gets there: \(link.absoluteString)\n\nYour ear tag, if the app asks: \(formatted)", bundle: .appLanguage, locale: .appLanguage)
    }
}
