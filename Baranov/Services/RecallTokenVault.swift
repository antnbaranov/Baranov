//
//  RecallTokenVault.swift
//  Baranov
//
//  The sender's proof that a letter is theirs to take back.
//
//  At dispatch the sender's phone makes a random token, keeps it here in the
//  Keychain, and writes only its SHA-256 into the letter (`recallTokenHash`).
//  The letter travels with the hash; the token never leaves this phone
//  except inside a recall request. A carrier gives a letter up only when a
//  recall's hash matches the one inside the letter — so the person who sent
//  it can always get it back, and nobody else can pull it out of someone's
//  mailbag.
//

import CryptoKit
import Foundation
import Security

enum RecallTokenVault {
    private static let service = "com.baranov.recalltokens"

    /// This phone's token for a letter, if this phone sent it.
    static func token(for letterID: UUID) -> String? {
        var query = baseQuery(for: letterID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Whether this phone sent the letter (holds its recall token).
    static func isMine(_ letterID: UUID) -> Bool {
        token(for: letterID) != nil
    }

    /// Makes and stores a fresh token for a letter, returning its hash for
    /// the letter to carry. Reuses an existing token so a letter sent twice
    /// keeps one identity.
    static func issue(for letterID: UUID) -> String {
        if let existing = token(for: letterID) {
            return hash(existing)
        }
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        var query = baseQuery(for: letterID)
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
        return hash(token)
    }

    /// Lowercase hex SHA-256 — the same digest the relay computes.
    static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func baseQuery(for letterID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: letterID.uuidString,
        ]
    }
}
