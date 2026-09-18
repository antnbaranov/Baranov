//
//  SealKeyVault.swift
//  Baranov
//
//  Where a letter's receiving code lives on the device that wrote it —
//  and nowhere else. The code is the letter's key (see `LetterCipher`),
//  so it is deliberately kept out of `Letter`, out of the `.ram` transit
//  package, and out of the flock cache; it goes in the Keychain here,
//  keyed by letter id, and comes back out only for the sender to share
//  it on (`RamHistoryView`, `RamCardView`) or for the recipient's device
//  to remember what they typed at the gate.
//
//  Keychain rather than `UserDefaults` because this is the one piece of
//  state in the app that actually is a secret. Every call is best-effort:
//  a Keychain failure degrades to "the code isn't on this phone", never
//  to a crash.
//

import Foundation
import Security

enum SealKeyVault {
    private static let service = "com.baranov.sealkeys"

    /// The receiving code for a letter, if this device holds it.
    static func code(for letterID: UUID) -> String? {
        var query = baseQuery(for: letterID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Stores (or replaces) the receiving code for a letter.
    static func store(_ code: String, for letterID: UUID) {
        let data = Data(LetterCipher.normalize(code).utf8)
        var query = baseQuery(for: letterID)

        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard updateStatus == errSecItemNotFound else { return }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Forgets a letter's code — e.g. when its ram is removed.
    static func remove(for letterID: UUID) {
        SecItemDelete(baseQuery(for: letterID) as CFDictionary)
    }

    private static func baseQuery(for letterID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: letterID.uuidString,
        ]
    }
}
