//
//  ExpectedLetter.swift
//  Baranov
//
//  "A letter from Anton is on the way": the recipient's incoming card.
//
//  It starts from the tracking link the sender shares (Messages, anything),
//  from typing the letter's ear tag, or from a letter addressed to this
//  profile turning up in the relay inbox. From then on:
//
//  - The link alone is enough to show the card — who sent it, which ram,
//    where to and roughly when — with no network, as before.
//  - With a server configured and the ear tag known, each relay tick asks
//    the post office where the ram is now and refreshes the card.
//  - When the relay reports the ram at the gate, the delivered package is
//    pulled straight into the mailbag (`onDelivered`), the ear tag is
//    already in `SealKeyVault`, and the seal opens with a long press.
//
//  If the ram reaches this phone some other way (AirDrop, a shake at the
//  gate) the card simply disappears: it's hidden for any letter already
//  here.
//
//  https://antnbaranov.github.io/l/<ear tag>?id=<letter UUID>&from=<sender>&ram=<ram>&city=<town>&by=<unix seconds>
//  (a letter with no ear tag uses /l/expect). It is a universal link, so
//  messengers make it tappable; the old baranov://expect?... form still opens.
//

import Foundation
import Observation

struct ExpectedLetter: Codable, Identifiable, Hashable, Sendable {
    let letterID: UUID
    var senderName: String
    var ramName: String
    var city: String
    var expectedBy: Date?
    let addedAt: Date
    /// The letter's ear tag, normalized. With it the relay can be asked
    /// where the letter is, and the seal opens without typing.
    var code: String?

    // Live, from the relay (`RelayTracking`). All `nil` until the first answer.
    var originName: String?
    var metersWalked: Int?
    var metersToGo: Int?
    var status: String?
    var currentCity: String?
    var latitude: Double?
    var longitude: Double?
    var updatedAt: Date?
    var deliveredAt: Date?
    /// When the relay was last asked, and whether it knew the letter.
    var lastCheckedAt: Date?
    var relayKnowsIt: Bool?
    /// Sent before this person's gate was known; the ram sets out once the
    /// relay has it (this phone sends it, from `GateStore`).
    var awaitingGate: Bool?
    /// This phone asked the relay to push it this letter's arrival.
    var watching: Bool?

    var id: UUID { letterID }

    /// Whether the post office is following this one (it can't be swiped away).
    var isTracked: Bool { code != nil && relayKnowsIt == true }

    /// The walk so far as 0…1, when the relay has said.
    var progress: Double? {
        guard let walked = metersWalked, let toGo = metersToGo else { return nil }
        let total = walked + toGo
        return total > 0 ? min(1, Double(walked) / Double(total)) : nil
    }

    var relayStatus: RamStatus? { status.flatMap(RamStatus.init(rawValue:)) }

    init(letterID: UUID, senderName: String, ramName: String, city: String, expectedBy: Date?, code: String?, originName: String? = nil, now: Date = Date()) {
        self.letterID = letterID
        self.senderName = String(senderName.prefix(40))
        self.ramName = String(ramName.prefix(40))
        self.city = String(city.prefix(60))
        self.expectedBy = expectedBy
        self.addedAt = now
        self.code = code.map(LetterCode.normalize)
        self.originName = originName
    }

    /// From the relay, for an ear tag typed in or unwrapped from the inbox.
    init?(code: String, tracking: RelayTracking, now: Date = Date()) {
        guard let id = tracking.letterUUID else { return nil }
        self.init(letterID: id, senderName: tracking.senderName, ramName: tracking.ramName,
                  city: tracking.destinationName, expectedBy: nil, code: code,
                  originName: tracking.originName, now: now)
        apply(tracking, at: now)
    }

    /// Takes in what the relay knows now.
    mutating func apply(_ tracking: RelayTracking, at now: Date = Date()) {
        if !tracking.senderName.isEmpty { senderName = String(tracking.senderName.prefix(40)) }
        if !tracking.ramName.isEmpty { ramName = String(tracking.ramName.prefix(40)) }
        if !tracking.destinationName.isEmpty { city = String(tracking.destinationName.prefix(60)) }
        if !tracking.originName.isEmpty { originName = tracking.originName }
        metersWalked = tracking.metersWalked
        metersToGo = tracking.metersToGo
        status = tracking.status
        currentCity = tracking.currentCity
        latitude = tracking.latitude
        longitude = tracking.longitude
        awaitingGate = tracking.isAwaitingGate
        if let gate = tracking.gate, !gate.city.isEmpty { city = String(gate.city.prefix(60)) }
        if let by = tracking.expectedBy.flatMap(Self.date(from:)) { expectedBy = by }
        updatedAt = tracking.updatedAt.flatMap(Self.date(from:))
        deliveredAt = tracking.deliveredAt.flatMap(Self.date(from:))
        lastCheckedAt = now
        relayKnowsIt = true
    }

    static func date(from iso: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)
    }

    // MARK: - Link

    /// The legacy custom-scheme host, still read.
    static let host = "expect"
    /// The universal-link host and path prefix (`applinks:antnbaranov.github.io`).
    static let universalHost = "antnbaranov.github.io"
    private static let universalPrefix = "l"

    /// Whether `url` is one of ours: a universal link or the old scheme.
    static func isLink(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https": return url.host?.lowercased() == universalHost && url.pathComponents.dropFirst().first == universalPrefix
        case "baranov": return url.host?.lowercased() == host
        default: return false
        }
    }

    /// The link that goes into the shared message: a real https universal
    /// link, so iMessage, Telegram and WhatsApp render it as tappable. With
    /// `code`, the recipient's phone can follow the letter at the post office.
    static func link(letterID: UUID, senderName: String, ramName: String, city: String, expectedBy: Date?, code: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = universalHost
        let usableCode = code.flatMap { LetterCode.isUsableKey($0) ? LetterCode.normalize($0) : nil }
        components.path = "/\(universalPrefix)/\(usableCode ?? host)"
        var items = [
            URLQueryItem(name: "id", value: letterID.uuidString),
            URLQueryItem(name: "from", value: String(senderName.prefix(40))),
            URLQueryItem(name: "ram", value: String(ramName.prefix(40))),
            URLQueryItem(name: "city", value: String(city.prefix(60))),
        ]
        if let expectedBy {
            items.append(URLQueryItem(name: "by", value: String(Int(expectedBy.timeIntervalSince1970))))
        }
        components.queryItems = items
        return components.url
    }

    /// Reads an `expect` link; `nil` for anything else or anything malformed.
    init?(url: URL, now: Date = Date()) {
        guard Self.isLink(url),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let rawID = value("id"), let id = UUID(uuidString: rawID) else { return nil }
        // The ear tag rides in the path of a universal link, in `code=` of the old scheme.
        let pathCode = url.scheme?.lowercased() == "https" ? url.pathComponents.last : nil
        let code = (pathCode ?? value("code")).flatMap { LetterCode.isUsableKey($0) ? LetterCode.normalize($0) : nil }
        self.init(
            letterID: id,
            senderName: value("from") ?? "",
            ramName: value("ram") ?? "",
            city: value("city") ?? "",
            expectedBy: value("by").flatMap(TimeInterval.init).map { Date(timeIntervalSince1970: $0) },
            code: code,
            now: now
        )
    }
}

/// The letters on their way to this person. Kept on the phone; followed at
/// the relay when a server is configured.
@MainActor
@Observable
final class ExpectedLetterStore {
    static let shared = ExpectedLetterStore()

    private(set) var letters: [ExpectedLetter] = []

    @ObservationIgnored private let key = "com.baranov.expectedLetters"
    @ObservationIgnored private var relay: LetterRelayService?
    @ObservationIgnored private var isOnPhone: (UUID) -> Bool = { _ in false }
    @ObservationIgnored private var onDelivered: (ExpectedLetter, RamTransitPackage) async -> Bool = { _, _ in false }
    @ObservationIgnored private var isRefreshing = false
    /// Lookup ids of letters opened here whose sender hasn't been told yet.
    @ObservationIgnored private var pendingOpened: [String] = []
    @ObservationIgnored private let openedKey = "com.baranov.pendingOpenedReceipts"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([ExpectedLetter].self, from: data) {
            letters = saved
        }
        pendingOpened = UserDefaults.standard.stringArray(forKey: openedKey) ?? []
        prune()
    }

    /// "Delete all data & reset": forgets every expected letter in memory.
    /// The saved copies go with `UserDefaults` (`AppDataEraser`).
    func eraseAll() {
        letters = []
        pendingOpened = []
        relay = nil
        isOnPhone = { _ in false }
        onDelivered = { _, _ in false }
    }

    /// Called once by `RootView` when a server is configured. `isOnPhone`
    /// says whether a letter already landed here some other way;
    /// `onDelivered` puts a delivered package in the mailbag and returns
    /// whether it did.
    func configure(
        relay: LetterRelayService,
        isOnPhone: @escaping (UUID) -> Bool,
        onDelivered: @escaping (ExpectedLetter, RamTransitPackage) async -> Bool
    ) {
        self.relay = relay
        self.isOnPhone = isOnPhone
        self.onDelivered = onDelivered
    }

    /// Adds (or refreshes) a letter. What the relay already said is kept;
    /// an ear tag is remembered for the seal.
    func add(_ letter: ExpectedLetter) {
        var merged = letter
        if let existing = letters.first(where: { $0.letterID == letter.letterID }) {
            merged = existing
            if merged.code == nil { merged.code = letter.code }
            if !letter.senderName.isEmpty { merged.senderName = letter.senderName }
            if !letter.ramName.isEmpty { merged.ramName = letter.ramName }
            if !letter.city.isEmpty { merged.city = letter.city }
            if merged.expectedBy == nil { merged.expectedBy = letter.expectedBy }
            if letter.relayKnowsIt == true {
                merged = letter
                merged.code = letter.code ?? existing.code
            }
        }
        if let code = merged.code {
            SealKeyVault.store(code, for: merged.letterID)
        }
        letters.removeAll { $0.letterID == merged.letterID }
        letters.insert(merged, at: 0)
        save()
        if merged.code != nil, merged.lastCheckedAt == nil || merged.deliveredAt != nil {
            Task { await refresh(force: true) }
        }
    }

    func remove(letterID: UUID) {
        letters.removeAll { $0.letterID == letterID }
        save()
    }

    /// What to show: minus letters whose ram is already on this phone.
    func pending(excluding arrived: Set<UUID>) -> [ExpectedLetter] {
        letters.filter { !arrived.contains($0.letterID) }
    }

    /// The seal on a letter was just broken here. If the post office knows
    /// the letter, its sender is told (a push when they have one) — queued,
    /// so a letter opened offline still reports once the phone is back.
    func noteOpened(_ letter: Letter) {
        guard TelemetryService.isServerConfigured, let code = SealKeyVault.code(for: letter.id) else { return }
        let lookupID = LetterCode.lookupID(for: code)
        guard !pendingOpened.contains(lookupID) else { return }
        pendingOpened.append(lookupID)
        UserDefaults.standard.set(Array(pendingOpened.suffix(50)), forKey: openedKey)
        Task { await flushOpened() }
    }

    private func flushOpened() async {
        guard let relay, !pendingOpened.isEmpty else { return }
        for lookupID in pendingOpened {
            do {
                try await relay.markOpened(id: lookupID)
                pendingOpened.removeAll { $0 == lookupID }
            } catch RelayError.notFound {
                // Never went through the post office (a letter handed over by hand).
                pendingOpened.removeAll { $0 == lookupID }
            } catch {
                continue
            }
        }
        UserDefaults.standard.set(pendingOpened, forKey: openedKey)
    }

    /// Asks the post office about every letter it can follow. A letter the
    /// relay has never heard of (sent with no server, or not published yet)
    /// is asked about again every ten minutes rather than every tick.
    func refresh(force: Bool = false, now: Date = Date()) async {
        guard let relay, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await flushOpened()

        for entry in letters {
            guard let code = entry.code else { continue }
            if !force, let checked = entry.lastCheckedAt, entry.relayKnowsIt != true,
               now.timeIntervalSince(checked) < 600 { continue }
            if isOnPhone(entry.letterID) {
                try? await relay.markCollected(id: LetterCode.lookupID(for: code))
                remove(letterID: entry.letterID)
                continue
            }
            let lookupID = LetterCode.lookupID(for: code)
            do {
                let tracking = try await relay.tracking(id: lookupID)
                update(entry.letterID) { $0.apply(tracking, at: now) }
                await follow(entry, lookupID: lookupID, tracking: tracking, relay: relay)
                guard tracking.isDelivered, let package = tracking.package,
                      let current = letters.first(where: { $0.letterID == entry.letterID }) else { continue }
                if await onDelivered(current, package) {
                    try? await relay.markCollected(id: lookupID)
                    remove(letterID: entry.letterID)
                }
            } catch RelayError.notFound {
                update(entry.letterID) {
                    $0.lastCheckedAt = now
                    $0.relayKnowsIt = false
                }
            } catch {
                continue
            }
        }
    }

    /// Once per letter: ask for its pushes, and tell a letter that's still
    /// waiting where this person's gate is, so the sender's ram sets out.
    private func follow(_ entry: ExpectedLetter, lookupID: String, tracking: RelayTracking, relay: LetterRelayService) async {
        if entry.watching != true, !tracking.isDelivered,
           let address = RecipientKeyring.myAddress, let token = AddressKeychain.inboxToken,
           (try? await relay.watch(id: lookupID, address: address, token: token)) != nil {
            update(entry.letterID) { $0.watching = true }
        }
        guard tracking.isAwaitingGate, let gate = GateStore.shared.gate else { return }
        do {
            try await relay.setLetterGate(id: lookupID, gate: gate)
            update(entry.letterID) {
                $0.awaitingGate = false
                $0.city = String(gate.city.prefix(60))
            }
        } catch RelayError.conflict {
            update(entry.letterID) { $0.awaitingGate = false }
        } catch {
            // Next tick.
        }
    }

    private func update(_ letterID: UUID, _ change: (inout ExpectedLetter) -> Void) {
        guard let index = letters.firstIndex(where: { $0.letterID == letterID }) else { return }
        change(&letters[index])
        save()
    }

    /// Forgets the ones that arrived, and any that are long overdue (the
    /// sender may have taken it back).
    func prune(arrived: Set<UUID> = [], now: Date = Date()) {
        let before = letters.count
        letters.removeAll { letter in
            if arrived.contains(letter.letterID) { return true }
            let last = [letter.expectedBy, letter.updatedAt, Optional(letter.addedAt)].compactMap { $0 }.max() ?? letter.addedAt
            return now > last.addingTimeInterval(120 * 86_400)
        }
        if letters.count != before { save() }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(letters) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
