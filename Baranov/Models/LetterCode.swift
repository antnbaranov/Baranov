//
//  LetterCode.swift
//  Baranov
//
//  The one code a letter has. It used to be two: a short claim code that
//  fetched the letter from the relay and a separate receiving code that
//  decrypted it. Now a single 12-character code does both, and the two jobs
//  are kept apart by derivation rather than by asking the recipient twice:
//
//  - the DECRYPTION KEY comes from the code through HKDF (`LetterCipher`),
//    and never leaves the device;
//  - the RELAY LOOKUP ID is a different, one-way HKDF output of the same
//    code. The post office files the letter under that id, so it can find a
//    letter for someone who has the code but cannot turn the id back into
//    the code.
//
//  Twelve characters from a 31-symbol alphabet is about 59 bits — long
//  enough that the lookup id cannot practically be ground back into the
//  key, short enough to read aloud in groups of four. Older 8-character
//  receiving codes still open letters already on the phone.
//

import CryptoKit
import Foundation

enum LetterCode {
    static let length = 12

    /// Leaves out characters that are easy to mix up when read off a screen
    /// (`0`/`O`, `1`/`I`/`L`).
    private static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    private static let lookupInfo = Data("com.baranov.letter.lookup.v1".utf8)

    /// A fresh code, grouped `XXXX-XXXX-XXXX`.
    static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        let characters = (0..<length).map { _ in alphabet.randomElement(using: &generator)! }
        return format(String(characters))
    }

    /// Uppercased and stripped to letters and digits, so "abcd-efgh-jkmn",
    /// "ABCD EFGH JKMN" and "ABCDEFGHJKMN" are the same code.
    static func normalize(_ raw: String) -> String {
        LetterCipher.normalize(raw)
    }

    /// Groups of four, as far as the typed text goes: `ABCDEF` → `ABCD-EF`.
    static func format(_ raw: String) -> String {
        let cleaned = Array(normalize(raw).prefix(length))
        return stride(from: 0, to: cleaned.count, by: 4)
            .map { String(cleaned[$0..<min($0 + 4, cleaned.count)]) }
            .joined(separator: "-")
    }

    /// Finds a grouped code (`XXXX-XXXX-XXXX`, with dashes, spaces or dots between the groups) inside
    /// longer text, so pasting the whole message a friend sent — "Your ear tag, if the app asks: …" —
    /// fills the field with just the tag.
    static func extract(from text: String) -> String? {
        let pattern = #"(?<![A-Za-z0-9])[A-Za-z0-9]{4}[-\s.][A-Za-z0-9]{4}[-\s.][A-Za-z0-9]{4}(?![A-Za-z0-9])"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return format(String(text[range]))
    }

    static func isComplete(_ raw: String) -> Bool {
        normalize(raw).count == length
    }

    /// Enough characters to try against a sealed letter. A current code is
    /// `length`; an older receiving code was 8 and still works.
    static func isUsableKey(_ raw: String) -> Bool {
        normalize(raw).count >= 8
    }

    /// The id the relay files this letter under: 32 hex characters, one-way
    /// from the code.
    static func lookupID(for code: String) -> String {
        let material = SymmetricKey(data: Data(normalize(code).utf8))
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: material,
            salt: Data(),
            info: lookupInfo,
            outputByteCount: 16
        )
        return derived.withUnsafeBytes { $0.map { String(format: "%02x", $0) }.joined() }
    }
}
