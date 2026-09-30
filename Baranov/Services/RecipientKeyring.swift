//
//  RecipientKeyring.swift
//  Baranov
//
//  Sealing a letter's code to its recipient, and opening it again on their
//  phone — the part that lets the wax seal open with nothing to type.
//
//  Sender side: the recipient's profile public key comes from the relay
//  (`GET /addresses/{address}`) and is cached on their saved code, so a
//  letter written with no network still gets a key if the sender has
//  written to that person before.
//
//  Recipient side: whenever a letter lands on this phone (relay, AirDrop,
//  a shake), `adopt(_:)` looks for a key addressed to this phone's profile,
//  opens it with the private key in `AddressKeychain`, and keeps the code in
//  `SealKeyVault`. A key for anyone else is simply not openable here.
//

import CryptoKit
import Foundation

enum RecipientKeyring {
    /// This phone's own profile address, or `nil` if none was ever made.
    static var myAddress: String? {
        guard let stored = UserDefaults.standard.string(forKey: "com.baranov.courierCode") else { return nil }
        let address = CourierCodeStore.address(from: stored)
        return address.count == CourierCodeStore.addressLength ? address : nil
    }

    /// Seals `code` to the recipient's public key.
    static func key(forCode code: String, address: String, publicKey: Curve25519.KeyAgreement.PublicKey) -> RecipientKey? {
        guard let wrapped = try? LetterKeyWrap.wrap(code: code, to: publicKey) else { return nil }
        return RecipientKey(
            address: CourierCodeStore.address(from: address),
            lookupID: LetterCode.lookupID(for: code),
            wrapped: wrapped
        )
    }

    /// Whether the letter carries a key for this phone's profile.
    static func isAddressedToMe(_ letter: Letter) -> Bool {
        guard let mine = myAddress, let keys = letter.recipientKeys else { return false }
        return keys.contains { $0.address == mine }
    }

    /// Opens the key meant for this phone and keeps the code for the seal.
    /// Returns whether it did.
    @discardableResult
    static func adopt(_ letter: Letter) -> Bool {
        guard let mine = myAddress, let keys = letter.recipientKeys,
              let key = keys.first(where: { $0.address == mine }) else { return false }
        if SealKeyVault.code(for: letter.id) != nil { return true }
        guard AddressKeychain.inboxToken != nil || AddressKeychain.hasPrivateKey else { return false }
        let privateKey = AddressKeychain.loadOrCreatePrivateKey()
        guard let code = try? LetterKeyWrap.unwrap(key.wrapped, lookupID: key.lookupID, with: privateKey) else { return false }
        SealKeyVault.store(code, for: letter.id)
        return true
    }

    /// Adopts keys for the ram's letter and every passenger. Returns whether
    /// the ram's own letter is this phone's.
    @discardableResult
    static func adoptAll(in ram: Ram) -> Bool {
        for passenger in ram.passengerLetters { adopt(passenger) }
        guard let letter = ram.letter else { return false }
        return adopt(letter)
    }
}
