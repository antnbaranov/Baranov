//
//  CourierCodeStore.swift
//  Baranov
//
//  A courier's own permanent address — the profile code a friend types into
//  "Send by code" to put a letter straight into this person's mailbag (see
//  `LetterInbox`). Generated once on this device and
//  kept; 10 characters from a 31-symbol alphabet (no 0/O, 1/I/L), so
//  there are ~8 × 10^14 possibilities and two couriers never collide in
//  practice. Formatted XXXXX-XXXXX for reading aloud and typing.
//

import Foundation
import Observation

@MainActor
@Observable
final class CourierCodeStore {
    private static let key = "com.baranov.courierCode"
    private static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    private(set) var code: String

    /// The code as the relay knows it: 10 characters, no dash.
    var address: String { Self.address(from: code) }

    static let addressLength = 10

    static func address(from raw: String) -> String {
        String(raw.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(addressLength))
    }

    /// Whether typed or scanned text is a whole profile address.
    static func isAddress(_ raw: String) -> Bool {
        let cleaned = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        return cleaned.count == addressLength && cleaned.allSatisfy(alphabet.contains)
    }

    /// `ABCDEFGHJK` → `ABCDE-FGHJK`, as far as the text goes.
    static func formatted(_ raw: String) -> String {
        let cleaned = address(from: raw)
        return cleaned.count > 5 ? "\(cleaned.prefix(5))-\(cleaned.dropFirst(5))" : cleaned
    }

    /// Replaces the address with a fresh one. Only used when the relay says
    /// this one already belongs to somebody else's keys.
    func regenerate(defaults: UserDefaults = .standard) {
        let fresh = Self.generate()
        defaults.set(fresh, forKey: Self.key)
        code = fresh
    }

    init(defaults: UserDefaults = .standard) {
        if let stored = defaults.string(forKey: Self.key), Self.isValid(stored) {
            code = stored
        } else {
            let fresh = Self.generate()
            defaults.set(fresh, forKey: Self.key)
            code = fresh
        }
    }

    static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        let chars = (0..<10).map { _ in alphabet.randomElement(using: &generator)! }
        return String(chars[0..<5]) + "-" + String(chars[5..<10])
    }

    private static func isValid(_ value: String) -> Bool {
        let parts = value.split(separator: "-")
        return parts.count == 2 && parts.allSatisfy { $0.count == 5 && $0.allSatisfy(alphabet.contains) }
    }
}
