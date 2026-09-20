//
//  LetterTests.swift
//  BaranovTests
//
//  What a `Letter` puts on the wire — and, more importantly, what it
//  doesn't.
//

import Foundation
import Testing
@testable import Baranov

struct LetterTests {

    @Test func writingALetterSealsItAndReturnsTheCode() throws {
        let (letter, code) = Letter.write(senderName: "Anton", recipientName: "Marta", messageBody: "Miss you.")
        #expect(letter.isSealed)
        #expect(letter.messageBody.isEmpty)
        #expect(!letter.isReadable)

        var opened = letter
        try opened.open(withReceivingCode: code)
        #expect(!opened.isSealed)
        #expect(opened.messageBody == "Miss you.")
    }

    @Test func wireFormatCarriesNoPlaintextAndNoCode() throws {
        let (letter, code) = Letter.write(senderName: "Anton", recipientName: "Marta", messageBody: "a very distinctive sentence")
        let json = String(decoding: try JSONEncoder().encode(letter), as: UTF8.self)
        #expect(!json.contains("a very distinctive sentence"))
        #expect(!json.contains(code))
        #expect(!json.contains("receivingCode"))
        #expect(json.contains("sealedBody"))
    }

    @Test func aRelayedLetterStillOpensForTheRecipient() throws {
        let (letter, code) = Letter.write(senderName: "Anton", recipientName: "Marta", messageBody: "Across the sea.")
        let data = try JSONEncoder().encode(RamTransitPackage(ram: ram(carrying: letter)))
        var arrived = try JSONDecoder().decode(RamTransitPackage.self, from: data).ram
        #expect(arrived.letter?.isReadable == false)
        try arrived.letter?.open(withReceivingCode: code)
        #expect(arrived.letter?.messageBody == "Across the sea.")
    }

    @Test func wrongCodeLeavesTheLetterSealed() {
        var letter = Letter.write(senderName: "Anton", recipientName: "Marta", messageBody: "Secret.").letter
        var thrown: Error?
        do {
            try letter.open(withReceivingCode: "ZZZZ-ZZZZ")
        } catch {
            thrown = error
        }
        #expect(thrown as? LetterCipherError == .wrongCode)
        #expect(letter.isSealed)
        #expect(letter.messageBody.isEmpty)
    }

    @Test func legacyPlaintextLetterStillDecodes() throws {
        let legacy = """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","senderName":"Old","recipientName":"Build",
         "messageBody":"written before encryption","isSealed":true,"createdAt":700000000,"receivingCode":"ABCD-EFGH"}
        """
        var letter = try JSONDecoder().decode(Letter.self, from: Data(legacy.utf8))
        #expect(letter.isSealed)
        try letter.open(withReceivingCode: "anything")
        #expect(letter.messageBody == "written before encryption")
    }

    @Test func sealColorDefaultsToCrimsonAndRoundTrips() throws {
        let (letter, _) = Letter.write(senderName: "A", recipientName: "B", messageBody: "c", sealColor: .plum)
        let decoded = try JSONDecoder().decode(Letter.self, from: try JSONEncoder().encode(letter))
        #expect(decoded.sealColor == .plum)
        #expect(SealColor.crimson.isIncludedFree)
        #expect(SealColor.allCases.filter(\.isIncludedFree).count == SealColor.allCases.count)
    }

    @Test func anOpenPostcardTravelsInTheClearAndOpensWithoutACode() throws {
        let postcard = Letter.writeOpen(senderName: "Anton", recipientName: "Marta", messageBody: "Wish you were here.")
        #expect(!postcard.isEncrypted)
        #expect(postcard.isSealed)
        #expect(postcard.isReadable)
        #expect(postcard.receivingCode == nil)
        #expect(postcard.shareMessage(carrierName: "Klaus") == nil)

        let data = try JSONEncoder().encode(RamTransitPackage(ram: ram(carrying: postcard)))
        var arrived = try JSONDecoder().decode(RamTransitPackage.self, from: data).ram
        #expect(arrived.letter?.isEncrypted == false)
        #expect(arrived.letter?.messageBody == "Wish you were here.")
        try arrived.letter?.open(withReceivingCode: "")
        #expect(arrived.letter?.isSealed == false)
    }

    @Test func aSealedLetterIsEncryptedAndAPostcardIsNot() {
        let sealed = Letter.write(senderName: "A", recipientName: "B", messageBody: "c").letter
        #expect(sealed.isEncrypted)
        #expect(!Letter.writeOpen(senderName: "A", recipientName: "B", messageBody: "c").isEncrypted)
    }

    private func ram(carrying letter: Letter) -> Ram {
        Ram(
            name: "Klaus",
            totalStepsRequired: 1_000,
            currentCity: "Burnaby",
            targetCity: "Frankfurt",
            letter: letter,
            finalDestinationCoordinate: RamCoordinate(latitude: 50.1109, longitude: 8.6821)
        )
    }
}
