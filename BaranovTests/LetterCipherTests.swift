//
//  LetterCipherTests.swift
//  BaranovTests
//
//  The encryption claim, checked: a letter body round-trips only with the
//  right code, on the right letter, and the sealed form leaks nothing.
//

import CryptoKit
import Foundation
import Testing
@testable import Baranov

struct LetterCipherTests {

    @Test func sealAndOpenRoundTrips() throws {
        let id = UUID()
        let sealed = try LetterCipher.seal("By the time this reaches you, the leaves will have turned.", receivingCode: "ABCD-EFGH", letterID: id)
        let opened = try LetterCipher.open(sealed, receivingCode: "ABCD-EFGH", letterID: id)
        #expect(opened == "By the time this reaches you, the leaves will have turned.")
    }

    @Test func codeIsCaseAndPunctuationInsensitive() throws {
        let id = UUID()
        let sealed = try LetterCipher.seal("hello", receivingCode: "ABCD-EFGH", letterID: id)
        #expect(try LetterCipher.open(sealed, receivingCode: "abcd efgh", letterID: id) == "hello")
        #expect(try LetterCipher.open(sealed, receivingCode: "abcdefgh", letterID: id) == "hello")
    }

    @Test func wrongCodeDoesNotOpen() throws {
        let id = UUID()
        let sealed = try LetterCipher.seal("hello", receivingCode: "ABCD-EFGH", letterID: id)
        #expect(throws: LetterCipherError.wrongCode) {
            try LetterCipher.open(sealed, receivingCode: "ABCD-EFGJ", letterID: id)
        }
    }

    @Test func ciphertextIsBoundToItsLetter() throws {
        let sealed = try LetterCipher.seal("hello", receivingCode: "ABCD-EFGH", letterID: UUID())
        #expect(throws: LetterCipherError.wrongCode) {
            try LetterCipher.open(sealed, receivingCode: "ABCD-EFGH", letterID: UUID())
        }
    }

    @Test func tamperedBodyIsRejected() throws {
        let id = UUID()
        var sealed = try LetterCipher.seal("hello", receivingCode: "ABCD-EFGH", letterID: id)
        sealed[sealed.count - 1] ^= 0x01
        #expect(throws: LetterCipherError.wrongCode) {
            try LetterCipher.open(sealed, receivingCode: "ABCD-EFGH", letterID: id)
        }
    }

    @Test func garbageIsMalformedNotACrash() {
        #expect(throws: LetterCipherError.malformed) {
            try LetterCipher.open(Data([1, 2, 3]), receivingCode: "ABCD-EFGH", letterID: UUID())
        }
    }

    @Test func plaintextNeverAppearsInSealedForm() throws {
        let body = "a very distinctive sentence"
        let sealed = try LetterCipher.seal(body, receivingCode: "ABCD-EFGH", letterID: UUID())
        #expect(!sealed.contains(Data(body.utf8)))
    }

    @Test func fingerprintIsStableAndShort() throws {
        let id = UUID()
        let sealed = try LetterCipher.seal("hello", receivingCode: "ABCD-EFGH", letterID: id)
        #expect(LetterCipher.fingerprint(of: sealed) == LetterCipher.fingerprint(of: sealed))
        #expect(LetterCipher.fingerprint(of: sealed).count == 4)
    }

    @Test func receivingCodesAvoidAmbiguousCharacters() {
        for _ in 0..<200 {
            let code = Letter.generateReceivingCode()
            #expect(code.count == 14)
            #expect(!code.contains("0") && !code.contains("O") && !code.contains("1") && !code.contains("I") && !code.contains("L"))
        }
    }
}

private extension Data {
    func contains(_ needle: Data) -> Bool {
        guard !needle.isEmpty, count >= needle.count else { return false }
        return (0...(count - needle.count)).contains { self[$0..<($0 + needle.count)] == needle }
    }
}
