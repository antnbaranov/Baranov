//
//  LetterTracker.swift
//  Baranov
//
//  The post office side of a letter this phone sent or is carrying.
//
//  One rule for every letter: the sender's ram walks it to the recipient's
//  gate, and the relay hands it over there. This is the half that talks to
//  the relay for the sender and for any courier carrying the ram:
//
//  1. Dispatch — `track(_:)` publishes a letter that carries a `RelayTicket`
//     right away: sealed payload, recipient, destination, rough arrival.
//     A letter whose recipient's gate isn't known yet (Code mode with an ear
//     tag only, or a Shepherd ID that hasn't set a gate) is *held* instead
//     (`hold(_:…)`): published as awaiting a gate, and the ram sets out by
//     itself the moment the recipient's phone says where its gate is.
//  2. In transit — every relay tick, each tracked letter this phone holds
//     reports how far its ram has come (only when that changed). The ticket
//     travels in the `.ram`, so after a handoff the courier's phone reports.
//  3. At the gate — the report carries the delivery package: the ram with
//     just this letter in it, for the recipient's phone to pull into their
//     mailbag.
//  4. Collected, then opened — the sender's phone polls until the
//     recipient's phone picked it up and broke the seal, and says so once.
//
//  Offline-first: every step is retried on the next tick, nothing throws
//  out of here, and without a configured server none of it runs.
//

import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class LetterTracker {
    static let shared = LetterTracker()

    enum State: String, Codable, Sendable {
        /// Written, not yet at the post office.
        case pending
        /// The relay has it and is following the ram (or waiting for the gate).
        case published
        /// The ram reached the gate and the relay holds the letter for the recipient.
        case delivered
        /// The recipient's phone picked it up.
        case collected
        /// The recipient broke the seal.
        case opened
    }

    struct Record: Codable, Identifiable, Hashable, Sendable {
        let letterID: UUID
        let lookupID: String
        let recipientName: String
        var state: State
        let createdAt: Date
        /// Held on this phone until the recipient's gate is known.
        var isAwaitingGate: Bool?
        /// The ram that will carry a held letter.
        var ramName: String?
        var id: UUID { letterID }
        var awaitsGate: Bool { isAwaitingGate == true }
    }

    /// A held letter's contents and starting point, kept on disk (it may
    /// carry a photo) until its ram sets out.
    struct HeldLetter: Codable, Sendable {
        let letter: Letter
        let ramName: String
        let originLatitude: Double
        let originLongitude: Double
        let originCity: String
        var origin: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: originLatitude, longitude: originLongitude)
        }
    }

    typealias Event = (Record) -> Void

    private(set) var records: [Record] = []

    @ObservationIgnored private weak var flock: FlockViewModel?
    @ObservationIgnored private var relay: LetterRelayService?
    @ObservationIgnored private var onCollected: Event = { _ in }
    @ObservationIgnored private var onOpened: Event = { _ in }
    @ObservationIgnored private var onSetOut: (Record, Ram) -> Void = { _, _ in }
    /// What was last reported per lookup id, so an unchanged ram costs nothing.
    @ObservationIgnored private var lastReports: [String: String] = [:]
    /// When a held letter's route was last tried, so a failing one waits.
    @ObservationIgnored private var lastSetOutAttempt: [UUID: Date] = [:]
    /// Lookup ids this phone already handed to the relay at the gate
    /// (observed: the gate card on a courier's phone reads it).
    private var reportedDeliveries: Set<String> = []
    @ObservationIgnored private var held: [UUID: HeldLetter] = [:]
    @ObservationIgnored private var isTicking = false
    @ObservationIgnored private var rerunRequested = false
    @ObservationIgnored private var arrivalReportFailed = false
    @ObservationIgnored private var arrivalRetryTask: Task<Void, Never>?

    private let recordsKey = "com.baranov.trackedLetters"
    private let deliveriesKey = "com.baranov.reportedDeliveries"
    private let heldURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        heldURL = base.appendingPathComponent("held-letters.json")
        if let data = UserDefaults.standard.data(forKey: recordsKey),
           let saved = try? JSONDecoder().decode([Record].self, from: data) {
            records = saved
        }
        if let data = try? Data(contentsOf: heldURL),
           let saved = try? JSONDecoder().decode([UUID: HeldLetter].self, from: data) {
            held = saved
        }
        reportedDeliveries = Set(UserDefaults.standard.stringArray(forKey: deliveriesKey) ?? [])
        prune()
    }

    // MARK: - Setup

    /// Called once by `RootView` when a server is configured.
    func configure(
        relay: LetterRelayService,
        flock: FlockViewModel,
        onCollected: @escaping Event,
        onOpened: @escaping Event,
        onSetOut: @escaping (Record, Ram) -> Void
    ) {
        self.relay = relay
        self.flock = flock
        self.onCollected = onCollected
        self.onOpened = onOpened
        self.onSetOut = onSetOut
    }

    /// A ticket for a new letter, or `nil` when there is no post office to
    /// follow it (no server configured) — the letter then travels exactly
    /// as it always did, on the phone and by hand.
    static func ticketIfConfigured(forCode code: String?) -> RelayTicket? {
        guard TelemetryService.isServerConfigured, let code, LetterCode.isUsableKey(code) else { return nil }
        return RelayTicket.issue(forCode: code)
    }

    // MARK: - Dispatch

    /// Queues a just-dispatched letter and publishes it straight away.
    func track(_ letter: Letter) {
        guard let ticket = letter.relayTicket,
              !records.contains(where: { $0.letterID == letter.id }) else { return }
        records.insert(Record(
            letterID: letter.id,
            lookupID: ticket.lookupID,
            recipientName: letter.recipientName,
            state: .pending,
            createdAt: Date()
        ), at: 0)
        save()
        Task { await tick() }
    }

    /// Keeps a letter whose recipient's gate isn't known yet. It is published
    /// as awaiting a gate; its ram sets out from `origin` as soon as the
    /// recipient's phone (or their Shepherd ID) says where the gate is.
    func hold(_ letter: Letter, ramName: String, origin: CLLocationCoordinate2D, originCity: String) {
        guard let ticket = letter.relayTicket,
              !records.contains(where: { $0.letterID == letter.id }) else { return }
        held[letter.id] = HeldLetter(
            letter: letter, ramName: ramName,
            originLatitude: origin.latitude, originLongitude: origin.longitude,
            originCity: originCity
        )
        saveHeld()
        records.insert(Record(
            letterID: letter.id,
            lookupID: ticket.lookupID,
            recipientName: letter.recipientName,
            state: .pending,
            createdAt: Date(),
            isAwaitingGate: true,
            ramName: ramName
        ), at: 0)
        save()
        Task { await tick() }
    }

    /// Takes back a held letter before its ram ever set out.
    func cancelHeld(_ letterID: UUID) {
        guard records.contains(where: { $0.letterID == letterID && $0.awaitsGate }) else { return }
        remove(letterID)
        SealKeyVault.remove(for: letterID)
    }

    func state(for letterID: UUID) -> State? {
        records.first { $0.letterID == letterID }?.state
    }

    /// Letters held until their recipient's gate is known — each keeps a pen.
    var heldRecords: [Record] { records.filter(\.awaitsGate) }
    var heldCount: Int { heldRecords.count }

    /// The held letter's contents, for its share message.
    func heldLetter(for letterID: UUID) -> Letter? { held[letterID]?.letter }

    /// Whether the relay is following this letter at all, from this phone's view.
    func isTracked(_ letter: Letter?) -> Bool {
        guard let letter else { return false }
        return letter.relayTicket != nil || records.contains { $0.letterID == letter.id }
    }

    /// Whether this phone already handed the letter to the relay at the gate
    /// (true for a courier too, who has no record of their own).
    func wasHandedToPostOffice(_ letter: Letter?) -> Bool {
        guard let letter else { return false }
        if let state = state(for: letter.id), state == .delivered || state == .collected || state == .opened { return true }
        guard let ticket = letter.relayTicket else { return false }
        return reportedDeliveries.contains(ticket.lookupID)
    }

    // MARK: - Tick

    /// Publish what's waiting, set out what learned its gate, report what
    /// moved, and check on what arrived.
    func tick() async {
        guard let relay, let flock else { return }
        // A request that lands mid-tick (a ram reaching its gate while the
        // minute tick is running) used to be dropped until the next minute.
        // It now runs once more right after this one.
        guard !isTicking else { rerunRequested = true; return }
        isTicking = true
        defer { isTicking = false }
        repeat {
            rerunRequested = false
            arrivalReportFailed = false
            await publishPending(relay: relay, flock: flock)
            await setOutHeld(relay: relay, flock: flock)
            await reportProgress(relay: relay, flock: flock)
            await pollDelivered(relay: relay)
        } while rerunRequested
        // The delivery itself failed to reach the post office (offline, or
        // the letter isn't there yet): don't wait a whole minute to retry,
        // the recipient is waiting for the push.
        if arrivalReportFailed { scheduleArrivalRetry() }
    }

    /// Call whenever the flock changes: a ram that just reached the
    /// recipient's gate is reported to the post office right away, which is
    /// what makes the relay push both phones and hand the letter over.
    func flockChanged() {
        guard relay != nil, let flock else { return }
        let waiting = flock.activeRams.contains { ram in
            guard Self.isCustodian(of: ram),
                  ram.status == .arrivedAtGate || ram.wasDeliveredInPerson else { return false }
            return ([ram.letter].compactMap { $0 } + ram.passengerLetters).contains { letter in
                guard let ticket = letter.relayTicket else { return false }
                return !reportedDeliveries.contains(ticket.lookupID)
            }
        }
        guard waiting else { return }
        Task { await tick() }
    }

    private func scheduleArrivalRetry() {
        guard arrivalRetryTask == nil else { return }
        arrivalRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled else { return }
            self.arrivalRetryTask = nil
            await self.tick()
        }
    }

    private func publishPending(relay: LetterRelayService, flock: FlockViewModel) async {
        let senderAddress = AddressKeychain.inboxToken == nil ? nil : RecipientKeyring.myAddress
        for record in records where record.state == .pending {
            let letter: Letter
            let tracking: LetterRelayService.TrackingBody
            let origin: CLLocationCoordinate2D
            let originName: String
            let ramName: String

            if record.awaitsGate {
                guard let kept = held[record.letterID] else { remove(record.letterID); continue }
                letter = kept.letter
                origin = kept.origin
                originName = kept.originCity
                ramName = kept.ramName
                guard let ticket = letter.relayTicket else { remove(record.letterID); continue }
                tracking = LetterRelayService.TrackingBody(
                    progressToken: ticket.progressToken,
                    letterId: letter.id.uuidString,
                    recipientName: String(letter.recipientName.prefix(80)),
                    destinationName: "",
                    totalMeters: 0,
                    expectedBy: nil,
                    senderAddress: senderAddress,
                    awaitingGate: true
                )
            } else {
                guard let found = Self.find(record.letterID, in: flock.activeRams) else {
                    // Recalled before it ever reached the post office.
                    if Date().timeIntervalSince(record.createdAt) > 3_600 { remove(record.letterID) }
                    continue
                }
                let ram = found.0
                letter = found.1
                origin = ram.originCoordinate ?? ram.currentCoordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                originName = ram.stamps.first { $0.kind == .setOut }?.placeName ?? ram.routeHistory.first?.cityName ?? ram.currentCity
                ramName = ram.name
                guard let ticket = letter.relayTicket else { remove(record.letterID); continue }
                tracking = LetterRelayService.TrackingBody(
                    progressToken: ticket.progressToken,
                    letterId: letter.id.uuidString,
                    recipientName: String(letter.recipientName.prefix(80)),
                    destinationName: String(ram.targetCity.prefix(120)),
                    totalMeters: ram.journeyStepsSoFar + ram.remainingSteps,
                    expectedBy: ram.expectedArrival?.ISO8601Format(),
                    senderAddress: senderAddress,
                    awaitingGate: nil
                )
            }
            guard let ticket = letter.relayTicket,
                  let code = SealKeyVault.code(for: letter.id),
                  LetterCode.lookupID(for: code) == ticket.lookupID else {
                remove(record.letterID)
                continue
            }
            let addressed = letter.recipientKeys?.first.map {
                LetterRelayService.Recipient(address: $0.address, wrappedKey: $0.wrapped)
            }
            do {
                try await publish(relay: relay, letter: letter, code: code, originName: originName,
                                  origin: origin, ramName: ramName, addressed: addressed, tracking: tracking)
                setState(.published, for: record.letterID)
                lastReports[ticket.lookupID] = nil
            } catch RelayError.conflict {
                // Published on an earlier try whose answer never came back.
                setState(.published, for: record.letterID)
            } catch {
                continue
            }
        }
    }

    /// Publishes, falling back to an unaddressed letter when the profile
    /// the key was sealed to isn't registered (the key still travels in
    /// the `.ram`, so an in-person delivery still opens by itself).
    private func publish(
        relay: LetterRelayService, letter: Letter, code: String, originName: String,
        origin: CLLocationCoordinate2D, ramName: String,
        addressed: LetterRelayService.Recipient?, tracking: LetterRelayService.TrackingBody
    ) async throws {
        do {
            try await relay.publish(letter: letter, code: code, originName: originName, origin: origin,
                                    ramName: ramName, addressedTo: addressed, tracking: tracking)
        } catch RelayError.notFound where addressed != nil {
            try await relay.publish(letter: letter, code: code, originName: originName, origin: origin,
                                    ramName: ramName, addressedTo: nil, tracking: tracking)
        }
    }

    /// A held letter whose recipient's gate is now known: plan the road from
    /// where the sender wrote it, and send the ram on its way.
    private func setOutHeld(relay: LetterRelayService, flock: FlockViewModel) async {
        for record in records where record.awaitsGate && record.state == .published {
            if let last = lastSetOutAttempt[record.letterID], Date().timeIntervalSince(last) < 600 { continue }
            guard let kept = held[record.letterID],
                  let tracking = try? await relay.tracking(id: record.lookupID),
                  let gate = tracking.gate else { continue }
            lastSetOutAttempt[record.letterID] = Date()
            guard let ram = try? await RamRoutePlanner.makeRam(
                name: kept.ramName, letter: kept.letter, origin: kept.origin, originCity: kept.originCity,
                destination: gate.coordinate, destinationCity: gate.city
            ) else { continue }
            // The held letter was keeping this pen; hand it to the ram.
            setAwaitingGate(false, for: record.letterID)
            guard flock.dispatch(ram) else {
                setAwaitingGate(true, for: record.letterID)
                continue
            }
            held[record.letterID] = nil
            saveHeld()
            lastReports[record.lookupID] = nil
            lastSetOutAttempt[record.letterID] = nil
            if let current = records.first(where: { $0.letterID == record.letterID }) {
                onSetOut(current, ram)
            }
        }
    }

    private func reportProgress(relay: LetterRelayService, flock: FlockViewModel) async {
        for ram in flock.activeRams where Self.isCustodian(of: ram) {
            let letters = ([ram.letter].compactMap { $0 } + ram.passengerLetters).filter { $0.relayTicket != nil }
            for letter in letters {
                guard let ticket = letter.relayTicket, !reportedDeliveries.contains(ticket.lookupID) else { continue }
                // Not at the post office yet: nothing there to update.
                if state(for: letter.id) == .pending { continue }

                let arrived = ram.status == .arrivedAtGate || ram.wasDeliveredInPerson
                let walked = ram.journeyStepsSoFar
                let signature = "\(ram.status.rawValue)|\(walked / 100)|\(ram.currentCity)"
                if !arrived, lastReports[ticket.lookupID] == signature { continue }

                let progress = RelayProgress(
                    metersWalked: walked,
                    metersToGo: arrived ? 0 : ram.remainingSteps,
                    status: arrived ? .arrivedAtGate : ram.status,
                    currentCity: ram.currentCity,
                    destinationName: ram.targetCity,
                    coordinate: ram.currentCoordinate,
                    expectedBy: arrived ? nil : ram.expectedArrival,
                    package: arrived ? Self.deliveryPackage(of: ram, carrying: letter) : nil
                )
                do {
                    let receipt = try await relay.reportProgress(id: ticket.lookupID, token: ticket.progressToken, progress: progress)
                    lastReports[ticket.lookupID] = signature
                    if receipt.delivered {
                        reportedDeliveries.insert(ticket.lookupID)
                        saveDeliveries()
                        if state(for: letter.id) == .published { setState(.delivered, for: letter.id) }
                    }
                    if receipt.claimed { markCollected(letter.id) }
                } catch RelayError.unauthorized {
                    // Not this ticket's letter at the post office; stop asking.
                    reportedDeliveries.insert(ticket.lookupID)
                    saveDeliveries()
                } catch {
                    // Not published yet (a courier ahead of the sender), or offline.
                    if arrived { arrivalReportFailed = true }
                    continue
                }
            }
        }
    }

    private func pollDelivered(relay: LetterRelayService) async {
        for record in records where record.state == .published || record.state == .delivered || record.state == .collected {
            if record.awaitsGate { continue }
            guard let status = try? await relay.status(id: record.lookupID) else { continue }
            if status.openedAt != nil {
                markCollected(record.letterID)
                markOpened(record.letterID)
            } else if status.claimed {
                markCollected(record.letterID)
            } else if status.delivered == true, record.state == .published {
                setState(.delivered, for: record.letterID)
            }
        }
    }

    // MARK: - Helpers

    /// Whether this phone is the one carrying the ram right now (or handed it
    /// to the recipient in person, which is a delivery too). The recipient's
    /// own copy never reports.
    private static func isCustodian(of ram: Ram) -> Bool {
        guard !ram.addressedToThisPhone else { return false }
        switch ram.status {
        case .grazing, .walking, .waitingForHandoff, .atSea, .arrivedAtGate: return true
        case .handedOff: return ram.wasDeliveredInPerson
        case .delivered: return false
        }
    }

    /// The ram as the recipient receives it: this one letter, at the gate,
    /// with its passport, and nothing that belongs to the sender or courier.
    static func deliveryPackage(of ram: Ram, carrying letter: Letter) -> RamTransitPackage {
        var copy = ram
        var delivered = letter
        delivered.relayTicket = nil
        copy.letter = delivered
        copy.passengerLetters = []
        copy.status = .arrivedAtGate
        copy.isGuest = false
        copy.addressedToThisPhone = false
        copy.recallRequestedAt = nil
        copy.custodyOrigin = nil
        copy.custodySince = nil
        copy.stepsWalked = copy.totalStepsRequired
        return RamTransitPackage(ram: copy)
    }

    private static func find(_ letterID: UUID, in rams: [Ram]) -> (Ram, Letter)? {
        for ram in rams {
            if let letter = ram.letter, letter.id == letterID { return (ram, letter) }
            if let passenger = ram.passengerLetters.first(where: { $0.id == letterID }) { return (ram, passenger) }
        }
        return nil
    }

    private func markCollected(_ letterID: UUID) {
        guard let index = records.firstIndex(where: { $0.letterID == letterID }) else { return }
        let state = records[index].state
        guard state != .collected, state != .opened else { return }
        records[index].state = .collected
        save()
        onCollected(records[index])
    }

    private func markOpened(_ letterID: UUID) {
        guard let index = records.firstIndex(where: { $0.letterID == letterID }),
              records[index].state != .opened else { return }
        records[index].state = .opened
        save()
        onOpened(records[index])
    }

    private func setState(_ state: State, for letterID: UUID) {
        guard let index = records.firstIndex(where: { $0.letterID == letterID }) else { return }
        records[index].state = state
        save()
    }

    private func setAwaitingGate(_ awaiting: Bool, for letterID: UUID) {
        guard let index = records.firstIndex(where: { $0.letterID == letterID }) else { return }
        records[index].isAwaitingGate = awaiting
        save()
    }

    private func remove(_ letterID: UUID) {
        records.removeAll { $0.letterID == letterID }
        if held.removeValue(forKey: letterID) != nil { saveHeld() }
        save()
    }

    /// Finished letters are kept for two months, for the gate card.
    private func prune(now: Date = Date()) {
        let before = records.count
        records.removeAll {
            ($0.state == .collected || $0.state == .opened) && now.timeIntervalSince($0.createdAt) > 60 * 86_400
        }
        if records.count != before { save() }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: recordsKey)
    }

    private func saveHeld() {
        guard let data = try? JSONEncoder().encode(held) else { return }
        try? FileManager.default.createDirectory(at: heldURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: heldURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func saveDeliveries() {
        UserDefaults.standard.set(Array(Array(reportedDeliveries).suffix(300)), forKey: deliveriesKey)
    }
}
