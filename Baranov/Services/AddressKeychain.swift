//
//  AddressKeychain.swift
//  Baranov
//
//  The two secrets behind this person's profile address, kept in the
//  Keychain and nowhere else:
//
//  - the private half of the key pair letters are wrapped to
//    (`LetterKeyWrap`), which never leaves the phone;
//  - the inbox token the relay hands back once, when the address is
//    registered, and which is the only thing that lets a phone list what is
//    waiting for that address.
//
//  Every call is best-effort: a Keychain failure means "no inbox on this
//  phone", never a crash.
//

import CryptoKit
import Foundation
import Security

enum AddressKeychain {
    private static let service = "com.baranov.address"

    private enum Account: String {
        case privateKey
        case inboxToken
    }

    /// The key pair's private half, created on first use.
    static func loadOrCreatePrivateKey() -> Curve25519.KeyAgreement.PrivateKey {
        if let data = read(.privateKey),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) {
            return key
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        write(key.rawRepresentation, for: .privateKey)
        return key
    }

    static var inboxToken: String? {
        get { read(.inboxToken).flatMap { String(data: $0, encoding: .utf8) } }
        set {
            if let newValue { write(Data(newValue.utf8), for: .inboxToken) } else { delete(.inboxToken) }
        }
    }

    /// Forgets both secrets, so the next launch registers a fresh pair.
    static func reset() {
        delete(.privateKey)
        delete(.inboxToken)
    }

    // MARK: - Keychain plumbing

    private static func query(_ account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }

    private static func read(_ account: Account) -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func write(_ data: Data, for account: Account) {
        var query = query(account)
        let update: [String: Any] = [kSecValueData as String: data]
        guard SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound else { return }
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func delete(_ account: Account) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
