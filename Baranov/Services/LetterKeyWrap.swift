//
//  LetterKeyWrap.swift
//  Baranov
//
//  How a letter code reaches someone who was addressed by profile code
//  instead of being handed the code out loud.
//
//  The recipient's phone keeps a Curve25519 key pair (`AddressKeychain`) and
//  publishes only the public half under their profile address. To send to
//  that address, the sender's phone seals the letter's code to the public key
//  with HPKE (RFC 9180, CryptoKit) and the relay stores the result beside the
//  encrypted letter. The relay holds a sealed code it cannot open: only the
//  private key on the recipient's phone can turn it back into the letter
//  code, and from that code everything else follows (`LetterCode`).
//
//  The letter's lookup id is bound in as authenticated data, and `unwrap`
//  re-derives it from the recovered code, so a wrapped key cannot be swapped
//  onto a different letter.
//

import CryptoKit
import Foundation

struct WrappedLetterKey: Codable, Sendable, Hashable {
    /// HPKE encapsulated key, base64.
    let enc: String
    /// The sealed letter code, base64.
    let ct: String
}

enum LetterKeyWrapError: Error, Equatable {
    case malformed
    case mismatch
}

enum LetterKeyWrap {
    private static let suite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly
    private static let info = Data("com.baranov.letter.wrap.v1".utf8)

    /// Seals `code` so only the holder of the matching private key can read it.
    static func wrap(
        code: String,
        to publicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> WrappedLetterKey {
        let normalized = LetterCode.normalize(code)
        let lookupID = LetterCode.lookupID(for: normalized)
        var sender = try HPKE.Sender(recipientKey: publicKey, ciphersuite: suite, info: info)
        let ciphertext = try sender.seal(Data(normalized.utf8), authenticating: Data(lookupID.utf8))
        return WrappedLetterKey(
            enc: sender.encapsulatedKey.base64EncodedString(),
            ct: ciphertext.base64EncodedString()
        )
    }

    /// Recovers the letter code for the letter filed under `lookupID`.
    static func unwrap(
        _ wrapped: WrappedLetterKey,
        lookupID: String,
        with privateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> String {
        guard let enc = Data(base64Encoded: wrapped.enc),
              let ciphertext = Data(base64Encoded: wrapped.ct) else {
            throw LetterKeyWrapError.malformed
        }
        var recipient = try HPKE.Recipient(
            privateKey: privateKey,
            ciphersuite: suite,
            info: info,
            encapsulatedKey: enc
        )
        let plaintext = try recipient.open(ciphertext, authenticating: Data(lookupID.utf8))
        guard let code = String(data: plaintext, encoding: .utf8), LetterCode.isUsableKey(code) else {
            throw LetterKeyWrapError.malformed
        }
        guard LetterCode.lookupID(for: code) == lookupID else { throw LetterKeyWrapError.mismatch }
        return LetterCode.normalize(code)
    }
}
