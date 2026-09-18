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

    // MARK: - Writing a letter

    /// Writes an *open postcard*: a letter that travels unencrypted, in
    /// plain text, so anyone carrying the ram can read it and the
    /// recipient needs no receiving code at the gate. There is no key
    /// and nothing goes in `SealKeyVault`. The arrival ritual still runs
    /// (`isSealed` starts true) — the recipient lifts the postcard out of
    /// the satchel — it just opens without a code.
    static func writeOpen(
        senderName: String,
        recipientName: String,
        messageBody: String
    ) -> Letter {
        Letter(
            id: UUID(),
            senderName: senderName,
            recipientName: recipientName,
            openBody: messageBody,
            createdAt: Date()
        )
    }

    private init(
        id: UUID,
        senderName: String,
        recipientName: String,
        openBody: String,
        createdAt: Date
    ) {
        self.id = id
        self.senderName = senderName
        self.recipientName = recipientName
        self.sealedBody = Data()
        self.revealedBody = openBody
        self.isSealed = true
        self.createdAt = createdAt
        self.sealColor = .crimson
    }

    /// Writes and seals a brand-new letter. The receiving code is minted
    /// here, stored in `SealKeyVault` for the sender, and returned so the
    /// caller can hand it on — it is not kept on the letter itself.
    static func write(
        senderName: String,
        recipientName: String,
        messageBody: String,
        sealColor: SealColor = .crimson
    ) -> (letter: Letter, receivingCode: String) {
        let code = generateReceivingCode()
        let letter = Letter(
            senderName: senderName,
            recipientName: recipientName,
            messageBody: messageBody,
            receivingCode: code,
            sealColor: sealColor
        )
        SealKeyVault.store(code, for: letter.id)
        return (letter, code)
    }

    /// Seals `messageBody` with `receivingCode`. Pass `isSealed: false`
    /// only for a letter that should start out open (previews, an
    /// already-delivered fixture) — its plaintext is then kept as
    /// `revealedBody` too.
    init(
        id: UUID = UUID(),
        senderName: String,
        recipientName: String,
        messageBody: String,
        isSealed: Bool = true,
        createdAt: Date = Date(),
        receivingCode: String,
        sealColor: SealColor = .crimson
    ) {
        self.id = id
        self.senderName = senderName
        self.recipientName = recipientName
        self.isSealed = isSealed
        self.createdAt = createdAt
        self.sealColor = sealColor
        // Sealing can only fail if CryptoKit itself fails to seal a few
        // bytes with a fresh key — not a condition worth crashing a letter
        // over; an empty body simply reads as an empty letter.
        self.sealedBody = (try? LetterCipher.seal(messageBody, receivingCode: receivingCode, letterID: id)) ?? Data()
        self.revealedBody = isSealed ? nil : messageBody
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

    /// Breaks the seal: decrypts the body with `code` and marks the letter
    /// open. Throws `LetterCipherError.wrongCode` if the code doesn't fit,
    /// leaving the letter exactly as it was.
    mutating func open(withReceivingCode code: String) throws {
        if !isEncrypted, revealedBody != nil {
            // An open postcard (or a legacy letter that shipped its
            // plaintext); nothing to decrypt, no code needed.
            isSealed = false
            return
        }
        let body = try LetterCipher.open(sealedBody, receivingCode: code, letterID: id)
        revealedBody = body
        isSealed = false
        SealKeyVault.store(code, for: id)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, senderName, recipientName, sealedBody, revealedBody, isSealed, createdAt, sealColor
        // Legacy keys from builds before letters were actually encrypted.
        case messageBody, receivingCode
    }

    /// A hand-written decode so a `.ram` package or cache written by an
    /// older build still lands: those carried `messageBody` in the clear
    /// and had no `sealedBody`/`sealColor`. Offline-first resilience means
    /// a letter already mid-journey must keep loading, not vanish because
    /// the wire format grew.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        senderName = try container.decode(String.self, forKey: .senderName)
        recipientName = try container.decode(String.self, forKey: .recipientName)
        isSealed = try container.decode(Bool.self, forKey: .isSealed)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sealColor = try container.decodeIfPresent(SealColor.self, forKey: .sealColor) ?? .crimson

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
    }

    // MARK: - Receiving codes

    /// A fresh, human-typeable receiving code — grouped `XXXX-XXXX` for
    /// readability, drawn from an alphabet that leaves out characters
    /// that are easy to mix up when read off a phone screen or typed in
    /// by hand (`0`/`O`, `1`/`I`/`L`).
    static func generateReceivingCode() -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        let characters = (0..<8).map { _ in alphabet.randomElement()! }
        let first = String(characters[0..<4])
        let second = String(characters[4..<8])
        return "\(first)-\(second)"
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
