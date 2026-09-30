//
//  GateStore.swift
//  Baranov
//
//  This person's gate: the town letters to their Shepherd ID walk to.
//
//  Set once, automatically, from where the phone is the first time it knows
//  (town-level, rounded to about 1 km), and changeable from Profile ("Move
//  my gate here"). Published under the Shepherd ID on the relay tick, so a
//  sender who types that ID knows where to send their ram. A letter sent
//  before any gate existed learns it from here too (`ExpectedLetterStore`).
//

import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class GateStore {
    static let shared = GateStore()

    private(set) var gate: LetterGate?

    @ObservationIgnored private let gateKey = "com.baranov.myGate"
    @ObservationIgnored private let publishedKey = "com.baranov.myGatePublished"

    private init() {
        if let data = UserDefaults.standard.data(forKey: gateKey),
           let saved = try? JSONDecoder().decode(LetterGate.self, from: data) {
            gate = saved
        }
    }

    /// Takes the phone's town as the gate if there isn't one yet.
    func adoptIfNeeded(coordinate: CLLocationCoordinate2D?, city: String?) {
        guard gate == nil, let coordinate else { return }
        move(to: coordinate, city: city)
    }

    /// Moves the gate to where the phone is now.
    func move(to coordinate: CLLocationCoordinate2D, city: String?) {
        let name = (city ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fresh = LetterGate(
            city: name.isEmpty ? String(localized: "Your gate", bundle: .appLanguage, locale: .appLanguage) : name,
            coordinate: coordinate
        )
        guard fresh != gate else { return }
        gate = fresh
        if let data = try? JSONEncoder().encode(fresh) {
            UserDefaults.standard.set(data, forKey: gateKey)
        }
        UserDefaults.standard.removeObject(forKey: publishedKey)
    }

    /// Publishes the gate under this phone's Shepherd ID when it changed.
    func publish(using relay: LetterRelayService) async {
        guard let gate, let address = RecipientKeyring.myAddress,
              let token = AddressKeychain.inboxToken else { return }
        let signature = "\(address)|\(gate.city)|\(gate.latitude)|\(gate.longitude)"
        guard UserDefaults.standard.string(forKey: publishedKey) != signature else { return }
        do {
            try await relay.setAddressGate(address: address, token: token, gate: gate)
            UserDefaults.standard.set(signature, forKey: publishedKey)
        } catch {
            // Next tick.
        }
    }
}
