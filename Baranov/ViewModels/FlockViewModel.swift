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
import UIKit
import WidgetKit

@Observable
@MainActor
final class FlockViewModel {
    /// The absolute ceiling on concurrent rams, free slot included — what
    /// "Expand the Pasture" ultimately unlocks all the way to. Matches the
    /// "Five Rams at Once" the paywall itself advertises.
    static let pastureCapacity = 5

    var activeRams: [Ram] = [] {
        didSet {
            persist()
            endFinishedLiveActivities()
        }
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
        self.selectedRamId = activeRams.first?.id
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
            if let active = self.ownRams.first(where: { $0.status == .walking }) ?? self.activeRams.first(where: { $0.status == .walking }) ?? self.activeRams.first {
                self.addStepProgress(ramId: active.id, steps: steps)
            }
        }
        if let active = self.liveActivityRam {
            self.startOrUpdateLiveActivity(for: active)
        } else {
            // Nothing in play (everything arrived, was delivered or handed on):
            // a card left over from the last launch must not linger.
            self.endAllLiveActivities()
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
    /// ActivityKit silently drops updates once its budget is spent, and a dropped
    /// update is usually the one that changes the icon. The bar and the walking
    /// clock move by themselves between pushes, so a push every 3 s is plenty.
    private let activityUpdateInterval: TimeInterval = 3
    /// The last status symbol pushed per ram. A change of status (walking, at
    /// sea, arrived...) is always pushed at once, never throttled away.
    @ObservationIgnored private var lastPushedSymbol: [UUID: String] = [:]
    /// Advances the gait frame the widget shows; bumped on every pushed update.
    @ObservationIgnored private var activityStride: [UUID: Int] = [:]
    /// When each ram's current walk began, for the self-ticking clock.
    @ObservationIgnored private var walkingSince: [UUID: Date] = [:]
    /// Recent step deltas per ram, for a live cadence (steps/second).
    @ObservationIgnored private var stepSamples: [UUID: [(date: Date, steps: Int)]] = [:]
    /// When the last steps landed. The person counts as "moving" for a few
    /// seconds after this, so the ram keeps trotting between pedometer callbacks.
    @ObservationIgnored private var lastStepAt: [UUID: Date] = [:]
    @ObservationIgnored private var lastPushedMoving: [UUID: Bool] = [:]
    /// Pushes a Live Activity update every second while a ram is walking. A
    /// Live Activity cannot animate on its own, so this is what makes the
    /// ram's gait, the step count and the bar visibly move instead of
    /// waiting for the next pedometer callback.
    @ObservationIgnored private var liveTicker: Task<Void, Never>?
    /// True between the scene going to the background and coming back. The
    /// app has no background mode, so anything pushed in this window is the
    /// last thing the card shows until a HealthKit wake or the next launch:
    /// it carries the long projection `staleDate` instead of the 30 s one.
    @ObservationIgnored private var isInBackground = false
    /// Last ride-along route check per ram, so a phone sitting in the
    /// wrong place doesn't send an MKDirections request every 30 seconds.
    @ObservationIgnored private var isCarryingGuests = false
    @ObservationIgnored private var liftAttempts: [UUID: (position: CLLocationCoordinate2D, date: Date)] = [:]
    private static let movingGrace: TimeInterval = 8

    /// The most recent SF Symbol WeatherKit gave us for each ram's live
    /// position. Refreshed best-effort, in the background, off
    /// `WeatherSnapshotService`'s own reuse cache — never awaited, never
    /// something the Live Activity waits on.
    @ObservationIgnored private var liveWeatherSymbols: [UUID: String] = [:]

    func startOrUpdateLiveActivity(for ram: Ram) {
        refreshLiveWeather(for: ram)
        var state = contentState(for: ram)
        // One Live Activity for the whole flock: the ram that is walking now (or the
        // first one). Other rams never spawn their own card.
        let primary = liveActivityRam
        if !Self.showsLiveActivity(ram) {
            // The ram reached the gate (or was delivered / handed on): the
            // journey is over, so take the card off the Lock Screen and the
            // Dynamic Island at once instead of leaving it frozen there.
            endLiveActivity(for: ram.id, immediately: true)
            if primary == nil { endAllLiveActivities() }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled, primary == nil || primary?.id == ram.id {
            if let existing = liveActivities[ram.id], existing.activityState == .active {
                let now = Date()
                let statusChanged = lastPushedSymbol[ram.id] != state.statusSymbol
                if !statusChanged, let last = lastActivityUpdate[ram.id], now.timeIntervalSince(last) < activityUpdateInterval {
                    // Throttle ActivityKit updates to avoid system limits
                } else {
                    lastActivityUpdate[ram.id] = now
                    lastPushedSymbol[ram.id] = state.statusSymbol
                    // Only a ram whose shepherd is walking right now takes steps;
                    // anything else holds its frame.
                    if ram.status == .walking, isMoving(ram.id, now: now) {
                        activityStride[ram.id, default: 0] += 1
                    }
                    state = contentState(for: ram)
                    lastPushedMoving[ram.id] = state.isMoving
                    let content = ActivityContent(state: state, staleDate: liveStaleDate(for: state, now: now))
                    Task { await existing.update(content) }
                }
            } else {
                liveActivities.removeValue(forKey: ram.id)
                // After a relaunch our in-memory map is empty but the system may still be
                // showing the old card: adopt a matching one, and end every other leftover.
                let leftovers = Activity<RamActivityAttributes>.activities
                let adopted = leftovers.first {
                    $0.attributes.ramName == ram.name && $0.attributes.toCity == ram.targetCity
                }
                for old in leftovers where old.id != adopted?.id {
                    Task { await old.end(nil, dismissalPolicy: .immediate) }
                }
                liveActivities.removeAll()
                if let adopted {
                    liveActivities[ram.id] = adopted
                    lastActivityUpdate[ram.id] = Date()
                    lastPushedSymbol[ram.id] = state.statusSymbol
                    Task { await adopted.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(30 * 60))) }
                } else {
                    let attrs = RamActivityAttributes(ramName: ram.name, fromCity: ram.currentCity, toCity: ram.targetCity)
                    do {
                        let activity = try Activity.request(
                            attributes: attrs,
                            content: .init(state: state, staleDate: Date().addingTimeInterval(30 * 60))
                        )
                        liveActivities[ram.id] = activity
                        lastActivityUpdate[ram.id] = Date()
                        lastPushedSymbol[ram.id] = state.statusSymbol
                    } catch { /* not supported or authorized */ }
                }
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
        if ram.status == .walking { ensureLiveTicker() }
    }

    // MARK: Live Activity ticker

    private func isMoving(_ id: UUID, now: Date = Date()) -> Bool {
        guard let last = lastStepAt[id] else { return false }
        return now.timeIntervalSince(last) <= Self.movingGrace
    }

    /// Records a step delta so the Live Activity can show a real cadence.
    private func noteSteps(ramId: UUID, steps: Int) {
        let now = Date()
        lastStepAt[ramId] = now
        var samples = (stepSamples[ramId] ?? []).filter { now.timeIntervalSince($0.date) <= 30 }
        samples.append((date: now, steps: steps))
        stepSamples[ramId] = samples
    }

    private func stepsPerSecond(_ id: UUID, now: Date) -> Double {
        let recent = (stepSamples[id] ?? []).filter { now.timeIntervalSince($0.date) <= 30 }
        guard let first = recent.first else { return 0 }
        let total = recent.reduce(0) { $0 + $1.steps }
        let span = max(now.timeIntervalSince(first.date), 5)
        return min(Double(total) / span, 3.5)
    }

    /// In the foreground the app pushes every few seconds, so a walking card
    /// is only trusted for 30 s. Pushed on the way into the background, the
    /// card keeps projecting toward the ETA for `backgroundProjectionWindow`,
    /// then goes stale and shows the last real numbers.
    private func liveStaleDate(for state: RamActivityAttributes.ContentState, now: Date) -> Date {
        if isInBackground { return state.backgroundStaleDate(now: now) }
        return state.isMoving == true ? now.addingTimeInterval(30) : now.addingTimeInterval(30 * 60)
    }

    private func ensureLiveTicker() {
        guard liveTicker == nil, !isInBackground else { return }
        liveTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if !self.tickLiveActivity() {
                    self.liveTicker = nil
                    return
                }
            }
        }
    }

    /// One tick. Returns `false` when there is nothing left to tick for.
    private func tickLiveActivity() -> Bool {
        guard !isInBackground else { return false }
        guard let ram = activeRams.first(where: { $0.status == .walking }),
              let activity = liveActivities[ram.id],
              activity.activityState == .active else { return false }
        let now = Date()
        if let last = lastActivityUpdate[ram.id], now.timeIntervalSince(last) < activityUpdateInterval { return true }
        let moving = isMoving(ram.id, now: now)
        // Already showing "paused" and still paused: nothing new to say.
        if !moving, lastPushedMoving[ram.id] == false { return true }
        lastActivityUpdate[ram.id] = now
        lastPushedSymbol[ram.id] = ram.status.symbolName
        if moving { activityStride[ram.id, default: 0] += 1 }
        let state = contentState(for: ram)
        lastPushedMoving[ram.id] = state.isMoving
        let content = ActivityContent(state: state, staleDate: liveStaleDate(for: state, now: now))
        Task { await activity.update(content) }
        return true
    }

    /// Whether a ram still deserves a Live Activity. Once it has reached the
    /// recipient's gate, been delivered, or been passed to another carrier,
    /// nothing on it moves any more and the card would only sit there.
    static func showsLiveActivity(_ ram: Ram) -> Bool {
        switch ram.status {
        case .arrivedAtGate, .delivered, .handedOff: return false
        case .grazing, .walking, .waitingForHandoff, .atSea: return true
        }
    }

    /// Ends every Live Activity this app has, including cards left over from
    /// a previous launch that `liveActivities` doesn't know about.
    /// Safety net for every path that flips a ram to arrived / delivered /
    /// handed on: whichever code did it, its card comes down with it.
    private func endFinishedLiveActivities() {
        guard !liveActivities.isEmpty else { return }
        for ram in activeRams where !Self.showsLiveActivity(ram) && liveActivities[ram.id] != nil {
            endLiveActivity(for: ram.id, immediately: true)
        }
    }

    private func endAllLiveActivities() {
        for activity in Activity<RamActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        liveActivities.removeAll()
        lastActivityUpdate.removeAll()
        activityStride.removeAll()
        walkingSince.removeAll()
        stepSamples.removeAll()
        lastStepAt.removeAll()
        lastPushedMoving.removeAll()
        lastPushedSymbol.removeAll()
        liveTicker?.cancel()
        liveTicker = nil
    }

    func endLiveActivity(for ramId: UUID, immediately: Bool = false) {
        guard let activity = liveActivities[ramId] else { return }
        let policy: ActivityUIDismissalPolicy = immediately ? .immediate : .after(Date().addingTimeInterval(5))
        Task { await activity.end(nil, dismissalPolicy: policy) }
        liveActivities.removeValue(forKey: ramId)
        lastActivityUpdate.removeValue(forKey: ramId)
        activityStride.removeValue(forKey: ramId)
        walkingSince.removeValue(forKey: ramId)
        stepSamples.removeValue(forKey: ramId)
        lastStepAt.removeValue(forKey: ramId)
        lastPushedMoving.removeValue(forKey: ramId)
        lastPushedSymbol.removeValue(forKey: ramId)
        if liveActivities.isEmpty {
            liveTicker?.cancel()
            liveTicker = nil
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func contentState(for ram: Ram) -> RamActivityAttributes.ContentState {
        if ram.status == .walking {
            if walkingSince[ram.id] == nil { walkingSince[ram.id] = Date() }
        } else {
            walkingSince.removeValue(forKey: ram.id)
        }
        let now = Date()
        return RamActivityAttributes.ContentState.make(
            ram: ram,
            isMoving: ram.status == .walking ? isMoving(ram.id, now: now) : nil,
            stepsPerSecond: stepsPerSecond(ram.id, now: now),
            stride: activityStride[ram.id, default: 0],
            walkingSince: walkingSince[ram.id],
            weatherSymbol: liveWeatherSymbols[ram.id],
            now: now
        )
    }

    // MARK: Background and foreground

    /// The ram the one Live Activity is about.
    private var liveActivityRam: Ram? {
        let live = activeRams.filter(Self.showsLiveActivity)
        return live.first(where: { $0.status == .walking && !$0.isGuest })
            ?? live.first(where: { $0.status == .walking })
            ?? live.first
    }

    /// The scene is going to the background and the app will be suspended
    /// within seconds. Pushes one last card that projects toward the ETA on
    /// its own, saves the step baseline for HealthKit wakes, and schedules
    /// the "almost there" notification from the same estimate.
    func sceneDidEnterBackground() {
        isInBackground = true
        liveTicker?.cancel()
        liveTicker = nil

        // The steps applied up to now are what a HealthKit wake counts on from.
        BackgroundStepSync.shared.flushBaseline()
        guard let ram = liveActivityRam, ram.status == .walking else { return }

        let state = contentState(for: ram)
        let eta = state.barEnd
        let activity = liveActivities[ram.id]
        // A few seconds of runway so the update and the notification land
        // before suspension. Not a background mode; iOS grants this to any app.
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "Live Activity handoff")
        Task {
            if let activity, activity.activityState == .active {
                lastActivityUpdate[ram.id] = Date()
                lastPushedSymbol[ram.id] = state.statusSymbol
                lastPushedMoving[ram.id] = state.isMoving
                await activity.update(ActivityContent(state: state, staleDate: state.backgroundStaleDate()))
            }
            await ArrivalEstimateNotifier.schedule(for: ram, eta: eta)
            if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
        }
    }

    /// Back on screen: the real step pipeline takes over again. Pending
    /// estimates are dropped (the real arrival announces itself) and the
    /// card gets real numbers as soon as the pedometer catches up.
    func sceneDidBecomeActive() {
        isInBackground = false
        Task { await ArrivalEstimateNotifier.cancelAll() }
        if let ram = liveActivityRam {
            // Force a push: the card may be showing a stale projection.
            lastActivityUpdate.removeValue(forKey: ram.id)
            startOrUpdateLiveActivity(for: ram)
        }
    }

    /// Best-effort, fire-and-forget: asks `WeatherSnapshotService` for a
    /// reading at the ram's current position and remembers the symbol for
    /// the next `contentState(for:)`. Costs nothing extra against the
    /// monthly WeatherKit budget beyond what stamps already spend — the
    /// service's own 5 km / 30-minute reuse cache absorbs repeat calls
    /// from a ram that hasn't moved far. Never blocks, never throws.
    private func refreshLiveWeather(for ram: Ram) {
        guard let coordinate = ram.currentCoordinate else { return }
        let ramId = ram.id
        Task { @MainActor [weak self] in
            guard let weather = await WeatherSnapshotService.snapshot(at: coordinate) else { return }
            self?.liveWeatherSymbols[ramId] = weather.symbolName
        }
    }

    /// Set by `eraseAll()`: once the person has deleted their data, this
    /// instance must never write a flock back to disk, whatever late
    /// pedometer or watch callback still holds a reference to it.
    @ObservationIgnored private var isErased = false

    /// "Delete all data & reset": takes every Live Activity off the Lock
    /// Screen, empties the flock and stops all writes. The files themselves
    /// are removed by `AppDataEraser`.
    func eraseAll() {
        isErased = true
        pendingSave?.cancel()
        pendingSave = nil
        endAllLiveActivities()
        liveWeatherSymbols.removeAll()
        liftAttempts.removeAll()
        selectedRamId = nil
        activeRams = []
        store?.clear()
    }

    private func persist() {
        guard let store, !isErased else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, !self.isErased else { return }
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
        // not go on occupying a pen the person has paid for. The same
        // goes for a ram that has reached the gate: it has left the
        // letter there for the recipient to walk over and collect, so it
        // is free to carry the next one.
        //
        // Someone else's letter (a guest) never takes a pen either: it rides
        // in the mailbag with this person's own ram.
        //
        // A delivered letter is history, and a letter that came TO this
        // person is theirs to open, not a ram they walk.
        //
        // A letter held for its recipient's gate (Code mode) keeps the pen
        // its ram will walk from.
        activeRams.filter {
            !$0.isGuest && !$0.addressedToThisPhone
                && $0.status != .handedOff && $0.status != .arrivedAtGate && $0.status != .delivered
        }.count + LetterTracker.shared.heldCount < maxAllowedRams
    }

    /// How many other people's letters one phone will carry at once. Not a
    /// paywall — just a sane bound on a mailbag.
    static let maxGuests = 5

    /// Other people's letters this phone is carrying right now.
    var guestRams: [Ram] {
        activeRams.filter { $0.isGuest && Self.isInPlay($0) }
    }

    /// This person's own rams — what the pasture pens, the ram selector
    /// and step tracking are about.
    var ownRams: [Ram] {
        activeRams.filter { !$0.isGuest }
    }

    private static func isInPlay(_ ram: Ram) -> Bool {
        switch ram.status {
        case .grazing, .walking, .waitingForHandoff, .atSea: return true
        case .handedOff, .arrivedAtGate, .delivered: return false
        }
    }

    /// Whether a letter bound for `destination` is going this person's way:
    /// its destination is near where one of their own rams is headed
    /// (`KnownCarrierDirectory.matchRadiusMeters`), or, seen from `here`,
    /// it lies in roughly the same direction. `nil` when there's nothing to
    /// compare against (no own ram out and no position).
    func isGoingMyWay(to destination: CLLocationCoordinate2D, from here: CLLocationCoordinate2D?) -> Bool? {
        let target = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let mine = ownRams.filter { Self.isInPlay($0) }.map(\.finalDestinationCoordinate)
        guard !mine.isEmpty else { return nil }

        for own in mine {
            let ownLocation = CLLocation(latitude: own.latitude, longitude: own.longitude)
            if ownLocation.distance(from: target) <= KnownCarrierDirectory.matchRadiusMeters { return true }
        }
        guard let here else { return false }
        let hereLocation = CLLocation(latitude: here.latitude, longitude: here.longitude)
        guard hereLocation.distance(from: target) > 50_000 else { return true }
        let theirs = Self.bearing(from: here, to: destination)
        return mine.contains { own in
            let ownLocation = CLLocation(latitude: own.latitude, longitude: own.longitude)
            guard hereLocation.distance(from: ownLocation) > 50_000 else { return false }
            let diff = abs(theirs - Self.bearing(from: here, to: own.clLocationCoordinate))
            return min(diff, 360 - diff) <= 40
        }
    }

    private static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Whether this ram's letter is someone else's: this phone holds no
    /// recall token for it. A letter coming back to its own sender is not
    /// a guest.
    static func isGuestLetter(_ ram: Ram) -> Bool {
        guard let letter = ram.letter else { return false }
        return !RecallTokenVault.isMine(letter.id) && !isAddressedToMe(letter)
            && !RecipientKeyring.isAddressedToMe(letter)
    }

    /// Whether this person is the letter's recipient, by the display name
    /// they carry — the same identity the arrival screen checks.
    static func isAddressedToMe(_ letter: Letter) -> Bool {
        // Any of the person's active names (name, nickname, pen name).
        NameProfile.matches(letter.recipientName)
    }

    // MARK: - Delivery receipts

    /// Whether this package is a delivery receipt: a ram whose letter has
    /// been opened, coming back to the phone that sent it.
    static func isDeliveryReceipt(_ package: RamTransitPackage) -> Bool {
        package.ram.status == .delivered
    }

    /// Applies a receipt the recipient sent back (iMessage, AirDrop): the
    /// sender's own record of the letter learns it was opened and gets the
    /// whole journey — every stamp and every carrier along the way. The
    /// sender's own copy of the letter is kept. Returns the ram's name, or
    /// `nil` when this phone didn't send that letter.
    @discardableResult
    func applyDeliveryReceipt(_ package: RamTransitPackage) -> String? {
        let incoming = package.ram
        guard let letterID = incoming.letter?.id,
              let index = activeRams.firstIndex(where: { $0.letter?.id == letterID && !$0.isGuest })
        else { return nil }
        var ram = activeRams[index]
        guard ram.status != .delivered || ram.stamps.count < incoming.stamps.count else { return ram.name }
        ram.status = .delivered
        ram.stamps = incoming.stamps
        ram.routeHistory = incoming.routeHistory
        ram.recallRequestedAt = nil
        activeRams[index] = ram
        endLiveActivity(for: ram.id)
        return ram.name
    }

    /// Sender side: the relay says the recipient broke the seal. The ram's
    /// journey is complete: delivered, with a last passport stamp. Returns
    /// the ram's name, or `nil` when this phone has no such letter.
    @discardableResult
    func markOpenedByRecipient(letterID: UUID, recipientName: String) -> String? {
        guard let index = activeRams.firstIndex(where: { $0.letter?.id == letterID && !$0.isGuest }) else { return nil }
        var ram = activeRams[index]
        guard ram.status != .delivered else { return ram.name }
        let name = recipientName.trimmingCharacters(in: .whitespacesAndNewlines)
        appendStamp(
            to: &ram,
            placeName: String(localized: "Opened by \(name.isEmpty ? String(localized: "the recipient", bundle: .appLanguage, locale: .appLanguage) : name)", bundle: .appLanguage, locale: .appLanguage),
            kind: .arrival,
            coordinate: ram.gateCoordinate
        )
        ram.status = .delivered
        ram.recallRequestedAt = nil
        activeRams[index] = ram
        endLiveActivity(for: ram.id)
        return ram.name
    }

    // MARK: - More than one letter per ram

    /// An own ram already heading to (within 25 km of) this destination,
    /// which can carry another letter in its mailbag instead of a new ram
    /// taking a pen.
    func ramHeading(to destination: CLLocationCoordinate2D) -> Ram? {
        let target = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        return ownRams.first { ram in
            guard ram.status == .grazing || ram.status == .walking
                    || ram.status == .waitingForHandoff || ram.status == .atSea else { return false }
            // A ram carries at most three letters besides its own.
            guard ram.passengerLetters.count < RamAgeStage.adult.maxPassengerLetters else { return false }
            let goal = CLLocation(latitude: ram.finalDestinationCoordinate.latitude,
                                  longitude: ram.finalDestinationCoordinate.longitude)
            return goal.distance(from: target) <= 25_000
        }
    }

    /// Sends a letter along with a ram that is already going there.
    func bundle(_ letter: Letter, into ramId: UUID) {
        var letter = letter
        if letter.recallTokenHash == nil {
            letter.recallTokenHash = RecallTokenVault.issue(for: letter.id)
        }
        addPassengerLetter(letter, to: ramId)
    }

    /// Whether importing this AirDropped package would be admitted right
    /// now: a ram already tracked locally can always be re-imported
    /// (idempotent, e.g. resuming a leg after a handoff), while a
    /// brand-new ram is only admitted while under `maxAllowedRams`.
    /// A sealed letter that already stands at its gate but whose code this
    /// phone neither holds nor can open (no key sealed to this phone's
    /// profile, no code stored) can never be read here, so it is declined
    /// rather than left in the mailbag as a letter nobody can open. Letters
    /// still on the road are never declined: a carrier doesn't need the code.
    /// Already-tracked rams and relay deliveries (which store the code
    /// first) are not affected.
    func shouldDecline(_ package: RamTransitPackage) -> Bool {
        let ram = package.ram
        guard ram.status == .arrivedAtGate,
              !activeRams.contains(where: { $0.id == ram.id }),
              let letter = ram.letter,
              letter.isEncrypted, letter.isSealed
        else { return false }
        if SealKeyVault.code(for: letter.id) != nil { return false }
        return !RecipientKeyring.adoptAll(in: ram)
    }

    func canImport(_ package: RamTransitPackage) -> Bool {
        if activeRams.contains(where: { $0.id == package.ram.id }) { return true }
        // A letter delivered at the gate takes no pen: it's here to be opened.
        if package.ram.status == .arrivedAtGate { return true }
        if Self.isGuestLetter(package.ram) { return guestRams.count < Self.maxGuests }
        return hasFreeRamSlot
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

        if !ram.isGuest {
            noteSteps(ramId: ramId, steps: steps)
            startOrUpdateLiveActivity(for: ram)
            if ram.status == .walking {
                // What a HealthKit wake counts on from, if the app is suspended next.
                BackgroundStepSync.shared.recordBaseline(ramId: ram.id, stepsWalked: ram.stepsWalked)
            } else {
                BackgroundStepSync.shared.clearBaseline()
            }
        }

        // Guests ride in the mailbag of the ram being walked: the same steps
        // carry them along their own roads. (Guarded so the guests' own
        // updates don't fan out again.)
        guard !isCarryingGuests else { return }
        isCarryingGuests = true
        defer { isCarryingGuests = false }
        for guest in guestRams where guest.id != ramId && (guest.status == .grazing || guest.status == .walking) {
            addStepProgress(ramId: guest.id, steps: steps)
        }
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

        let stamp = JourneyStamp(
            placeName: trimmed,
            kind: kind,
            latitude: coordinate?.latitude ?? 0,
            longitude: coordinate?.longitude ?? 0,
            stepsAtStamp: ram.journeyStepsSoFar,
            carrierName: Self.currentCarrierName(fallback: ram.name)
        )
        ram.stamps.append(stamp)

        // Best-effort and fully offline-safe: the stamp exists immediately,
        // and the sky is written onto it only if the lookup succeeds.
        if let coordinate {
            let stampId = stamp.id
            Task { [weak self] in
                guard let weather = await WeatherSnapshotService.snapshot(at: coordinate) else { return }
                self?.attachWeather(weather, toStamp: stampId)
            }
        }
    }

    /// Writes a late-arriving weather reading onto the stamp it belongs to,
    /// wherever that stamp lives now.
    private func attachWeather(_ weather: StampWeather, toStamp stampId: UUID) {
        for ramIndex in activeRams.indices {
            guard let stampIndex = activeRams[ramIndex].stamps.firstIndex(where: { $0.id == stampId }) else { continue }
            activeRams[ramIndex].stamps[stampIndex].weather = weather
            return
        }
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
    /// `currentCoordinate` is only consulted when the letter carries a
    /// Geo-Lock (paid) — pass the device's best current fix so an
    /// `.outsideGeofence` throw actually reflects reality; omitting it on
    /// a geofenced letter fails closed rather than skipping the check.
    func openDeliveredLetter(ramId: UUID, receivingCode: String, currentCoordinate: CLLocationCoordinate2D? = nil) throws {
        guard let index = activeRams.firstIndex(where: { $0.id == ramId }) else { return }
        var ram = activeRams[index]
        guard ram.status == .arrivedAtGate, var letter = ram.letter else { return }
        try letter.open(withReceivingCode: receivingCode, currentCoordinate: currentCoordinate)
        ram.letter = letter
        ram.status = .delivered
        // The last page of the passport, and what the delivery receipt
        // carries home to the sender.
        appendStamp(
            to: &ram,
            placeName: String(localized: "Opened by \(Self.currentCarrierName(fallback: letter.recipientName))", bundle: .appLanguage, locale: .appLanguage),
            kind: .arrival,
            coordinate: currentCoordinate ?? ram.currentCoordinate
        )
        activeRams[index] = ram
    }

    /// Opens one of the passenger letters riding on a ram that has reached
    /// the gate, for a recipient standing there with its code. See
    /// `openDeliveredLetter` for what `currentCoordinate` is for.
    func openPassengerLetter(ramId: UUID, letterId: UUID, receivingCode: String, currentCoordinate: CLLocationCoordinate2D? = nil) throws {
        guard let index = activeRams.firstIndex(where: { $0.id == ramId }),
              let letterIndex = activeRams[index].passengerLetters.firstIndex(where: { $0.id == letterId })
        else { return }
        var letter = activeRams[index].passengerLetters[letterIndex]
        try letter.open(withReceivingCode: receivingCode, currentCoordinate: currentCoordinate)
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
        dispatched.isGuest = false
        // The sender's proof, for "Take it back" once it's handed on.
        if var letter = dispatched.letter, letter.recallTokenHash == nil {
            letter.recallTokenHash = RecallTokenVault.issue(for: letter.id)
            dispatched.letter = letter
        }
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
        // Someone else's letter is never ours to withdraw — only its
        // sender can take it back (see `RecallService`).
        guard !ram.isGuest else { return false }
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
    /// A handoff changes who carries the ram, never where it is. Two phones
    /// that shake are in the same spot, so the receiver's position says
    /// nothing about the letter's journey: a ram already across the
    /// Atlantic must not snap back to North America because the friend who
    /// took it lives there. The ram keeps its place on the map, its road,
    /// its steps and any packet booking; the receiver's steps walk it on
    /// from there.
    ///
    /// `receivedAt` only starts the new carrier's custody. If that phone
    /// later turns up across the water, `rideAlong(carrierAt:)` lets the
    /// ram go ashore with it.
    func importPackage(
        _ package: RamTransitPackage,
        receivedAt coordinate: CLLocationCoordinate2D? = nil,
        asRecipient: Bool = false,
        now: Date = Date()
    ) async {
        var importedRam = package.ram
        let alreadyTracked = activeRams.contains { $0.id == importedRam.id }

        guard canImport(package) else { return }
        // Delivered by the post office the code is already stored, so this
        // only ever stops a letter handed over with no way to open it.
        if !asRecipient, shouldDecline(package) { return }

        // A key sealed to this phone's profile opens here and nowhere else:
        // keep the code for the seal, and the letter is this person's.
        let keyedToMe = RecipientKeyring.adoptAll(in: importedRam)

        // Someone else's letter rides in the mailbag rather than taking a pen
        // or the ram selector; the sender's own letter coming back is theirs.
        importedRam.isGuest = Self.isGuestLetter(importedRam)
        importedRam.recallRequestedAt = nil
        if asRecipient || (keyedToMe && importedRam.status == .arrivedAtGate) {
            // Delivered by the post office, or handed over at the gate with a
            // key only this phone could open: here to be opened, right away.
            importedRam.isGuest = false
            importedRam.addressedToThisPhone = true
            if importedRam.letter?.relayTicket != nil { importedRam.letter?.relayTicket = nil }
        }

        switch importedRam.status {
        case .handedOff:
            // Handed away and then given back: livestock again.
            importedRam.status = .grazing
        case .grazing, .walking, .waitingForHandoff, .atSea, .arrivedAtGate, .delivered:
            break
        }

        importedRam.custodyOrigin = coordinate.map { RamCoordinate($0) }
        importedRam.custodySince = coordinate == nil ? nil : now
        liftAttempts[importedRam.id] = nil

        if let index = activeRams.firstIndex(where: { $0.id == importedRam.id }) {
            activeRams[index] = importedRam
        } else {
            activeRams.append(importedRam)
        }

        // A guest never takes the selected ram's place.
        if !importedRam.isGuest || !ownRams.contains(where: { Self.isInPlay($0) }) {
            selectedRamId = importedRam.id
        }
    }

    // MARK: - Taking a letter back

    /// Whether the sender can ask for this ram's letter back: it was handed
    /// on from this phone, and this phone holds the letter's recall token.
    func canTakeBack(_ ram: Ram) -> Bool {
        guard ram.status == .handedOff, !ram.isGuest, !ram.wasDeliveredInPerson,
              let letter = ram.letter, letter.recallTokenHash != nil else { return false }
        return RecallTokenVault.isMine(letter.id)
    }

    /// Sender side: the recall request reached the relay.
    func markRecallRequested(ramId: UUID, at date: Date = Date()) {
        guard let index = activeRams.firstIndex(where: { $0.id == ramId }) else { return }
        activeRams[index].recallRequestedAt = date
    }

    /// Sender side: the carrier gave the letter up. The ram comes home and
    /// walks again from where it was handed on — to the quay if it was
    /// waiting there, otherwise back to grazing.
    @discardableResult
    func restoreRecalled(letterID: UUID) -> String? {
        guard let index = activeRams.firstIndex(where: {
            $0.letter?.id == letterID && $0.status == .handedOff && !$0.isGuest
        }) else { return nil }
        var ram = activeRams[index]
        let atQuay = ram.requiresHandoffAtLegEnd && ram.stepsWalked >= ram.totalStepsRequired
        ram.status = atQuay ? .waitingForHandoff : .grazing
        ram.recallRequestedAt = nil
        ram.custodyOrigin = nil
        ram.custodySince = nil
        appendStamp(
            to: &ram,
            placeName: String(localized: "Came back home", bundle: .appLanguage, locale: .appLanguage),
            kind: .arrival,
            coordinate: ram.currentCoordinate
        )
        activeRams[index] = ram
        return ram.name
    }

    /// Carrier side: the sender asked for their letter back and the recall's
    /// hash matches the one inside the letter. The guest leaves this
    /// mailbag. Returns the ram's name, or `nil` if nothing was released.
    @discardableResult
    func releaseRecalled(letterID: UUID, tokenHash: String) -> String? {
        guard let index = activeRams.firstIndex(where: {
            $0.isGuest && $0.letter?.id == letterID && Self.isInPlay($0)
        }),
        let expected = activeRams[index].letter?.recallTokenHash,
        expected.lowercased() == tokenHash.lowercased()
        else { return nil }

        let ram = activeRams.remove(at: index)
        endLiveActivity(for: ram.id)
        liftAttempts[ram.id] = nil
        if selectedRamId == ram.id {
            selectedRamId = ownRams.first?.id ?? activeRams.first?.id
        }
        return ram.name
    }

    // MARK: - Riding along

    /// How far the carrying phone must have moved since taking custody
    /// before a ride-along is even considered. Keeps a phone that simply
    /// stayed home from ever lifting a ram.
    static let rideAlongMinimumTravelMeters: CLLocationDistance = 300_000

    /// The ram must end up at least this much closer to its destination.
    static let rideAlongMinimumGainMeters: CLLocationDistance = 100_000

    /// Faster than any airliner means the location isn't real.
    static let rideAlongMaximumSpeed: CLLocationSpeed = 300

    /// A failed route check is not repeated until the phone has moved this
    /// far again, or this much time has passed.
    private static let rideAlongRetryDistance: CLLocationDistance = 50_000
    private static let rideAlongRetryInterval: TimeInterval = 30 * 60

    /// Lets rams with water ahead of them ride along with the phone
    /// carrying them.
    ///
    /// Land is walked, water is crossed by the packet or in someone's
    /// pocket. The pocket half is decided here, not at the moment of a
    /// handoff: once the carrying phone has actually travelled (a flight,
    /// a ferry) and turned up somewhere a road reaches the destination
    /// from, and that is clearly closer than where the ram is, the ram
    /// goes ashore there, any packet booking is cancelled, and the new leg
    /// starts from the carrier's own position. It only ever moves a ram
    /// forward.
    ///
    /// Called with the phone's position from the app's 30-second loop and
    /// whenever the app becomes active.
    func rideAlong(carrierAt position: CLLocationCoordinate2D, now: Date = Date()) async {
        let here = CLLocation(latitude: position.latitude, longitude: position.longitude)

        // First sight of a ram with no custody on record (sent from this
        // phone, or from an older build): custody starts here and now.
        for index in activeRams.indices where activeRams[index].custodyOrigin == nil {
            guard activeRams[index].hasWaterAhead else { continue }
            activeRams[index].custodyOrigin = RamCoordinate(position)
            activeRams[index].custodySince = now
        }

        let candidates = activeRams.filter { ram in
            guard ram.hasWaterAhead,
                  let origin = ram.custodyOrigin,
                  let since = ram.custodySince,
                  let ramPosition = ram.currentCoordinate
            else { return false }

            let start = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            let travelled = here.distance(from: start)
            guard travelled >= Self.rideAlongMinimumTravelMeters else { return false }

            let elapsed = max(now.timeIntervalSince(since), 1)
            guard travelled / elapsed <= Self.rideAlongMaximumSpeed else { return false }

            let destination = CLLocation(
                latitude: ram.finalDestinationCoordinate.latitude,
                longitude: ram.finalDestinationCoordinate.longitude
            )
            let ramLocation = CLLocation(latitude: ramPosition.latitude, longitude: ramPosition.longitude)
            let gain = ramLocation.distance(from: destination) - here.distance(from: destination)
            guard gain >= Self.rideAlongMinimumGainMeters else { return false }

            if let last = liftAttempts[ram.id],
               now.timeIntervalSince(last.date) < Self.rideAlongRetryInterval,
               here.distance(from: CLLocation(latitude: last.position.latitude, longitude: last.position.longitude)) < Self.rideAlongRetryDistance {
                return false
            }
            return true
        }

        for ram in candidates {
            liftAttempts[ram.id] = (position, now)

            // "Across the water" means a road now reaches the destination.
            // Landing in Iceland on the way to Berlin doesn't count.
            guard let leg = try? await RouteService.drivingRoute(
                from: position,
                to: ram.finalDestinationCoordinate.clLocationCoordinate
            ) else { continue }

            // Name the shore for the passport; offline, the stamp still says
            // who carried it and the leg still starts in the right place.
            let geocoded = try? await CLGeocoder().reverseGeocodeLocation(here, preferredLocale: .appLanguage)
            let shoreName = geocoded?.first?.locality ?? geocoded?.first?.name
                ?? String(localized: "Across the water", bundle: .appLanguage, locale: .appLanguage)

            // Re-find by id: steps or an import may have reshaped the flock
            // while those requests were in flight.
            guard let index = activeRams.firstIndex(where: { $0.id == ram.id }),
                  activeRams[index].hasWaterAhead
            else { continue }

            var updated = activeRams[index]
            let carrier = Self.currentCarrierName(fallback: updated.name)

            if updated.stepsWalked > 0 {
                let point = updated.currentCoordinate
                updated.routeHistory.append(RouteNode(
                    cityName: updated.currentCity,
                    latitude: point?.latitude ?? 0,
                    longitude: point?.longitude ?? 0,
                    carrierName: updated.name,
                    stepsContributed: updated.stepsWalked
                ))
            }
            updated.routeHistory.append(RouteNode(
                cityName: shoreName,
                latitude: position.latitude,
                longitude: position.longitude,
                carrierName: carrier,
                stepsContributed: 0
            ))
            appendStamp(
                to: &updated,
                placeName: String(localized: "Crossed with \(carrier)", bundle: .appLanguage, locale: .appLanguage),
                kind: .water,
                coordinate: position
            )

            updated.voyage = nil
            updated.currentCity = shoreName
            updated.routeCoordinates = leg.coordinates
            updated.totalStepsRequired = leg.distanceMeters
            updated.stepsWalked = 0
            updated.legDestinationCity = updated.targetCity
            updated.requiresHandoffAtLegEnd = false
            updated.status = leg.distanceMeters <= 25 ? .arrivedAtGate : .grazing
            updated.custodyOrigin = RamCoordinate(position)
            updated.custodySince = now

            activeRams[index] = updated
            liftAttempts[ram.id] = nil
            startOrUpdateLiveActivity(for: updated)
        }
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
        guard ram.status != .delivered, ram.status != .handedOff else { return }

        let recipient = (carrierName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if ram.status == .arrivedAtGate {
            // Handed over at the gate: that's a delivery, in person.
            appendStamp(
                to: &ram,
                placeName: recipient.isEmpty
                    ? String(localized: "Delivered in person", bundle: .appLanguage, locale: .appLanguage)
                    : String(localized: "Delivered to \(recipient)", bundle: .appLanguage, locale: .appLanguage),
                kind: .arrival,
                coordinate: ram.currentCoordinate
            )
        } else {
            appendStamp(
                to: &ram,
                placeName: recipient.isEmpty ? "Handed on" : "Handed to \(recipient)",
                kind: .handoff,
                coordinate: ram.currentCoordinate
            )
        }
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
                carrierName: String(localized: "The packet", bundle: .appLanguage, locale: .appLanguage),
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

}

// Preview fixtures: intentionally not #if DEBUG so #Preview blocks compile in Release/Archive builds.
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

        var klaus = Ram(
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
        klaus.stamps = [
            JourneyStamp(placeName: "Burnaby", kind: .setOut, latitude: 49.2488, longitude: -122.9805, stepsAtStamp: 0, carrierName: "Anton", timestamp: Date().addingTimeInterval(-86_400 * 7)),
            JourneyStamp(placeName: "Calgary", kind: .town, latitude: 51.0447, longitude: -114.0719, stepsAtStamp: 4200, carrierName: "Anton", timestamp: Date().addingTimeInterval(-86_400 * 4)),
            JourneyStamp(placeName: "Thunder Bay", kind: .landmark, latitude: 48.3809, longitude: -89.2477, stepsAtStamp: 7300, carrierName: "Anton", timestamp: Date().addingTimeInterval(-86_400 * 1))
        ]

        let model = FlockViewModel(activeRams: [klaus], maxAllowedRams: 1)
        model.selectedRamId = klaus.id
        return model
    }
}
