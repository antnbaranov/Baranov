//
//  SavedRecipientCode.swift
//  Baranov
//
//  A Shepherd ID worth keeping — someone whose code you'll send to again
//  ("Send by Code" in Compose), saved once so it's a tap instead of a
//  re-typed ABCDE-FGHJK every time. Everything beyond the code and a name
//  is optional: where you met them, and a note, both purely for the
//  sender's own memory — never sent anywhere, never shown to the
//  recipient.
//

import Foundation

struct SavedRecipientCode: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// The formatted Shepherd ID, e.g. "ABCDE-FGHJK".
    var code: String
    /// Where you met them, or where you'd hand off — a place name only;
    /// the coordinate is kept alongside it so it can be shown on a map
    /// later, but nothing here is the recipient's own live location.
    var locationName: String?
    var locationCoordinate: RamCoordinate?
    var notes: String?
    var createdAt: Date
    /// Their profile public key (base64), cached the last time the relay was
    /// asked, so a letter written offline can still be sealed to them.
    var publicKey: String?

    init(
        id: UUID = UUID(),
        name: String,
        code: String,
        locationName: String? = nil,
        locationCoordinate: RamCoordinate? = nil,
        notes: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.code = code
        self.locationName = locationName
        self.locationCoordinate = locationCoordinate
        self.notes = notes
        self.createdAt = createdAt
    }
}
