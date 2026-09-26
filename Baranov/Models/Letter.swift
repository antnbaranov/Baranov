//
//  Letter.swift
//  Baranov
//
//  The encrypted digital letter a ram carries — and "encrypted" here is
//  literal. `sealedBody` is ChaCha20-Poly1305 ciphertext (see
//  `LetterCipher`); the plaintext never appears in a `.ram` transit
//  package, in the flock cache, or on any phone that merely relays the
//  ram. It only ever exists on the sender's screen while they write it,
//  and on the recipient's screen after they break the seal with the
//  letter's receiving code.
//
//  `receivingCode` is that key: a short, human-typeable code generated
//  the moment a letter is written. It is NOT a stored property — it lives
//  in the Keychain (`SealKeyVault`) on the device that wrote the letter,
//  and on the recipient's device once they've typed it in — so it is
//  never serialized alongside the ciphertext it unlocks. The sender
//  shares it out of band (`shareMessage(carrierName:)`, most naturally
//  over iMessage).
//
//  `isSealed` gates the wax-seal long-press reveal ritual on arrival — it
//  starts true and flips to false only when the recipient performs that
//  gesture with the right code.
//
//  Not every letter is encrypted. `Letter.writeOpen` makes an *open
//  postcard* — plain text on the wire, readable by every shepherd who
//  carries it, no code at the gate. `isEncrypted` tells the two apart;
//  the sender chooses at compose time by either pressing a wax seal into
//  the letter or leaving it open.
//
//  Three paid-only locks, each independent and each optional, gate a
//  sealed letter's decryption on top of the receiving code itself:
//
//  - `unlockAt` (Time-Capsule): won't decrypt before this moment, even
//    with the right code.
//  - `geofence` (Geo-Lock): won't decrypt until the device is physically
//    within `geofence.radiusMeters` of a point the sender chose.
//  - `sealedScratchSecret` (Scratch-Off Secret): a second, short line
//    that decrypts alongside the body but stays hidden behind a
//    scratchable foil on screen (`ScratchOffRevealView`) even after the
//    seal itself is broken — a reveal-within-a-reveal.
//
//  None of these apply to an open postcard: postcards have no receiving
//  code to hang a lock on, and are the deliberately low-ceremony tier —
//  every extra lock here is something a subscriber adds to a *sealed*
//  letter, never a new way to gate reading one at all (see
//  `PasturePaywallView`'s "no letter is ever behind this screen").
//

import CoreLocation
import Foundation

struct Letter: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let senderName: String
    let recipientName: String
    /// ChaChaPoly combined box (nonce + ciphertext + tag) of the message.
    let sealedBody: Data
    /// The plaintext, present only after the seal has been broken on this
    /// device. Persisted locally so a delivered letter stays readable in
    /// the Pasture; a delivered ram is never handed off, so this never
    /// crosses to another phone.
    private(set) var revealedBody: String?
    var isSealed: Bool
    let createdAt: Date
    /// The wax this letter was sealed with.
    var sealColor: SealColor
    /// Optional photo (JPEG, possibly doodled on). Ciphertext for a
    /// wax-sealed letter, plain for an open postcard — like the body.
    private(set) var attachment: Data?
    /// The photo's plain bytes, once this device may show it.
    private(set) var revealedAttachment: Data?
    /// The paper it travels on; purely visual.
    var paper: EnvelopePaper = .cream
    /// `#RRGGBB` picked on the colour wheel; overrides `paper` when set.
    var paperCustomHex: String?

    /// Time-Capsule (paid). `nil` means no time lock. See `isTimeLocked`.
    private(set) var unlockAt: Date?
    /// Geo-Lock (paid). `nil` means no geo-lock. See `isOutsideGeofence(of:)`.
    private(set) var geofence: LetterGeofence?
    /// Scratch-Off Secret (paid): sealed exactly like `attachment`, under
    /// the same per-letter key, so it travels as ciphertext and decrypts
    /// the moment the main seal breaks — it just isn't *shown* yet.
    private(set) var sealedScratchSecret: Data?
    /// The secret line's plain text, once this device may show it. Still
    /// hidden behind the scratch-off foil in the UI even once this is
    /// set — `hasScratchedSecret` (view-local, not persisted) is what
    /// actually reveals it on screen.
    private(set) var revealedScratchSecret: String?

    // MARK: - Writing a letter

    /// Writes an *open postcard*: a letter that travels unencrypted, in
    /// plain text, so anyone carrying the ram can read it and the
    /// recipient needs no receiving code at the gate. There is no key
    /// and nothing goes in `SealKeyVault`. The arrival ritual still runs
    /// (`isSealed` starts true) — the recipient lifts the postcard out of
    /// the satchel — it just opens without a code.
    ///
    /// No Time-Capsule, Geo-Lock, or Scratch-Off Secret here: those hang
    /// off the receiving code a postcard doesn't have.
    static func writeOpen(
        senderName: String,
        recipientName: String,
        messageBody: String,
        attachment: Data? = nil
    ) -> Letter {
        Letter(
            id: UUID(),
            senderName: senderName,
            recipientName: recipientName,
            openBody: messageBody,
            createdAt: Date(),
            attachment: attachment
        )
    }

    private init(
        id: UUID,
        senderName: String,
        recipientName: String,
        openBody: String,
        createdAt: Date,
        attachment: Data?
    ) {
        self.id = id
        self.senderName = senderName
        self.recipientName = recipientName
        self.sealedBody = Data()
        self.revealedBody = openBody
        self.isSealed = true
        self.createdAt = createdAt
        self.sealColor = .crimson
        self.attachment = attachment
        self.revealedAttachment = attachment
    }

    /// Writes and seals a brand-new letter. The receiving code is minted
    /// here, stored in `SealKeyVault` for the sender, and returned so the
    /// caller can hand it on — it is not kept on the letter itself.
    static func write(
        senderName: String,
        recipientName: String,
        messageBody: String,
        sealColor: SealColor = .crimson,
        attachment: Data? = nil,
        unlockAt: Date? = nil,
        geofence: LetterGeofence? = nil,
        scratchSecret: String? = nil
    ) -> (letter: Letter, receivingCode: String) {
        let code = generateReceivingCode()
        let letter = Letter(
            senderName: senderName,
            recipientName: recipientName,
            messageBody: messageBody,
            receivingCode: code,
            sealColor: sealColor,
            attachment: attachment,
            unlockAt: unlockAt,
            geofence: geofence,
            scratchSecret: scratchSecret
        )
        SealKeyVault.store(code, for: letter.id)
        return (letter, code)
    }

    /// Seals `messageBody` with `receivingCode`. Pass `isSealed: false`
    /// only for a letter that should start out open (previews, an
    /// already-delivered fixture) — its plaintext, attachment and
    /// scratch secret are then kept revealed too, and its locks (if any)
    /// are assumed already satisfied.
    init(
        id: UUID = UUID(),
        senderName: String,
        recipientName: String,
        messageBody: String,
        isSealed: Bool = true,
        createdAt: Date = Date(),
        receivingCode: String,
        sealColor: SealColor = .crimson,
        attachment: Data? = nil,
        unlockAt: Date? = nil,
        geofence: LetterGeofence? = nil,
        scratchSecret: String? = nil
    ) {
        self.id = id
        self.senderName = senderName
        self.recipientName = recipientName
        self.isSealed = isSealed
        self.createdAt = createdAt
        self.sealColor = sealColor
        self.unlockAt = unlockAt
        self.geofence = geofence
        // Sealing can only fail if CryptoKit itself fails to seal a few
        // bytes with a fresh key — not a condition worth crashing a letter
        // over; an empty body simply reads as an empty letter.
        self.sealedBody = (try? LetterCipher.seal(messageBody, receivingCode: receivingCode, letterID: id)) ?? Data()
        self.revealedBody = isSealed ? nil : messageBody
        self.attachment = attachment.flatMap {
            try? LetterCipher.sealData($0, receivingCode: receivingCode, letterID: id)
        }
        self.revealedAttachment = isSealed ? nil : attachment
        self.sealedScratchSecret = scratchSecret.flatMap {
            try? LetterCipher.sealData(Data($0.utf8), receivingCode: receivingCode, letterID: id)
        }
        self.revealedScratchSecret = isSealed ? nil : scratchSecret
    }

    // MARK: - Reading a letter

    /// The message, if the seal has been broken on this device; empty
    /// while the letter is still sealed.
    var messageBody: String { revealedBody ?? "" }

    /// Whether this device holds the plaintext — either it broke the seal
    /// or the letter arrived already open.
    var isReadable: Bool { revealedBody != nil }

    /// Whether the body travels as ciphertext (a wax-sealed letter) or in
    /// the clear (an open postcard, or a legacy pre-encryption letter).
    /// Only an encrypted letter has a receiving code.
    var isEncrypted: Bool { !sealedBody.isEmpty }

    /// A short impression of the ciphertext, like the pattern pressed
    /// into wax — the same on every phone the ram passes through.
    var sealFingerprint: String { LetterCipher.fingerprint(of: sealedBody) }

    /// The receiving code, if this device holds it (it wrote the letter,
    /// or the recipient typed it in at the gate). `nil` on any phone that
    /// is only carrying the ram.
    var receivingCode: String? {
        guard isEncrypted else { return nil }
        return SealKeyVault.code(for: id)
    }

    /// Whether this letter carries any paid lock beyond the receiving
    /// code itself — used by the arrival screen to decide whether it
    /// needs to show a countdown, a "get closer" prompt, or neither.
    var hasExtraLock: Bool { unlockAt != nil || geofence != nil }

    /// Whether a Time-Capsule letter's clock hasn't struck yet. Always
    /// `false` for a letter with no `unlockAt`.
    var isTimeLocked: Bool {
        guard let unlockAt else { return false }
        return Date() < unlockAt
    }

    /// Whether a Geo-Lock letter's recipient is still too far from the
    /// drop point to open it. `coordinate == nil` (no location fix yet)
    /// counts as "still outside" — the lock fails closed, never open, on
    /// a missing fix. Always `false` for a letter with no `geofence`.
    func isOutsideGeofence(of coordinate: CLLocationCoordinate2D?) -> Bool {
        guard let geofence else { return false }
        guard let coordinate else { return true }
        return !geofence.contains(coordinate)
    }

    /// How far the recipient still has to travel to satisfy a Geo-Lock,
    /// or `nil` when there's no geofence, no location fix, or they're
    /// already inside the radius.
    func geofenceDistanceRemaining(from coordinate: CLLocationCoordinate2D?) -> CLLocationDistance? {
        guard let geofence, let coordinate else { return nil }
        let remaining = geofence.distance(from: coordinate) - geofence.radiusMeters
        return remaining > 0 ? remaining : nil
    }

    /// Whether this letter has a Scratch-Off Secret at all — independent
    /// of whether it's been scratched clear yet, which is view-local
    /// state (`ScratchOffRevealView` never persists "scratched", by
    /// design: the moment is meant to happen once, live).
    var hasScratchSecret: Bool { sealedScratchSecret != nil }

    /// The secret line's plain text, once this device holds it — `nil`
    /// until the seal breaks, exactly like `messageBody`.
    var scratchSecretText: String? { revealedScratchSecret }

    /// Breaks the seal: decrypts the body with `code` and marks the
    /// letter open. Throws `LetterCipherError.wrongCode` if the code
    /// doesn't fit, `.timeLocked` if a Time-Capsule's clock hasn't struck
    /// yet, or `.outsideGeofence` if a Geo-Lock's radius isn't satisfied
    /// — leaving the letter exactly as it was in every failure case.
    ///
    /// `currentCoordinate` only matters when `geofence` is set; pass the
    /// device's best current fix. Omitting it on a geofenced letter fails
    /// closed (`.outsideGeofence(metersAway: nil)`) rather than silently
    /// skipping the check.
    mutating func open(withReceivingCode code: String, currentCoordinate: CLLocationCoordinate2D? = nil) throws {
        if !isEncrypted, revealedBody != nil {
            // An open postcard (or a legacy letter that shipped its
            // plaintext); nothing to decrypt, no locks to check.
            isSealed = false
            return
        }

        if let unlockAt, Date() < unlockAt {
            throw LetterCipherError.timeLocked(until: unlockAt)
        }
        if let geofence {
            guard let currentCoordinate else {
                throw LetterCipherError.outsideGeofence(metersAway: nil)
            }
            guard geofence.contains(currentCoordinate) else {
                throw LetterCipherError.outsideGeofence(metersAway: geofence.distance(from: currentCoordinate))
            }
        }

        let body = try LetterCipher.open(sealedBody, receivingCode: code, letterID: id)
        revealedBody = body
        if let attachment {
            revealedAttachment = try? LetterCipher.openData(attachment, receivingCode: code, letterID: id)
        }
        if let sealedScratchSecret {
            let plain = try? LetterCipher.openData(sealedScratchSecret, receivingCode: code, letterID: id)
            revealedScratchSecret = plain.flatMap { String(data: $0, encoding: .utf8) }
        }
        isSealed = false
        SealKeyVault.store(code, for: id)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, senderName, recipientName, sealedBody, revealedBody, isSealed, createdAt, sealColor, attachment, revealedAttachment, paper, paperCustomHex
        case unlockAt, geofence, sealedScratchSecret, revealedScratchSecret
        // Legacy keys from builds before letters were actually encrypted.
        case messageBody, receivingCode
    }

    /// A hand-written decode so a `.ram` package or cache written by an
    /// older build still lands: those carried `messageBody` in the clear
    /// and had no `sealedBody`/`sealColor`, and every build before the
    /// three paid locks existed simply has none of them. Offline-first
    /// resilience means a letter already mid-journey must keep loading,
    /// not vanish because the wire format grew.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        senderName = try container.decode(String.self, forKey: .senderName)
        recipientName = try container.decode(String.self, forKey: .recipientName)
        isSealed = try container.decode(Bool.self, forKey: .isSealed)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sealColor = try container.decodeIfPresent(SealColor.self, forKey: .sealColor) ?? .crimson
        attachment = try container.decodeIfPresent(Data.self, forKey: .attachment)
        revealedAttachment = try container.decodeIfPresent(Data.self, forKey: .revealedAttachment)
        paper = try container.decodeIfPresent(EnvelopePaper.self, forKey: .paper) ?? .cream
        paperCustomHex = try container.decodeIfPresent(String.self, forKey: .paperCustomHex)
        unlockAt = try container.decodeIfPresent(Date.self, forKey: .unlockAt)
        geofence = try container.decodeIfPresent(LetterGeofence.self, forKey: .geofence)
        sealedScratchSecret = try container.decodeIfPresent(Data.self, forKey: .sealedScratchSecret)
        revealedScratchSecret = try container.decodeIfPresent(String.self, forKey: .revealedScratchSecret)

        if let sealed = try container.decodeIfPresent(Data.self, forKey: .sealedBody) {
            sealedBody = sealed
            revealedBody = try container.decodeIfPresent(String.self, forKey: .revealedBody)
        } else {
            // Legacy plaintext letter.
            sealedBody = Data()
            revealedBody = try container.decodeIfPresent(String.self, forKey: .messageBody) ?? ""
            if let legacyCode = try container.decodeIfPresent(String.self, forKey: .receivingCode) {
                SealKeyVault.store(legacyCode, for: id)
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(senderName, forKey: .senderName)
        try container.encode(recipientName, forKey: .recipientName)
        try container.encode(sealedBody, forKey: .sealedBody)
        try container.encodeIfPresent(revealedBody, forKey: .revealedBody)
        try container.encode(isSealed, forKey: .isSealed)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(sealColor, forKey: .sealColor)
        try container.encodeIfPresent(attachment, forKey: .attachment)
        try container.encodeIfPresent(revealedAttachment, forKey: .revealedAttachment)
        try container.encode(paper, forKey: .paper)
        try container.encodeIfPresent(paperCustomHex, forKey: .paperCustomHex)
        try container.encodeIfPresent(unlockAt, forKey: .unlockAt)
        try container.encodeIfPresent(geofence, forKey: .geofence)
        try container.encodeIfPresent(sealedScratchSecret, forKey: .sealedScratchSecret)
        try container.encodeIfPresent(revealedScratchSecret, forKey: .revealedScratchSecret)
    }

    // MARK: - Receiving codes

    /// A fresh letter code — the one code that both finds the letter at the
    /// relay and opens its seal (see `LetterCode`).
    static func generateReceivingCode() -> String {
        LetterCode.generate()
    }

    /// A ready-to-send message handing this letter's receiving code to
    /// its recipient — the copy `ShareLink` hands to the system share
    /// sheet (Messages included). `nil` when this device doesn't hold
    /// the code, which is exactly the case for anyone merely relaying
    /// the ram.
    func shareMessage(carrierName: String) -> String? {
        guard let receivingCode else { return nil }
        return "\(carrierName) is carrying a letter to you from \(senderName). When it arrives, hold the seal and use this code to open it: \(receivingCode)"
    }
}
