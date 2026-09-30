//
//  LetterRelayService.swift
//  Baranov
//
//  Client for the receiver's letter relay (`/letters`, `/addresses` and
//  `/api/v1/devices` on the same ACIT3855 receiver the telemetry goes to).
//
//  Every letter follows one rule: the SENDER's ram walks it to the
//  recipient's gate, and the relay hands it over there (`LetterTracker`,
//  `ExpectedLetterStore`). The relay follows the ram, keeps the sealed letter
//  until it arrives, and knows who to push:
//
//  - BY LETTER CODE (ear tag). One code finds the letter at the relay and
//    opens the seal (`LetterCode`).
//  - BY PROFILE ADDRESS (Shepherd ID). The code travels sealed to that
//    address's public key (`LetterKeyWrap`), the address says where its gate
//    is, and the letter turns up in the recipient's mailbag with nothing to
//    type (`LetterInbox`).
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

/// One letter waiting in a profile's inbox, before its code is unwrapped.
struct InboxEnvelope: Decodable, Sendable {
    let id: String
    let senderName: String
    let originName: String
    let wrappedKey: WrappedLetterKey
    let createdAt: String
    /// A tracked letter: the sender's ram walks it and the relay delivers
    /// it at the gate. `nil` from older receivers.
    let tracked: Bool?
    let letterId: String?
}

/// Where a tracked letter is, as the relay last heard from the phone
/// carrying it — and, once it reached the gate, the letter itself.
struct RelayTracking: Decodable, Sendable {
    let senderName: String
    let recipientName: String
    let originName: String
    let destinationName: String
    let ramName: String
    let letterId: String
    let metersWalked: Int
    let metersToGo: Int
    let status: String
    let currentCity: String
    let latitude: Double?
    let longitude: Double?
    let expectedBy: String?
    let updatedAt: String?
    let deliveredAt: String?
    let claimed: Bool
    /// Sent before the recipient's gate was known, and still waiting for it.
    let awaitingGate: Bool?
    /// Where the ram walks: the recipient's town, rounded to about 1 km.
    let gate: LetterGate?
    let openedAt: String?
    let package: RamTransitPackage?

    var isDelivered: Bool { deliveredAt != nil }
    var isAwaitingGate: Bool { awaitingGate == true }
    var letterUUID: UUID? { UUID(uuidString: letterId) }
}

/// What the carrying phone tells the relay about a tracked letter.
struct RelayProgress: Sendable {
    let metersWalked: Int
    let metersToGo: Int
    let status: RamStatus
    let currentCity: String
    let destinationName: String
    let coordinate: CLLocationCoordinate2D?
    let expectedBy: Date?
    /// Only at the gate: the ram, carrying just this letter, for the recipient.
    let package: RamTransitPackage?
}

enum RelayError: LocalizedError, Sendable {
    case notFound
    case offline
    case rejected
    case conflict
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .notFound: String(localized: "No letter is waiting under that code.", bundle: .appLanguage, locale: .appLanguage)
        case .offline: String(localized: "Couldn't reach the post office. Check your connection and try again.", bundle: .appLanguage, locale: .appLanguage)
        case .rejected: String(localized: "The post office couldn't accept that. Try again.", bundle: .appLanguage, locale: .appLanguage)
        case .conflict: String(localized: "That code is already taken. Try again.", bundle: .appLanguage, locale: .appLanguage)
        case .unauthorized: String(localized: "The post office doesn't recognise this phone.", bundle: .appLanguage, locale: .appLanguage)
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
        let tracking: TrackingBody?
    }

    /// Makes a published letter a tracked one.
    struct TrackingBody: Encodable, Sendable {
        let progressToken: String
        let letterId: String
        let recipientName: String
        let destinationName: String
        let totalMeters: Int
        let expectedBy: String?
        /// The sender's own Shepherd ID, so they can be pushed when it's opened.
        let senderAddress: String?
        /// Sent before the recipient's gate is known.
        let awaitingGate: Bool?
    }

    private struct ProgressBody: Encodable {
        let token: String
        let metersWalked: Int
        let metersToGo: Int
        let status: String
        let currentCity: String?
        let destinationName: String?
        let latitude: Double?
        let longitude: Double?
        let expectedBy: String?
        let package: RamTransitPackage?
    }

    struct ProgressReceipt: Decodable, Sendable {
        let delivered: Bool
        let claimed: Bool
    }

    struct LetterStatus: Decodable, Sendable {
        let claimed: Bool
        let delivered: Bool?
        let openedAt: String?
    }

    /// A Shepherd ID's public key, and its gate once the owner's phone set one.
    struct AddressInfo: Sendable {
        let publicKey: Curve25519.KeyAgreement.PublicKey
        let gate: LetterGate?
    }

    private struct AddressReceipt: Decodable {
        let publicKey: String
        let gate: LetterGate?
    }

    private struct GateBody: Encodable {
        let token: String?
        let city: String
        let latitude: Double
        let longitude: Double
    }

    private struct WatchBody: Encodable {
        let address: String
        let token: String
    }

    private struct DeviceBody: Encodable {
        let shepherdId: String
        let inboxToken: String
        let deviceToken: String
        let environment: String
        let enabled: Bool
    }

    struct DeviceReceipt: Decodable, Sendable {
        let registered: Bool
        let pushEnabled: Bool
    }

    private struct PublishReceipt: Decodable {
        let code: String
    }

    private struct RegisterBody: Encodable {
        let publicKey: String
    }

    private struct RegisterReceipt: Decodable {
        let inboxToken: String
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
        addressedTo recipient: Recipient? = nil,
        tracking: TrackingBody? = nil
    ) async throws -> String {
        let id = LetterCode.lookupID(for: code)
        let body = PublishBody(
            id: id,
            senderName: letter.senderName,
            originName: originName,
            ramName: ramName,
            origin: Point(latitude: origin.latitude, longitude: origin.longitude),
            payload: letter.relayPayload(),
            recipientAddress: recipient?.address,
            wrappedKey: recipient?.wrappedKey,
            tracking: tracking
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

    // MARK: - Tracked letters

    /// Anyone holding the code: where the letter is, and the delivered
    /// package once its ram reached the gate. `notFound` also means "not a
    /// tracked letter" — fall back to `preview(id:)`.
    func tracking(id: String) async throws -> RelayTracking {
        let request = URLRequest(url: baseURL.appending(path: "letters/\(id)/tracking"))
        let data = try await send(request, expecting: [200])
        guard let tracking = try? JSONDecoder().decode(RelayTracking.self, from: data) else {
            throw RelayError.rejected
        }
        return tracking
    }

    /// The phone carrying the ram: how far it has come. With
    /// `.arrivedAtGate` and a package, this is the delivery.
    func reportProgress(id: String, token: String, progress: RelayProgress) async throws -> ProgressReceipt {
        let body = ProgressBody(
            token: token,
            metersWalked: max(0, progress.metersWalked),
            metersToGo: max(0, progress.metersToGo),
            status: progress.status.relayName,
            currentCity: progress.currentCity.isEmpty ? nil : String(progress.currentCity.prefix(120)),
            destinationName: progress.destinationName.isEmpty ? nil : String(progress.destinationName.prefix(120)),
            latitude: progress.coordinate?.latitude,
            longitude: progress.coordinate?.longitude,
            expectedBy: progress.expectedBy?.ISO8601Format(),
            package: progress.package
        )
        var request = URLRequest(url: baseURL.appending(path: "letters/\(id)/progress"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        let data = try await send(request, expecting: [200])
        guard let receipt = try? JSONDecoder().decode(ProgressReceipt.self, from: data) else {
            throw RelayError.rejected
        }
        return receipt
    }

    /// Recipient: the delivered letter is on this phone now. Tells the
    /// sender it was collected — never where.
    func markCollected(id: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "letters/\(id)/claim"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        _ = try await send(request, expecting: [200])
    }

    /// A recipient following a letter by its code: push its arrival to this
    /// phone too. Needs this phone's own address and inbox token.
    func watch(id: String, address: String, token: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "letters/\(id)/watch"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(WatchBody(address: address, token: token))
        _ = try await send(request, expecting: [200])
    }

    /// Recipient: where a letter sent before the gate was known should walk.
    /// `conflict` means it already knows.
    func setLetterGate(id: String, gate: LetterGate) async throws {
        var request = URLRequest(url: baseURL.appending(path: "letters/\(id)/gate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(GateBody(token: nil, city: gate.city, latitude: gate.latitude, longitude: gate.longitude))
        _ = try await send(request, expecting: [200])
    }

    /// Recipient: the seal is broken. The sender is told once.
    func markOpened(id: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "letters/\(id)/opened"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        _ = try await send(request, expecting: [200])
    }

    /// Sender: claimed yet, and (for a tracked letter) delivered yet?
    func status(id: String) async throws -> LetterStatus {
        let request = URLRequest(url: baseURL.appending(path: "letters/\(id)/status"))
        let data = try await send(request, expecting: [200])
        guard let status = try? JSONDecoder().decode(LetterStatus.self, from: data) else {
            throw RelayError.rejected
        }
        return status
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

    /// Sender: the public key to wrap a letter code to, and where the
    /// address's gate is. `notFound` means nobody has registered that address.
    func addressInfo(_ address: String) async throws -> AddressInfo {
        let request = URLRequest(url: baseURL.appending(path: "addresses/\(address)"))
        let data = try await send(request, expecting: [200])
        guard let receipt = try? JSONDecoder().decode(AddressReceipt.self, from: data),
              let raw = Data(base64Encoded: receipt.publicKey),
              let key = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw) else {
            throw RelayError.rejected
        }
        return AddressInfo(publicKey: key, gate: receipt.gate)
    }

    /// Sender: just the public key.
    func publicKey(ofAddress address: String) async throws -> Curve25519.KeyAgreement.PublicKey {
        try await addressInfo(address).publicKey
    }

    /// This phone's gate: where letters to its Shepherd ID walk.
    func setAddressGate(address: String, token: String, gate: LetterGate) async throws {
        var request = URLRequest(url: baseURL.appending(path: "addresses/\(address)/gate"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(GateBody(token: token, city: gate.city, latitude: gate.latitude, longitude: gate.longitude))
        _ = try await send(request, expecting: [200])
    }

    // MARK: - Devices

    /// Registers this phone's APNs token under its Shepherd ID (proven with
    /// the inbox token). `pushEnabled` says whether the server can push at all.
    func registerDevice(address: String, inboxToken: String, deviceToken: String, environment: String, enabled: Bool) async throws -> DeviceReceipt {
        var request = URLRequest(url: baseURL.appending(path: "api/v1/devices/register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(DeviceBody(
            shepherdId: address, inboxToken: inboxToken, deviceToken: deviceToken,
            environment: environment, enabled: enabled
        ))
        let data = try await send(request, expecting: [200])
        guard let receipt = try? JSONDecoder().decode(DeviceReceipt.self, from: data) else {
            throw RelayError.rejected
        }
        return receipt
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

extension RamStatus {
    /// The status as the relay spells it (`POST /letters/{id}/progress`).
    /// A ram handed on or opened is reported by whoever holds it now.
    var relayName: String {
        switch self {
        case .grazing: "grazing"
        case .walking: "walking"
        case .waitingForHandoff: "waitingForHandoff"
        case .atSea: "atSea"
        case .handedOff, .arrivedAtGate, .delivered: "arrivedAtGate"
        }
    }
}
