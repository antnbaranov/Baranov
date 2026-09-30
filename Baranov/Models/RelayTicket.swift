//
//  RelayTicket.swift
//  Baranov
//
//  What a tracked letter carries so the post office can follow it.
//
//  - `RelayTicket`: the relay lookup id (one-way from the letter code, see
//    `LetterCode`) and a random progress token. The relay keeps only a hash
//    of the token; whichever phone is carrying the ram presents it to report
//    progress and, at the gate, to hand the delivered letter over. It rides
//    inside the `.ram`, so a letter passed to a courier keeps reporting from
//    the courier's phone.
//
//  - `RecipientKey`: the letter code sealed to the recipient's profile key
//    with HPKE (`LetterKeyWrap`). The same sealed blob the relay's inbox
//    carries, so one wrap serves both the relay and an offline AirDrop.
//

import Foundation

struct RelayTicket: Codable, Hashable, Sendable {
    /// The id the relay files the letter under.
    let lookupID: String
    /// Shown to the relay on every progress report; only its hash is stored there.
    let progressToken: String

    /// A fresh ticket for a letter whose code is `code`.
    static func issue(forCode code: String) -> RelayTicket {
        var bytes = [UInt8](repeating: 0, count: 32)
        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max, using: &generator) }
        let token = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return RelayTicket(lookupID: LetterCode.lookupID(for: code), progressToken: token)
    }
}

struct RecipientKey: Codable, Hashable, Sendable {
    /// The recipient's profile address (10 characters, no dash).
    let address: String
    /// The relay lookup id the wrap is bound to.
    let lookupID: String
    let wrapped: WrappedLetterKey
}
