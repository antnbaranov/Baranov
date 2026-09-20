//
//  CourierCodeStore.swift
//  Baranov
//
//  A courier's own permanent, universal code — the one identifier used
//  for receiving mail and transfers. Generated once on this device and
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
