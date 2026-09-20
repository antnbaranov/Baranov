//
//  FlockTests.swift
//  BaranovTests
//
//  The flock's rules: capacity, step progress, the gate, and — since a
//  ram mid-walk is days of someone's real steps — that it survives a
//  relaunch.
//

import Foundation
import Testing
@testable import Baranov

@MainActor
struct FlockTests {

    @Test func freeTierAdmitsExactlyOneRam() {
        let flock = FlockViewModel()
        #expect(flock.dispatch(makeRam()))
        #expect(!flock.dispatch(makeRam()))
        #expect(flock.activeRams.count == 1)

        flock.maxAllowedRams = FlockViewModel.pastureCapacity
        for _ in 1..<FlockViewModel.pastureCapacity {
            #expect(flock.dispatch(makeRam()))
        }
        #expect(!flock.dispatch(makeRam()))
        #expect(flock.activeRams.count == FlockViewModel.pastureCapacity)
    }

    @Test func dispatchStampsTheOrigin() {
        let flock = FlockViewModel()
        flock.dispatch(makeRam())
        #expect(flock.activeRams[0].stamps.first?.placeName == "Burnaby")
        #expect(flock.activeRams[0].stamps.first?.kind == .setOut)
    }

    @Test func stepsWalkTheRamAndArrivalStopsAtTheGate() {
        let flock = FlockViewModel()
        flock.dispatch(makeRam(steps: 100))
        let id = flock.activeRams[0].id

        flock.addStepProgress(ramId: id, steps: 40)
        #expect(flock.activeRams[0].status == .walking)
        #expect(flock.activeRams[0].stepsWalked == 40)

        flock.addStepProgress(ramId: id, steps: 500)
        #expect(flock.activeRams[0].stepsWalked == 100)
        #expect(flock.activeRams[0].status == .arrivedAtGate)
        #expect(flock.activeRams[0].routeHistory.last?.cityName == "Frankfurt")
    }

    @Test func gateOpensOnlyWithTheRightCode() throws {
        let flock = FlockViewModel()
        let (letter, code) = Letter.write(senderName: "Anton", recipientName: "Marta", messageBody: "Hello.")
        flock.dispatch(makeRam(steps: 10, letter: letter))
        let id = flock.activeRams[0].id
        flock.addStepProgress(ramId: id, steps: 10)

        #expect(throws: LetterCipherError.wrongCode) {
            try flock.openDeliveredLetter(ramId: id, receivingCode: "ZZZZ-ZZZZ")
        }
        #expect(flock.activeRams[0].status == .arrivedAtGate)

        try flock.openDeliveredLetter(ramId: id, receivingCode: code)
        #expect(flock.activeRams[0].status == .delivered)
        #expect(flock.activeRams[0].letter?.messageBody == "Hello.")
        #expect(flock.lettersDelivered == 1)
    }

    @Test func flockSurvivesARelaunch() async throws {
        let store = FlockStore.ephemeral()
        defer { store.clear() }

        let first = FlockViewModel(store: store)
        first.dispatch(makeRam(steps: 5_000))
        let id = first.activeRams[0].id
        first.addStepProgress(ramId: id, steps: 1_234)

        // Writes are coalesced; give the debounce a moment.
        try await Task.sleep(for: .milliseconds(700))

        let second = FlockViewModel(store: store)
        #expect(second.activeRams.count == 1)
        #expect(second.activeRams[0].id == id)
        #expect(second.activeRams[0].stepsWalked == 1_234)
        #expect(second.selectedRamId == id)
    }

    @Test func transitPackageRoundTripsARamWithPassengers() throws {
        var ram = makeRam()
        ram.passengerLetters = [Letter.write(senderName: "X", recipientName: "Y", messageBody: "z").letter]
        let data = try JSONEncoder().encode(RamTransitPackage(ram: ram))
        let decoded = try JSONDecoder().decode(RamTransitPackage.self, from: data)
        #expect(decoded.ram.id == ram.id)
        #expect(decoded.ram.passengerLetters.count == 1)
    }

    private func makeRam(steps: Int = 1_000, letter: Letter? = nil) -> Ram {
        Ram(
            name: "Klaus",
            totalStepsRequired: steps,
            currentCity: "Burnaby",
            targetCity: "Frankfurt",
            routeCoordinates: [
                RamCoordinate(latitude: 49.2488, longitude: -122.9805),
                RamCoordinate(latitude: 50.1109, longitude: 8.6821),
            ],
            letter: letter,
            finalDestinationCoordinate: RamCoordinate(latitude: 50.1109, longitude: 8.6821)
        )
    }
}
