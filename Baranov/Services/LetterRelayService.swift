//
//  LetterRelayService.swift
//  Baranov
//
//  Client for the receiver's optional letter relay (`/letters` and
//  `/addresses` on the same ACIT3855 receiver the telemetry goes to). It lets
//  a letter reach someone who isn't standing next to you, two ways:
//
//  - BY LETTER CODE. The sender publishes the SEALED letter and hands over
//    one code (`LetterCode`). The recipient types it once; the phone derives
//    a lookup id from it, shows who the letter is from, lets them pick where
//    the ram should arrive, and the same code then opens the wax seal when
//    the ram gets there.
//
//  - BY PROFILE ADDRESS. The sender enters the recipient's profile code
//    instead. The letter code travels wrapped to that address's public key
//    (`LetterKeyWrap`), and the letter turns up in the recipient's mailbag
//    with nothing to type (`LetterInbox`).
//
//  What the server ever holds is ciphertext, a one-way lookup id, and a
//  wrapped code it cannot open. Nothing here can turn a lookup id back into
//  a letter code, and no call ever sends a code or a private key.
//
//  Offline-first: every call throws a `RelayError`; nothing here can crash
//  the UI or interrupt step recording.
//

import CoreLocation
import CryptoKit
import Foundation

struct RelayLetterPreview: Decodable, Sendable {
    struct Point: Decodable, Sendable {
        let latitude: Double
        let longitude: Double
    }

    let senderName: String
    let originName: String
    let ramName: String?
    let origin: Point
    let payload: Letter

    var originCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)
    }
}

/// One letter waiting in a profile's inbox, before its code is unwrapped.
struct InboxEnvelope: Decodable, Sendable {
    let id: String
    let senderName: String
    let originName: String
    let wrappedKey: WrappedLetterKey
    let createdAt: String
}

enum RelayError: LocalizedError, Sendable {
    case notFound
    case offline
    case rejected
    case conflict
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .notFound: String(localized: "No letter is waiting under that code.")
        case .offline: String(localized: "Couldn't reach the post office. Check your connection and try again.")
        case .rejected: String(localized: "The post office couldn't accept that. Try again.")
        case .conflict: String(localized: "That code is already taken. Try again.")
        case .unauthorized: String(localized: "The post office doesn't recognise this phone.")
        }
    }
}

struct LetterRelayService: Sendable {
    let baseURL: URL
    var session: URLSession = .shared

    /// Who a letter is addressed to, with the letter code sealed to them.
    struct Recipient: Sendable {
        let address: String
        let wrappedKey: WrappedLetterKey
    }

    // MARK: - Wire types

    private struct Point: Codable, Sendable {
        let latitude: Double
        let longitude: Double
    }

    private struct PublishBody: Encodable {
        let id: String
        let senderName: String
        let originName: String
        let ramName: String?
        let origin: Point
        let payload: Letter
        let recipientAddress: String?
        let wrappedKey: WrappedLetterKey?
    }

    private struct PublishReceipt: Decodable {
        let code: String
    }

    private struct StatusReceipt: Decodable {
        let claimed: Bool
    }

    private struct RegisterBody: Encodable {
        let publicKey: String
    }

    private struct RegisterReceipt: Decodable {
        let inboxToken: String
    }

    private struct PublicKeyReceipt: Decodable {
        let publicKey: String
    }

    private struct InboxBody: Encodable {
        let token: String
    }

    private struct InboxReceipt: Decodable {
        let letters: [InboxEnvelope]
    }

    // MARK: - Letters

    /// Sender: publishes a sealed letter under the id derived from its code,
    /// optionally addressed to a profile. Returns that id — the handle for
    /// asking later whether the letter was claimed.
    @discardableResult
    func publish(
        letter: Letter,
        code: String,
        originName: String,
        origin: CLLocationCoordinate2D,
        ramName: String?,
        addressedTo recipient: Recipient? = nil
    ) async throws -> String {
        let id = LetterCode.lookupID(for: code)
        let body = PublishBody(
            id: id,
            senderName: letter.senderName,
            originName: originName,
            ramName: ramName,
            origin: Point(latitude: origin.latitude, longitude: origin.longitude),
            payload: letter,
            recipientAddress: recipient?.address,
            wrappedKey: recipient?.wrappedKey
        )
        var request = URLRequest(url: baseURL.appending(path: "letters"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        let data = try await send(request, expecting: [201])
        guard let receipt = try? JSONDecoder().decode(PublishReceipt.self, from: data),
              receipt.code == id else {
            throw RelayError.rejected
        }
        return id
    }

    /// Recipient: who is this from, and where did it start?
    func preview(id: String) async throws -> RelayLetterPreview {
        let request = URLRequest(url: baseURL.appending(path: "letters/\(id)"))
        let data = try await send(request, expecting: [200])
        guard let preview = try? JSONDecoder().decode(RelayLetterPreview.self, from: data) else {
            throw RelayError.rejected
        }
        return preview
    }

    /// Recipient: locks in where the ram should arrive.
    func claim(id: String, dropSpot: CLLocationCoordinate2D) async throws {
        var request = URLRequest(url: baseURL.appending(path: "letters/\(id)/claim"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(Point(latitude: dropSpot.latitude, longitude: dropSpot.longitude))
        _ = try await send(request, expecting: [200])
    }

    /// Sender: has anyone claimed it yet? (The server never says where.)
    func isClaimed(id: String) async throws -> Bool {
        let request = URLRequest(url: baseURL.appending(path: "letters/\(id)/status"))
        let data = try await send(request, expecting: [200])
        guard let receipt = try? JSONDecoder().decode(StatusReceipt.self, from: data) else {
            throw RelayError.rejected
        }
        return receipt.claimed
    }

    // MARK: - Profile addresses

    /// Registers this phone's public key under its profile address and
    /// returns the inbox token — shown by the relay exactly once.
    func registerAddress(_ address: String, publicKey: Curve25519.KeyAgreement.PublicKey) async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "addresses/\(address)"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(RegisterBody(publicKey: publicKey.rawRepresentation.base64EncodedString()))
        let data = try await send(request, expecting: [201])
        guard let receipt = try? JSONDecoder().decode(RegisterReceipt.self, from: data) else {
            throw RelayError.rejected
        }
        return receipt.inboxToken
    }

    /// Sender: the public key to wrap a letter code to. `notFound` means
    /// nobody has registered that address.
    func publicKey(ofAddress address: String) async throws -> Curve25519.KeyAgreement.PublicKey {
        let request = URLRequest(url: baseURL.appending(path: "addresses/\(address)"))
        let data = try await send(request, expecting: [200])
        guard let receipt = try? JSONDecoder().decode(PublicKeyReceipt.self, from: data),
              let raw = Data(base64Encoded: receipt.publicKey),
              let key = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw) else {
            throw RelayError.rejected
        }
        return key
    }

    /// Recipient: every unclaimed letter addressed to this profile.
    func inbox(address: String, token: String) async throws -> [InboxEnvelope] {
        var request = URLRequest(url: baseURL.appending(path: "addresses/\(address)/inbox"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(InboxBody(token: token))
        let data = try await send(request, expecting: [200])
        guard let receipt = try? JSONDecoder().decode(InboxReceipt.self, from: data) else {
            throw RelayError.rejected
        }
        return receipt.letters
    }

    // MARK: - Transport

    private func send(_ request: URLRequest, expecting ok: Set<Int>) async throws -> Data {
        var request = request
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw RelayError.offline }
            if ok.contains(http.statusCode) { return data }
            switch http.statusCode {
            case 404: throw RelayError.notFound
            case 409: throw RelayError.conflict
            case 401: throw RelayError.unauthorized
            default: throw RelayError.rejected
            }
        } catch let error as RelayError {
            throw error
        } catch {
            throw RelayError.offline
        }
    }
}
