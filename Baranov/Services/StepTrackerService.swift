//
//  StepTrackerService.swift
//  Baranov
//
//  Wraps CoreMotion's CMPedometer and HealthKit's step count to drive
//  overland travel: 1 recorded step advances a ram 1 meter toward its
//  destination. All published state is MainActor-isolated so views can
//  bind to it directly; callbacks from CoreMotion/HealthKit fire on
//  private queues and are re-dispatched onto the main actor before
//  touching any state.
//
//  Why both sources: `CMPedometer` only counts motion sensed by the
//  iPhone's own coprocessor. Someone wearing an Apple Watch but not
//  carrying their phone (left on a desk, in a bag, etc.) can walk real
//  steps that CMPedometer never sees, which is exactly what made the ram
//  "not move" even while genuinely walking. HealthKit's cumulative step
//  count merges every source that writes to Health — iPhone *and* Apple
//  Watch — and de-duplicates overlapping samples the same way the Health
//  app's own daily total does, so it's the authoritative count whenever
//  it's available and authorized. CMPedometer stays wired up underneath
//  as an immediate, no-permission-round-trip fallback (and keeps working
//  for anyone who denies HealthKit access).
//

import CoreMotion
import Foundation
import HealthKit
import Observation

@Observable
@MainActor
final class StepTrackerService {

    /// Whether this device supports step counting at all via CMPedometer.
    /// `false` on the simulator's default configuration and on hardware
    /// without the required motion coprocessor. Even when this is `false`,
    /// HealthKit (Apple Watch data included) may still be usable.
    private(set) var isAvailable: Bool

    /// Whether an active tracking session is currently running.
    private(set) var isTracking: Bool = false

    /// The most recent step count reported for the current tracking session.
    private(set) var liveStepCount: Int = 0

    /// Live steps recorded since local midnight, independent of whether a
    /// ram is actually being tracked — a small always-on "today" readout,
    /// separate from `liveStepCount` (which is scoped to one ram's journey
    /// and resets every time a new leg starts tracking).
    private(set) var liveStepsToday: Int = 0

    /// Whether the always-on "steps today" query is currently running.
    private(set) var isTrackingToday: Bool = false

    /// Whether HealthKit's merged, deduplicated total (which folds in
    /// Apple Watch steps) is authorized and being folded into the count
    /// alongside `CMPedometer`.
    private(set) var isUsingHealthKit: Bool = false

    /// When `liveStepCount` last actually went up — the signal the map
    /// uses to tell "the sender is walking right now" from "a ram is
    /// mid-journey but its shepherd is sitting down". `nil` until the
    /// first step of the current session lands.
    private(set) var lastStepIncreaseAt: Date?

    /// Most recent observed cadence in steps per second, from the size
    /// and spacing of consecutive increases. Normalized by callers into
    /// `RamMotionState.moving(speed:)`.
    private(set) var recentCadence: Double = 0

    /// How long after the last increase the sender still counts as
    /// moving. `CMPedometer` reports every ~2–3 s while walking, so this
    /// comfortably bridges normal reporting gaps without leaving the ram
    /// galloping long after its shepherd stopped.
    static let movingGracePeriod: TimeInterval = 8

    /// Whether steps have landed recently enough that the sender should
    /// be treated as actively walking (see `movingGracePeriod`).
    var isSenderMoving: Bool {
        guard let lastStepIncreaseAt else { return false }
        return Date().timeIntervalSince(lastStepIncreaseAt) < Self.movingGracePeriod
    }

    /// Per-source cumulative counts for the current journey session,
    /// merged by `mergeJourneyCount()`.
    @ObservationIgnored private var pedometerJourneySteps = 0
    @ObservationIgnored private var healthKitJourneySteps = 0
    @ObservationIgnored private var pedometerTodaySteps = 0
    @ObservationIgnored private var healthKitTodaySteps = 0

    private let pedometer: CMPedometer

    /// A second, independent `CMPedometer` instance for `liveStepsToday` —
    /// CoreMotion only supports one active `startUpdates` query per
    /// pedometer instance, and this one runs continuously all day
    /// regardless of `pedometer`'s own start/stop cycle as rams begin and
    /// finish their journeys.
    private let todayPedometer: CMPedometer

    private let healthStore: HKHealthStore?
    private let stepType = HKQuantityType(.stepCount)

    /// Whether any step source at all is usable on this device — either
    /// CMPedometer's motion coprocessor or HealthKit. Views use this (rather
    /// than `isAvailable` alone) to decide whether to show step UI at all,
    /// since a device without a motion coprocessor can still have HealthKit
    /// data from a paired Apple Watch.
    var hasStepSource: Bool { isAvailable || healthStore != nil }

    private var updateHandler: (@Sendable (Int) -> Void)?
    private var journeyObserverQuery: HKObserverQuery?
    private var todayObserverQuery: HKObserverQuery?
    private var journeyStartDate: Date?
    /// Bumped on every start and stop of journey tracking. Pedometer and
    /// HealthKit callbacks capture the value they were started under and
    /// drop themselves if it has moved on — otherwise a late callback from
    /// the *previous* ram's session (carrying its step total) could land in
    /// the new session and teleport the freshly dispatched ram ahead.
    @ObservationIgnored private var trackingSession = 0
    private var todayStartDate: Date?

    init(pedometer: CMPedometer = CMPedometer(), todayPedometer: CMPedometer = CMPedometer()) {
        self.pedometer = pedometer
        self.todayPedometer = todayPedometer
        #if DEBUG
        if CommandLine.arguments.contains("-demoMode") {
            self.isAvailable = false
            self.healthStore = nil
            return
        }
        #endif
        self.isAvailable = CMPedometer.isStepCountingAvailable()
        self.healthStore = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    }

    /// Begins live step updates from `date` forward. The `updateHandler` is
    /// invoked on the main actor with the cumulative step count for this
    /// tracking session every time new data is reported.
    ///
    /// Calling this while already tracking, or when no step source is
    /// available on this device, is a no-op — travel simply does not
    /// advance rather than crashing the app.
    func startTracking(from date: Date, updateHandler: @escaping @Sendable (Int) -> Void) {
        guard isAvailable || healthStore != nil else {
            isTracking = false
            return
        }
        guard !isTracking else { return }

        trackingSession += 1
        let session = trackingSession
        self.updateHandler = updateHandler
        self.journeyStartDate = date
        liveStepCount = 0
        pedometerJourneySteps = 0
        healthKitJourneySteps = 0
        lastStepIncreaseAt = nil
        recentCadence = 0
        isTracking = true

        if isAvailable {
            pedometer.startUpdates(from: date) { [weak self] data, error in
                guard let self else { return }
                Task { @MainActor in
                    guard self.trackingSession == session else { return }
                    self.handlePedometerUpdate(data: data, error: error)
                }
            }
        }

        requestHealthAuthorizationIfNeeded { [weak self] granted in
            guard let self, granted, self.isTracking, self.trackingSession == session else { return }
            self.isUsingHealthKit = true
            self.startHealthObserving(from: date, session: session)
        }
    }

    /// Stops any active tracking (CMPedometer and/or HealthKit observation).
    /// Safe to call even when tracking has not started.
    func stopTracking() {
        trackingSession += 1
        pedometer.stopUpdates()
        if let query = journeyObserverQuery, let healthStore {
            healthStore.stop(query)
        }
        journeyObserverQuery = nil
        journeyStartDate = nil
        isTracking = false
        lastStepIncreaseAt = nil
        recentCadence = 0
        updateHandler = nil
    }

    // MARK: - Merging sources

    /// Folds the two per-source totals into one monotonically rising
    /// live count and notes when it rose (and how fast) so the UI can
    /// react to real-time walking.
    private func mergeJourneyCount() {
        let merged = max(pedometerJourneySteps, healthKitJourneySteps)
        guard merged > liveStepCount else { return }

        let now = Date()
        let delta = merged - liveStepCount
        if let last = lastStepIncreaseAt {
            let interval = max(0.5, now.timeIntervalSince(last))
            // HealthKit can land a minutes-old batch in one go; cap so
            // one big catch-up doesn't read as a sprint.
            recentCadence = min(3, Double(delta) / interval)
        } else {
            recentCadence = min(3, Double(delta) / 2.5)
        }
        lastStepIncreaseAt = now
        liveStepCount = merged
        updateHandler?(merged)
    }

    private func mergeTodayCount() {
        let merged = max(pedometerTodaySteps, healthKitTodaySteps)
        if merged > liveStepsToday {
            liveStepsToday = merged
        }
    }

    /// Begins the always-on "steps today" query, from local midnight
    /// forward. Idempotent (a no-op if already running) so a caller can
    /// invoke it every time the relevant view appears without worrying
    /// about double-starting it, and — unlike `startTracking`/
    /// `stopTracking` — it is never tied to any single ram's journey, so
    /// it keeps counting across the whole day regardless of what's
    /// currently being tracked.
    func startTrackingToday() {
        guard (isAvailable || healthStore != nil), !isTrackingToday else { return }

        isTrackingToday = true
        let startOfDay = Calendar.current.startOfDay(for: Date())
        todayStartDate = startOfDay
        pedometerTodaySteps = 0
        healthKitTodaySteps = 0

        if isAvailable {
            todayPedometer.startUpdates(from: startOfDay) { [weak self] data, error in
                guard let self else { return }
                Task { @MainActor in
                    self.handleTodayPedometerUpdate(data: data, error: error)
                }
            }
        }

        requestHealthAuthorizationIfNeeded { [weak self] granted in
            guard let self, granted, self.isTrackingToday else { return }
            self.isUsingHealthKit = true
            self.startHealthTodayObserving(from: startOfDay)
        }
    }

    // MARK: - CMPedometer (iPhone-only; immediate fallback)

    private func handlePedometerUpdate(data: CMPedometerData?, error: Error?) {
        guard isTracking else { return }

        if error != nil {
            // CoreMotion surfaces transient errors (e.g. brief motion
            // coprocessor unavailability) without ending the query. Offline-
            // first resilience means we simply wait for the next callback
            // rather than tearing down tracking.
            return
        }

        guard let data else { return }
        // The pedometer is the real-time source — it keeps driving the
        // count even once HealthKit is authorized; HealthKit only ever
        // lifts it higher (see the header note on why).
        pedometerJourneySteps = data.numberOfSteps.intValue
        mergeJourneyCount()
    }

    private func handleTodayPedometerUpdate(data: CMPedometerData?, error: Error?) {
        guard isTrackingToday else { return }

        if error != nil {
            // Same offline-first stance as the main tracker: a transient
            // CoreMotion error just waits for the next callback rather
            // than tearing anything down.
            return
        }

        guard let data else { return }
        pedometerTodaySteps = data.numberOfSteps.intValue
        mergeTodayCount()
    }

    // MARK: - HealthKit (merges Apple Watch + iPhone, deduplicated)

    /// Resolves quickly without a permission prompt when authorization was
    /// already granted or already denied in a previous session; only shows
    /// the system sheet the first time.
    private func requestHealthAuthorizationIfNeeded(completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard let healthStore else {
            completion(false)
            return
        }
        healthStore.requestAuthorization(toShare: [], read: [stepType]) { success, _ in
            Task { @MainActor in
                completion(success)
            }
        }
    }

    /// Runs an initial cumulative-sum fetch, then re-fetches every time
    /// HealthKit reports new step data for this window (e.g. once the
    /// paired Apple Watch syncs a batch of steps to Health).
    private func startHealthObserving(from date: Date, session: Int) {
        guard let healthStore else { return }

        refreshHealthKitSteps(since: date) { [weak self] steps in
            guard let self, self.isTracking, self.isUsingHealthKit, self.trackingSession == session else { return }
            self.healthKitJourneySteps = steps
            self.mergeJourneyCount()
        }

        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completionHandler, error in
            defer { completionHandler() }
            guard let self, error == nil else { return }
            Task { @MainActor in
                guard self.isTracking, self.isUsingHealthKit, self.trackingSession == session,
                      let start = self.journeyStartDate else { return }
                self.refreshHealthKitSteps(since: start) { steps in
                    guard self.trackingSession == session else { return }
                    self.healthKitJourneySteps = steps
                    self.mergeJourneyCount()
                }
            }
        }
        healthStore.execute(query)
        journeyObserverQuery = query
    }

    private func startHealthTodayObserving(from date: Date) {
        guard let healthStore else { return }

        refreshHealthKitSteps(since: date) { [weak self] steps in
            guard let self, self.isTrackingToday, self.isUsingHealthKit else { return }
            self.healthKitTodaySteps = steps
            self.mergeTodayCount()
        }

        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completionHandler, error in
            defer { completionHandler() }
            guard let self, error == nil else { return }
            Task { @MainActor in
                guard self.isTrackingToday, self.isUsingHealthKit, let start = self.todayStartDate else { return }
                self.refreshHealthKitSteps(since: start) { steps in
                    self.healthKitTodaySteps = steps
                    self.mergeTodayCount()
                }
            }
        }
        healthStore.execute(query)
        todayObserverQuery = query
    }

    /// One-shot cumulative step total from `date` to now. HealthKit's
    /// `.cumulativeSum` statistics query returns the same deduplicated
    /// total the Health app itself shows when a step is logged by more
    /// than one source (e.g. both iPhone and Apple Watch), so this is not
    /// simply "iPhone steps + Watch steps" double-counted.
    private func refreshHealthKitSteps(since date: Date, completion: @escaping @MainActor @Sendable (Int) -> Void) {
        guard let healthStore else { return }
        let predicate = HKQuery.predicateForSamples(withStart: date, end: nil, options: .strictStartDate)
        let query = HKStatisticsQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, statistics, error in
            guard error == nil else { return }
            let total = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            Task { @MainActor in
                completion(Int(total))
            }
        }
        healthStore.execute(query)
    }
}
