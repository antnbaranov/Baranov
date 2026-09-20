//
//  FlockViewModel.swift
//  Baranov
//
//  Owns the flock of rams currently in play: applying real-world step
//  progress from CoreMotion, moving rams into and out of AirDrop handoffs,
//  resolving the next real driving leg after a handoff, and revealing
//  letters through the wax-seal arrival ritual.
//
//  All mutation happens on the main actor so UI observers never race with
//  background pedometer/telemetry callbacks; callers on other actors must
//  hop to @MainActor before invoking these methods.
//

import CoreLocation
import Foundation
import Observation
import ActivityKit
import WidgetKit

@Observable
@MainActor
final class FlockViewModel {
    /// The absolute ceiling on concurrent rams, free slot included — what
    /// "Expand the Pasture" ultimately unlocks all the way to. Matches the
    /// "Five Rams at Once" the paywall itself advertises.
    static let pastureCapacity = 5

    var activeRams: [Ram] = [] {
        didSet { persist() }
    }
    var selectedRamId: UUID? {
        didSet { persist() }
    }
    var maxAllowedRams: Int = 1

    /// Where the flock is written through to on every change, and read
    /// back from at launch. `nil` for previews and throwaway instances.
    private let store: FlockStore?

    init(activeRams: [Ram] = [], maxAllowedRams: Int = 1) {
        self.store = nil
        self.activeRams = activeRams
        self.maxAllowedRams = maxAllowedRams
    }

    /// The real flock: whatever was on disk when the app last ran, or an
    /// empty pasture on a fresh install. Every mutation from here on is
    /// written straight back through `store`.
    init(store: FlockStore) {
        self.store = store
        if let snapshot = store.load() {
            self.activeRams = snapshot.activeRams
            self.selectedRamId = snapshot.selectedRamId
        }
        PhoneWatchSessionManager.shared.onStepsReceived = { [weak self] steps in
            guard let self else { return }
            if let active = self.activeRams.first(where: { $0.status == .walking }) ?? self.activeRams.first {
                self.addStepProgress(ramId: active.id, steps: steps)
            }
        }
        if let active = self.activeRams.first(where: { $0.status == .walking }) ?? self.activeRams.first {
            self.startOrUpdateLiveActivity(for: active)
        }
    }

    /// Coalesces bursts of mutations (a pedometer update lands every few
    /// seconds and touches `activeRams` each time) into one write shortly
    /// after the last change, rather than rewriting a flock with three
    /// legs of road polylines on every step.
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    // MARK: - Live Activity

    @ObservationIgnored private var liveActivities: [UUID: Activity<RamActivityAttributes>] = [:]
    @ObservationIgnored private var lastActivityUpdate: [UUID: Date] = [:]
    private let activityUpdateInterval: TimeInterval = 60

    func startOrUpdateLiveActivity(for ram: Ram) {
        let state = contentState(for: ram)
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            if let existing = liveActivities[ram.id] {
                let now = Date()
                if let last = lastActivityUpdate[ram.id], now.timeIntervalSince(last) < activityUpdateInterval {
                    // Throttle ActivityKit updates to avoid system limits
                } else {
                    lastActivityUpdate[ram.id] = now
                    Task { await existing.update(using: state) }
                }
            } else {
                let attrs = RamActivityAttributes(ramName: ram.name, fromCity: ram.currentCity, toCity: ram.targetCity)
                do {
                    let activity = try Activity.request(
                        attributes: attrs,
                        content: .init(state: state, staleDate: Date().addingTimeInterval(30 * 60))
                    )
                    liveActivities[ram.id] = activity
                    lastActivityUpdate[ram.id] = Date()
                } catch { /* not supported or authorized */ }
            }
        }
        PhoneWatchSessionManager.shared.syncRamState(
            ramName: ram.name,
            fromCity: ram.currentCity,
            toCity: ram.targetCity,
            progress: state.progress,
            remainingSteps: state.remainingSteps,
            remainingDistance: state.remainingDistance,
            statusSymbol: state.statusSymbol,
            statusLabel: state.statusLabel,
            isAtSea: ram.status == .atSea,
            seaVoyageTitle: ram.voyage.map { "\($0.departurePortName) → \($0.arrivalPortName)" }
        )
        WidgetCenter.shared.reloadAllTimelines()
    }

    func endLiveActivity(for ramId: UUID) {
        guard let activity = liveActivities[ramId] else { return }
        Task { await activity.end(nil, dismissalPolicy: .after(Date().addingTimeInterval(5))) }
        liveActivities.removeValue(forKey: ramId)
        lastActivityUpdate.removeValue(forKey: ramId)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func contentState(for ram: Ram) -> RamActivityAttributes.ContentState {
        let remaining = max(0, ram.totalStepsRequired - ram.stepsWalked)
        let progress = ram.totalStepsRequired > 0 ? min(1.0, Double(ram.stepsWalked) / Double(ram.totalStepsRequired)) : 0
        let distanceStr = remaining >= 1000 ? String(format: "%.1f km", Double(remaining) / 1000) : "\(remaining) m"
        return RamActivityAttributes.ContentState(
            progress: progress,
            remainingSteps: remaining,
            remainingDistance: distanceStr,
            statusSymbol: ram.status.symbolName,
            statusLabel: ram.status.displayName
        )
    }

    private func persist() {
        guard let store else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            store.save(FlockStore.Snapshot(
                activeRams: self.activeRams,
                selectedRamId: self.selectedRamId,
                savedAt: Date()
            ))
        }
    }

    /// Every letter delivered to this device, across the whole flock —
    /// what the flock-metric telemetry and the RevenueCat customer
    /// attributes both report.
    var lettersDelivered: Int {
        activeRams.filter { $0.status == .delivered }.count
    }

    /// Steps walked across every ram currently tracked, all legs included.
    var totalStepsWalked: Int {
        activeRams.reduce(0) { $0 + $1.journeyStepsSoFar }
    }

    /// Whether the pasture has room for one more ram right now — the
    /// single question "Slide to Dispatch", AirDrop imports and the
    /// hoofbeat relay all ask before admitting a ram. Composing a letter
    /// is never gated on this (the form is always reachable); only the
    /// moment of dispatch is, and a `false` here at that moment is what
    /// sends the letter to Drafts and opens "Expand the Pasture".
    var hasFreeRamSlot: Bool {
        // A ram that has been passed to another carrier is kept here as
        // history, not as livestock: it walks on nobody's steps and must
        // not go on occupying a pen the person has paid for.
        activeRams.filter { $0.status != .handedOff }.count < maxAllowedRams
    }

    /// Whether importing this AirDropped package would be admitted right
    /// now: a ram already tracked locally can always be re-imported
    /// (idempotent, e.g. resuming a leg after a handoff), while a
    /// brand-new ram is only admitted while under `maxAllowedRams`.
    func canImport(_ package: RamTransitPackage) -> Bool {
        activeRams.contains { $0.id == package.ram.id } || hasFreeRamSlot
    }

    /// Applies real-world steps (from CoreMotion) toward a ram's current
    /// leg. Silently ignores unknown rams, non-positive step counts, and
    /// rams that are not currently eligible to walk — background pedometer
    /// callbacks must never be interrupted by a thrown error.
    ///
    /// Reaching the leg's step quota logs the leg's endpoint to
    /// `routeHistory` and either hands the ram to `.waitingForHandoff` (an
    /// ocean/border gap remains before `targetCity`) or `.arrivedAtGate`
    /// (this leg's end IS the final destination).
    func addStepProgress(ramId: UUID, steps: Int) {
        guard steps > 0, let index = activeRams.firstIndex(where: { $0.id == ramId }) else { return }

        var ram = activeRams[index]
        guard ram.status == .grazing || ram.status == .walking else { return }

        if ram.status == .grazing {
            ram.status = .walking
        }

        ram.stepsWalked = min(ram.totalStepsRequired, ram.stepsWalked + steps)

        if ram.stepsWalked >= ram.totalStepsRequired {
            let endpoint = ram.routeCoordinates.last?.clLocationCoordinate

            // Stamp the leg's endpoint before `routeHistory` grows, so
            // `journeyStepsSoFar` still reads as "steps up to arriving
            // here" rather than double-counting the leg that just closed.
            appendStamp(
                to: &ram,
                placeName: ram.legDestinationCity,
                kind: ram.requiresHandoffAtLegEnd ? .handoff : .arrival,
                coordinate: endpoint
            )

            ram.routeHistory.append(RouteNode(
                cityName: ram.legDestinationCity,
                latitude: endpoint?.latitude ?? 0,
                longitude: endpoint?.longitude ?? 0,
                carrierName: ram.name,
                stepsContributed: ram.stepsWalked
            ))
            ram.currentCity = ram.legDestinationCity
            ram.status = ram.requiresHandoffAtLegEnd ? .waitingForHandoff : .arrivedAtGate
        }

        activeRams[index] = ram
        startOrUpdateLiveActivity(for: ram)
    }

    /// Records a passport stamp for a real, named place this ram has just
    /// walked past — called by `JourneyView` when accumulated steps carry
    /// the ram beyond whatever `NextLandmarkService` resolved ahead of it.
    /// Silently ignores unknown rams and places already stamped on this
    /// journey, so a step stream that fires repeatedly around the same
    /// spot can never fill a passport with duplicates.
    func recordStamp(
        ramId: UUID,
        placeName: String,
        kind: JourneyStampKind,
        coordinate: CLLocationCoordinate2D?
    ) {
        guard let index = activeRams.firstIndex(where: { $0.id == ramId }) else { return }
        var ram = activeRams[index]
        appendStamp(to: &ram, placeName: placeName, kind: kind, coordinate: coordinate)
        activeRams[index] = ram
    }

    /// The single place a stamp is actually minted, so every awarding path
    /// — passing a landmark, closing a leg, setting out — shares one
    /// dedupe rule and one notion of "who was carrying it".
    private func appendStamp(
        to ram: inout Ram,
        placeName: String,
        kind: JourneyStampKind,
        coordinate: CLLocationCoordinate2D?
    ) {
        let trimmed = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !ram.hasStamp(named: trimmed) else { return }

        ram.stamps.append(JourneyStamp(
            placeName: trimmed,
            kind: kind,
            latitude: coordinate?.latitude ?? 0,
            longitude: coordinate?.longitude ?? 0,
            stepsAtStamp: ram.journeyStepsSoFar,
            carrierName: Self.currentCarrierName(fallback: ram.name)
        ))
    }

    /// Whoever is holding the ram right now — the person's own name from
    /// onboarding, not the ram's. After a handoff that's a different
    /// person than the one who walked the previous leg, and a passport
    /// that says so is the whole point of a relay.
    private static func currentCarrierName(fallback: String) -> String {
        let stored = UserDefaults.standard
            .string(forKey: "com.baranov.carrierDisplayName")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stored, !stored.isEmpty else { return fallback }
        return stored
    }

    /// Moves a ram straight into the handoff queue ahead of schedule, e.g.
    /// when the carrier reaches a border or coastline before completing
    /// its step quota for the leg.
    func markHandoffReady(ramId: UUID) {
        guard let index = activeRams.firstIndex(where: { $0.id == ramId }) else { return }
        var ram = activeRams[index]
        guard ram.status == .grazing || ram.status == .walking else { return }
        ram.status = .waitingForHandoff
        activeRams[index] = ram
    }

    /// Completes the wax-seal long-press ritual: decrypts the ram's letter
    /// with the recipient's receiving code, unseals it, and marks the ram
    /// delivered. Throws `LetterCipherError.wrongCode` — and changes
    /// nothing — if the code doesn't fit. No-ops unless the ram has
    /// actually arrived at the recipient's gate.
    func openDeliveredLetter(ramId: UUID, receivingCode: String) throws {
        guard let index = activeRams.firstIndex(where: { $0.id == ramId }) else { return }
        var ram = activeRams[index]
        guard ram.status == .arrivedAtGate, var letter = ram.letter else { return }
        try letter.open(withReceivingCode: receivingCode)
        ram.letter = letter
        ram.status = .delivered
        activeRams[index] = ram
    }

    /// Opens one of the passenger letters riding on a ram that has reached
    /// the gate, for a recipient standing there with its code.
    func openPassengerLetter(ramId: UUID, letterId: UUID, receivingCode: String) throws {
        guard let index = activeRams.firstIndex(where: { $0.id == ramId }),
              let letterIndex = activeRams[index].passengerLetters.firstIndex(where: { $0.id == letterId })
        else { return }
        var letter = activeRams[index].passengerLetters[letterIndex]
        try letter.open(withReceivingCode: receivingCode)
        activeRams[index].passengerLetters[letterIndex] = letter
    }

    /// Attaches another ram's letter to this one as a passenger — carried
    /// alongside the ram's own letter toward the ram's own single
    /// `targetCity`, without spending a separate pasture slot tracking a
    /// whole new ram for it. No-ops on an unknown ram id.
    func addPassengerLetter(_ letter: Letter, to ramId: UUID) {
        guard let index = activeRams.firstIndex(where: { $0.id == ramId }) else { return }
        activeRams[index].passengerLetters.append(letter)
    }

    /// Adds a freshly-composed ram to the flock, gated by `maxAllowedRams`
    /// (the same "Expand the Pasture" limit AirDrop imports respect).
    /// Returns whether the ram was actually dispatched — `false` means the
    /// caller should present the pasture-expansion paywall instead.
    @discardableResult
    func dispatch(_ ram: Ram) -> Bool {
        guard hasFreeRamSlot else { return false }

        // The first page of the passport: where this journey set out from.
        // Stamped at dispatch rather than on the first recorded step, so a
        // ram that hasn't moved yet still shows an honest, non-empty
        // passport instead of a blank page.
        var dispatched = ram
        // A dispatched ram always sets out from the polyline's first
        // vertex: progress is forced to exactly zero and the status back
        // to `.grazing` regardless of what the caller built, so
        // `currentCoordinate` resolves to `routeCoordinates[0]` on the
        // very first frame. Any step baseline the pedometer already holds
        // is `JourneyView`'s to discard (it restarts tracking per ram id)
        // — nothing recorded before this moment may move this ram.
        dispatched.stepsWalked = 0
        dispatched.status = .grazing
        appendStamp(
            to: &dispatched,
            placeName: dispatched.currentCity,
            kind: .setOut,
            coordinate: dispatched.routeCoordinates.first?.clLocationCoordinate
        )

        activeRams.append(dispatched)
        selectedRamId = dispatched.id
        return true
    }

    /// Recalls a ram that is still on this device — walking, grazing or
    /// parked at a handoff — and takes it out of the flock entirely, so
    /// its pasture slot frees up and the letter it carried is withdrawn.
    /// The sealed letter's receiving code is forgotten with it (nothing
    /// can arrive any more, so nothing should be openable). No-ops for a
    /// ram that has already reached the gate or been delivered: those
    /// are archived history, not something to un-send. This is only ever
    /// reached through the deliberate "Slide to Recall" gesture, never a
    /// plain tap.
    @discardableResult
    func recall(ramId: UUID) -> Bool {
        guard let index = activeRams.firstIndex(where: { $0.id == ramId }) else { return false }
        let ram = activeRams[index]
        guard ram.status == .grazing || ram.status == .walking || ram.status == .waitingForHandoff else {
            // Not `.atSea` (the packet has it and there is nobody to ask),
            // not `.handedOff` (it is someone else's to carry now), and
            // not arrived/delivered (that is history, not a live send).
            return false
        }

        if let letter = ram.letter {
            SealKeyVault.remove(for: letter.id)
        }
        for passenger in ram.passengerLetters {
            SealKeyVault.remove(for: passenger.id)
        }

        activeRams.remove(at: index)
        endLiveActivity(for: ramId)
        if selectedRamId == ramId {
            selectedRamId = activeRams.first?.id
        }
        return true
    }

    /// Imports a ram received over AirDrop or a hoofbeat handoff.
    ///
    /// Re-importing a ram already tracked locally updates it in place
    /// (idempotent); a brand-new ram is admitted only while under
    /// `maxAllowedRams`, so a completed paywall unlock is required before
    /// the flock can grow.
    ///
    /// `receivedAt` is where the person taking the ram is actually
    /// standing. It matters more than it looks: a ram handed over
    /// mid-walk arrives carrying the *sender's* road polyline, and
    /// without re-resolving it the new carrier would be walking a street
    /// they are nowhere near. See `resumeLeg(for:from:)`.
    func importPackage(
        _ package: RamTransitPackage,
        receivedAt coordinate: CLLocationCoordinate2D? = nil
    ) async {
        var importedRam = package.ram
        let alreadyTracked = activeRams.contains { $0.id == importedRam.id }

        guard alreadyTracked || hasFreeRamSlot else { return }

        switch importedRam.status {
        case .waitingForHandoff, .atSea:
            // Someone took the ram off the quay. If they are standing
            // somewhere a road reaches the destination from, the crossing
            // has effectively already happened and the booked passage is
            // cancelled inside `beginNextLeg`. If they are still on the
            // near shore, the booking stands — taking a letter into your
            // pocket must never make it slower than leaving it for the
            // packet.
            importedRam.status = .waitingForHandoff
            await beginNextLeg(for: &importedRam, from: coordinate)
        case .grazing, .walking, .handedOff:
            await resumeLeg(for: &importedRam, from: coordinate)
            // A ram handed away and then given back is livestock again,
            // even if its route couldn't be re-resolved just now —
            // otherwise it would sit here permanently marked as somebody
            // else's and never take another step.
            if importedRam.status == .handedOff {
                importedRam.status = .grazing
            }
        case .arrivedAtGate, .delivered:
            break
        }

        if let index = activeRams.firstIndex(where: { $0.id == importedRam.id }) {
            activeRams[index] = importedRam
        } else {
            activeRams.append(importedRam)
        }

        selectedRamId = importedRam.id
    }

    /// Records that a ram has been given to another carrier.
    ///
    /// The ram is deliberately NOT deleted. A handoff has no delivery
    /// receipt — the other phone may refuse the ram because its pasture is
    /// full, or the transfer may simply fail — and a letter that vanished
    /// from both devices would be gone for good. Keeping it as
    /// `.handedOff` means the journey and its passport stay readable here,
    /// the ram stops walking on this person's steps (so a relayed letter
    /// can never be advanced twice), and the pasture slot is released.
    func markHandedOff(ramId: UUID, to carrierName: String?) {
        guard let index = activeRams.firstIndex(where: { $0.id == ramId }) else { return }
        var ram = activeRams[index]
        guard ram.status != .delivered, ram.status != .arrivedAtGate, ram.status != .handedOff else { return }

        let recipient = (carrierName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        appendStamp(
            to: &ram,
            placeName: recipient.isEmpty ? "Handed on" : "Handed to \(recipient)",
            kind: .handoff,
            coordinate: ram.currentCoordinate
        )
        ram.status = .handedOff
        activeRams[index] = ram

        if selectedRamId == ramId {
            selectedRamId = activeRams.first { $0.status != .handedOff && $0.status != .delivered }?.id ?? selectedRamId
        }
    }

    // MARK: - The packet

    /// Books a passage for every ram standing at a port with no crossing
    /// arranged yet.
    ///
    /// This is what makes the ocean gap survivable. A peer-to-peer handoff
    /// is a gift, not a guarantee: the odds that somebody beside you is
    /// about to cross the exact water your letter needs are effectively
    /// zero, and without a scheduled boat a letter simply dies at the
    /// coast. Booking one turns the human handoff into the shortcut it
    /// should be rather than the only door.
    func bookPendingPassages(now: Date = Date()) async {
        let waiting = activeRams.filter { $0.status == .waitingForHandoff && $0.voyage == nil }

        for ram in waiting {
            guard let port = ram.routeCoordinates.last?.clLocationCoordinate ?? ram.currentCoordinate else { continue }

            let voyage = await PacketShipService.bookPassage(
                from: port,
                portName: ram.legDestinationCity,
                toward: ram.finalDestinationCoordinate.clLocationCoordinate,
                departingAfter: now
            )

            // Re-find the ram rather than reusing an index captured before
            // the await: a step callback or another import may have
            // reshaped `activeRams` while the route requests were in
            // flight, and a stale index would write over the wrong ram.
            guard let voyage,
                  let index = activeRams.firstIndex(where: { $0.id == ram.id }),
                  activeRams[index].status == .waitingForHandoff,
                  activeRams[index].voyage == nil
            else { continue }

            activeRams[index].voyage = voyage
        }
    }

    /// Moves booked rams along the schedule: casts off the ones whose
    /// departure has passed, and lands the ones whose crossing is over,
    /// resolving the onward road leg from the arrival port.
    ///
    /// Driven by the wall clock rather than a running timer, so a crossing
    /// continues while the app is closed — the way a ship would — and a
    /// person who opens Baranov after two days finds the letter on the
    /// far shore, not still waiting for the app's attention.
    func advanceVoyages(now: Date = Date()) async {
        for index in activeRams.indices {
            guard activeRams[index].status == .waitingForHandoff,
                  let voyage = activeRams[index].voyage,
                  voyage.hasDeparted(by: now)
            else { continue }

            var ram = activeRams[index]
            appendStamp(
                to: &ram,
                placeName: voyage.departurePortName,
                kind: .water,
                coordinate: voyage.departurePort.clLocationCoordinate
            )
            ram.status = .atSea
            activeRams[index] = ram
        }

        let landing = activeRams.filter { ram in
            ram.status == .atSea && (ram.voyage?.hasLanded(by: now) ?? false)
        }

        for ram in landing {
            guard let voyage = ram.voyage else { continue }
            var updated = ram
            let shore = voyage.arrivalPort.clLocationCoordinate

            appendStamp(
                to: &updated,
                placeName: voyage.arrivalPortName,
                kind: .arrival,
                coordinate: shore
            )
            updated.routeHistory.append(RouteNode(
                cityName: voyage.arrivalPortName,
                latitude: shore.latitude,
                longitude: shore.longitude,
                carrierName: "The packet",
                stepsContributed: 0
            ))
            updated.currentCity = voyage.arrivalPortName
            updated.legDestinationCity = voyage.arrivalPortName
            updated.voyage = nil
            // Park the ram exactly on the quay it landed at, so that if the
            // onward route can't be resolved right now it sits at the new
            // port on the map rather than on the polyline it sailed from.
            updated.routeCoordinates = [RamCoordinate(shore)]
            updated.stepsWalked = 0
            updated.status = .waitingForHandoff

            await beginNextLeg(for: &updated, from: shore)

            guard let index = activeRams.firstIndex(where: { $0.id == ram.id }) else { continue }
            activeRams[index] = updated
        }
    }

    // MARK: - Leg resolution

    /// Resolves the leg from wherever a ram now sits toward its true final
    /// destination (`targetCity`).
    ///
    /// If that's drivable the ram is cleared to keep walking as a fresh
    /// leg, and any booked passage is cancelled — the water has been
    /// crossed, by boat or in somebody's pocket, and the schedule no
    /// longer applies. If it isn't drivable the ram stays
    /// `.waitingForHandoff` with its booking intact, and
    /// `bookPendingPassages` will arrange one if it has none, so a journey
    /// that needs two crossings gets two.
    ///
    /// `origin` is where the ram actually is — the receiving carrier's own
    /// position when there is one, falling back to the end of the leg it
    /// just finished.
    private func beginNextLeg(for ram: inout Ram, from origin: CLLocationCoordinate2D?) async {
        let start = origin
            ?? ram.routeCoordinates.last?.clLocationCoordinate
            ?? ram.currentCoordinate

        guard let start else { return }

        do {
            let leg = try await RouteService.drivingRoute(
                from: start,
                to: ram.finalDestinationCoordinate.clLocationCoordinate
            )
            ram.routeCoordinates = leg.coordinates
            ram.totalStepsRequired = leg.distanceMeters
            ram.stepsWalked = 0
            ram.legDestinationCity = ram.targetCity
            ram.requiresHandoffAtLegEnd = false
            ram.voyage = nil
            // A route of a few dozen meters means the ram is already
            // standing at the gate — landing a packet right at the
            // recipient's door shouldn't demand one more block of walking.
            ram.status = leg.distanceMeters <= 25 ? .arrivedAtGate : .grazing
        } catch {
            // Still water in the way (or a transient failure): keep any
            // booking already made and wait — for the packet, or for a
            // person, whichever comes first.
            ram.status = .waitingForHandoff
        }
    }

    /// Re-resolves the leg a ram was already walking, from the position of
    /// whoever has just taken it.
    ///
    /// Without this a mid-walk handoff is quietly broken: the package
    /// carries the previous carrier's road polyline, and the new carrier's
    /// steps would push the ram along a street on the other side of the
    /// city. Re-resolving also makes the relay honest about cost — a
    /// carrier who is farther from the destination gets a longer leg,
    /// because they are, in fact, farther away.
    ///
    /// With no location fix the sender's leg is kept as-is: a wrong route
    /// is worse than a slightly stale one.
    private func resumeLeg(for ram: inout Ram, from origin: CLLocationCoordinate2D?) async {
        guard let origin else { return }

        let destination = ram.requiresHandoffAtLegEnd
            ? (ram.routeCoordinates.last?.clLocationCoordinate ?? ram.finalDestinationCoordinate.clLocationCoordinate)
            : ram.finalDestinationCoordinate.clLocationCoordinate

        guard let leg = try? await RouteService.drivingRoute(from: origin, to: destination) else { return }

        // Bank the steps the previous carrier walked before handing it on,
        // so the passport's running total survives the relay instead of
        // restarting at zero on the new phone.
        if ram.stepsWalked > 0 {
            ram.routeHistory.append(RouteNode(
                cityName: ram.currentCity,
                latitude: ram.currentCoordinate?.latitude ?? 0,
                longitude: ram.currentCoordinate?.longitude ?? 0,
                carrierName: ram.name,
                stepsContributed: ram.stepsWalked
            ))
        }

        ram.routeCoordinates = leg.coordinates
        ram.totalStepsRequired = leg.distanceMeters
        ram.stepsWalked = 0
        ram.status = .grazing
    }

}

#if DEBUG
extension FlockViewModel {
    /// Realistic preview data for SwiftUI canvases: Klaus, en route from
    /// Burnaby toward Frankfurt by way of Calgary and Gander — the classic
    /// last mainland stop before the Atlantic — where he'll need a handoff
    /// to actually cross the ocean.
    static var preview: FlockViewModel {
        let burnabyLeg = RouteNode(
            cityName: "Burnaby",
            latitude: 49.2488,
            longitude: -122.9805,
            carrierName: "Klaus",
            stepsContributed: 4200,
            timestamp: Date().addingTimeInterval(-86_400 * 6)
        )
        let calgaryLeg = RouteNode(
            cityName: "Calgary",
            latitude: 51.0447,
            longitude: -114.0719,
            carrierName: "Klaus",
            stepsContributed: 3100,
            timestamp: Date().addingTimeInterval(-86_400 * 3)
        )

        let letter = Letter(
            senderName: "Anton",
            recipientName: "Marta",
            messageBody: "By the time this reaches you, the leaves will have turned. Miss you.",
            isSealed: true,
            createdAt: Date().addingTimeInterval(-86_400 * 7),
            receivingCode: "KLAU-SRAM"
        )

        // Illustrative placeholder polyline (Calgary -> Gander) — a real
        // ram gets its actual road route from `RouteService`.
        let currentLegRoute: [RamCoordinate] = [
            RamCoordinate(latitude: 51.0447, longitude: -114.0719), // Calgary
            RamCoordinate(latitude: 50.4452, longitude: -104.6189), // Regina
            RamCoordinate(latitude: 49.8951, longitude: -97.1384),  // Winnipeg
            RamCoordinate(latitude: 48.3809, longitude: -89.2477),  // Thunder Bay
            RamCoordinate(latitude: 46.4917, longitude: -80.9930),  // Sudbury
            RamCoordinate(latitude: 48.9564, longitude: -54.6089),  // Gander
        ]

        let klaus = Ram(
            name: "Klaus",
            status: .walking,
            stepsWalked: 7300,
            totalStepsRequired: 15000,
            currentCity: "Calgary",
            targetCity: "Frankfurt",
            legDestinationCity: "Gander",
            routeHistory: [burnabyLeg, calgaryLeg],
            routeCoordinates: currentLegRoute,
            requiresHandoffAtLegEnd: true,
            letter: letter,
            finalDestinationCoordinate: RamCoordinate(latitude: 50.1109, longitude: 8.6821) // Frankfurt
        )

        return FlockViewModel(activeRams: [klaus], maxAllowedRams: 1)
    }
}
#endif
