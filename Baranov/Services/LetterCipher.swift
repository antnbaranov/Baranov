//
//  LetterCipher.swift
//  Baranov
//
//  The part that makes "encrypted letter" literally true rather than a
//  figure of speech. A letter's body exists on the wire — inside a `.ram`
//  transit package, on another shepherd's phone mid-relay, in the flock
//  cache on disk — only as ChaCha20-Poly1305 ciphertext. The key is
//  derived from the letter's receiving code, which never travels with the
//  ram: the sender keeps it in `SealKeyVault` and hands it to the
//  recipient out of band (iMessage, in person, however they like), so
//  whoever carries a ram across an ocean carries something they cannot
//  read.
//
//  Design notes, stated plainly rather than oversold:
//  - Key derivation is HKDF-SHA256 over the normalized code, salted with
//    the letter's own id, so the same code on two letters yields two
//    unrelated keys.
//  - The letter id is also bound in as authenticated additional data,
//    so a ciphertext can't be transplanted from one letter onto another.
//  - A receiving code has 8 characters from a 31-symbol alphabet (~40
//    bits). That's a deliberate trade — a human has to read it off one
//    screen and type it into another — and it is more than enough to
//    keep a letter private from the people relaying it. It is not meant
//    to resist a determined offline attacker with the ciphertext in hand,
//    and this app never claims otherwise.
//

import CryptoKit
import Foundation

enum LetterCipherError: Error, Equatable {
    /// The code didn't open the seal — wrong code, or a tampered body.
    case wrongCode
    /// The sealed body isn't a well-formed ChaChaPoly box.
    case malformed
}

enum LetterCipher {
    private static let info = Data("com.baranov.letter.v1".utf8)

    /// The symmetric key for one letter, from its receiving code.
    static func key(fromReceivingCode code: String, letterID: UUID) -> SymmetricKey {
        let material = SymmetricKey(data: Data(normalize(code).utf8))
        let salt = Data(letterID.uuidString.utf8)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: material,
            salt: salt,
            info: info,
            outputByteCount: 32
        )
    }

    /// Seals a plaintext body. Returns the combined nonce + ciphertext +
    /// tag blob that `Letter.sealedBody` stores and ships.
    static func seal(_ plaintext: String, receivingCode: String, letterID: UUID) throws -> Data {
        let key = key(fromReceivingCode: receivingCode, letterID: letterID)
        let box = try ChaChaPoly.seal(
            Data(plaintext.utf8),
            using: key,
            authenticating: Data(letterID.uuidString.utf8)
        )
        return box.combined
    }

    /// Opens a sealed body. Throws `.wrongCode` on any authentication
    /// failure — a wrong code and a tampered body are indistinguishable
    /// by design, and both mean "this seal does not break for you".
    static func open(_ sealedBody: Data, receivingCode: String, letterID: UUID) throws -> String {
        let box: ChaChaPoly.SealedBox
        do {
            box = try ChaChaPoly.SealedBox(combined: sealedBody)
        } catch {
            throw LetterCipherError.malformed
        }

        let key = key(fromReceivingCode: receivingCode, letterID: letterID)
        let plaintext: Data
        do {
            plaintext = try ChaChaPoly.open(box, using: key, authenticating: Data(letterID.uuidString.utf8))
        } catch {
            throw LetterCipherError.wrongCode
        }

        guard let text = String(data: plaintext, encoding: .utf8) else {
            throw LetterCipherError.malformed
        }
        return text
    }

    /// A short, human-readable fingerprint of a sealed body — shown on the
    /// envelope like a wax impression, so the sender and recipient can
    /// confirm they're talking about the same letter without either of
    /// them seeing inside it.
    static func fingerprint(of sealedBody: Data) -> String {
        guard !sealedBody.isEmpty else { return "————" }
        let digest = SHA256.hash(data: sealedBody)
        return digest.prefix(2).map { String(format: "%02X", $0) }.joined()
    }

    /// Uppercased, stripped to the code alphabet — so "abcd-efgh",
    /// "ABCD EFGH" and "ABCDEFGH" all derive the same key. Typing the
    /// dash is optional; typing the letters is not.
    static func normalize(_ code: String) -> String {
        String(code.uppercased().filter { $0.isLetter || $0.isNumber })
    }
}
