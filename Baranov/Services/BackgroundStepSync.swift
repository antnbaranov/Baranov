//
//  BackgroundStepSync.swift
//  Baranov
//
//  Keeps the Live Activity and the arrival notification honest while the
//  app is suspended, without any background location.
//
//  How it works:
//
//  - The step count never depends on the app running. The motion
//    coprocessor keeps counting, and when the app comes back the journey's
//    `CMPedometer` session delivers everything walked in the meantime. If
//    iOS terminated the suspended app, the first session after launch
//    starts from the saved baseline (`consumeLaunchResumePoint`), so those
//    steps still count (up to the pedometer's seven days of history).
//  - While a ram is walking, HealthKit background delivery for step count
//    is on. When iOS wakes the app with new step samples (for step count
//    that is at most about hourly), `catchUp()` counts the steps walked
//    since the last real update (`Baseline`), pushes the caught-up numbers
//    and a fresh estimate to the Live Activity, and reschedules the
//    arrival notification.
//  - A wake only *shows* the caught-up count. It never writes it to the
//    flock: the foreground pedometer session commits those same steps when
//    the app returns, so committing them here would count them twice.
//
//  Everything is best-effort. A denied Health permission, a missing
//  pedometer or an unreadable flock file means "no update", never a crash.
//

import ActivityKit
import CoreMotion
import Foundation
import HealthKit
import os
import UIKit
import UserNotifications

@MainActor
final class BackgroundStepSync {
    static let shared = BackgroundStepSync()

    /// The last real step count applied to the walking ram, and when.
    struct Baseline: Codable, Sendable {
        var ramId: UUID
        var stepsWalked: Int
        var at: Date
    }

    private static let baselineKey = "com.baranov.walkBaseline"
    nonisolated private static let logger = Logger(subsystem: "com.baranov", category: "BackgroundStepSync")
    /// `CMPedometer` keeps seven days of history; older baselines can't be caught up.
    private static let maximumBaselineAge: TimeInterval = 7 * 86_400
    /// Window used to judge whether the person is walking at wake time.
    private static let recentPaceWindow: TimeInterval = 10 * 60
    /// Baselines are written at most this often while steps stream in.
    private static let baselineWriteInterval: TimeInterval = 10

    private let healthStore: HKHealthStore? = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    private let stepType = HKQuantityType(.stepCount)
    private var observer: HKObserverQuery?
    /// `nil` until the first `setWalking`, so the first call always applies
    /// (a previous run may have left delivery on).
    private var deliveryEnabled: Bool?
    private var lastBaselineWrite: Date = .distantPast
    /// The newest baseline, written to disk on the throttle or on `flushBaseline()`.
    private var latestBaseline: Baseline?
    private var isCatchingUp = false
    private var hasOfferedResumePoint = false

    private init() {}

    // MARK: - Launch

    /// Registers the step observer. Must run in
    /// `application(_:didFinishLaunchingWithOptions:)`: when HealthKit wakes a
    /// terminated app, the observer has to be in place before launch
    /// finishes or the wake is lost.
    func activate() {
        guard let healthStore, observer == nil else { return }
        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { _, completionHandler, error in
            let completion = UncheckedSendable(completionHandler)
            guard error == nil else {
                completion.value()
                return
            }
            Task { @MainActor in
                await BackgroundStepSync.shared.catchUp()
                // Tells HealthKit this wake is handled; skipping it makes
                // the system back off future deliveries.
                completion.value()
            }
        }
        healthStore.execute(query)
        observer = query
        setWalking(loadBaseline() != nil)
    }

    // MARK: - Walking state

    /// Turns HealthKit background delivery on while a ram is walking and off
    /// otherwise, so an idle pasture never wakes the phone.
    func setWalking(_ walking: Bool) {
        guard let healthStore, deliveryEnabled != walking else { return }
        deliveryEnabled = walking
        if walking {
            // HealthKit clamps step count to its own minimum (about hourly).
            healthStore.enableBackgroundDelivery(for: stepType, frequency: .immediate) { success, error in
                if !success {
                    Self.logger.info("Step background delivery unavailable: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                }
            }
        } else {
            healthStore.disableBackgroundDelivery(for: stepType) { _, _ in }
            clearBaseline()
        }
    }

    /// "Delete all data & reset": no ram is walking any more, so HealthKit
    /// has no reason to wake the app, and no baseline is kept.
    func eraseAll() {
        setWalking(false)
        clearBaseline()
        hasOfferedResumePoint = false
    }

    // MARK: - Baseline

    /// Called by `FlockViewModel` whenever real steps land on the walking
    /// ram. Written to disk at most every `baselineWriteInterval`; the app
    /// calls `flushBaseline()` on its way into the background.
    func recordBaseline(ramId: UUID, stepsWalked: Int) {
        let now = Date()
        latestBaseline = Baseline(ramId: ramId, stepsWalked: stepsWalked, at: now)
        guard now.timeIntervalSince(lastBaselineWrite) >= Self.baselineWriteInterval else { return }
        flushBaseline()
    }

    /// Writes the newest baseline now (the app is about to be suspended).
    func flushBaseline() {
        guard let latestBaseline, let data = try? JSONEncoder().encode(latestBaseline) else { return }
        lastBaselineWrite = Date()
        UserDefaults.standard.set(data, forKey: Self.baselineKey)
    }

    func clearBaseline() {
        UserDefaults.standard.removeObject(forKey: Self.baselineKey)
        latestBaseline = nil
        lastBaselineWrite = .distantPast
    }

    /// Where the first pedometer session after launch should start, so steps
    /// walked while the app was terminated are not lost. Offered once per
    /// launch and only for the ram the baseline belongs to; later sessions
    /// start from now, as before, so switching rams can't credit the same
    /// steps twice. `alreadyApplied` is how many of the steps since the
    /// baseline the saved flock already holds (the baseline is throttled).
    func consumeLaunchResumePoint(for ram: Ram) -> (since: Date, alreadyApplied: Int)? {
        guard !hasOfferedResumePoint else { return nil }
        hasOfferedResumePoint = true
        guard ram.status == .walking,
              let baseline = loadBaseline(), baseline.ramId == ram.id,
              Date().timeIntervalSince(baseline.at) < Self.maximumBaselineAge else { return nil }
        return (baseline.at, max(0, ram.stepsWalked - baseline.stepsWalked))
    }

    private func loadBaseline() -> Baseline? {
        guard let data = UserDefaults.standard.data(forKey: Self.baselineKey) else { return nil }
        return try? JSONDecoder().decode(Baseline.self, from: data)
    }

    // MARK: - Wake

    /// Counts the steps walked since the baseline and refreshes the Live
    /// Activity and the arrival notification. Does nothing while the app is
    /// on screen: the foreground pipeline is already live there.
    func catchUp() async {
        guard !isCatchingUp, UIApplication.shared.applicationState != .active else { return }
        guard let baseline = loadBaseline() else { return }
        let now = Date()
        guard now.timeIntervalSince(baseline.at) < Self.maximumBaselineAge else {
            clearBaseline()
            return
        }
        guard let ram = FlockStore.default.load()?.activeRams.first(where: { $0.id == baseline.ramId }),
              ram.status == .walking || ram.status == .grazing else {
            clearBaseline()
            return
        }

        isCatchingUp = true
        defer { isCatchingUp = false }

        async let pedometerSince = Self.pedometerSteps(from: baseline.at, to: now)
        async let healthSince = Self.healthSteps(from: baseline.at, to: now)
        async let recent = Self.pedometerSteps(from: now.addingTimeInterval(-Self.recentPaceWindow), to: now)
        // Same merge as the foreground: the larger of the two sources, so
        // Apple Watch steps count without double counting.
        let since = max(await pedometerSince ?? 0, await healthSince ?? 0)
        let recentPace = Double(await recent ?? 0) / Self.recentPaceWindow

        let walked = min(ram.totalStepsRequired, baseline.stepsWalked + since)
        let moving = recentPace >= RamActivityAttributes.ContentState.minimumProjectedPace
        let activity = Activity<RamActivityAttributes>.activities.first {
            $0.activityState == .active && $0.attributes.ramName == ram.name
        }
        let previous = activity?.content.state
        let state = RamActivityAttributes.ContentState.make(
            ram: ram,
            stepsWalked: walked,
            isMoving: moving,
            stepsPerSecond: recentPace,
            stride: previous?.stride ?? 0,
            walkingSince: previous?.walkingSince,
            weatherSymbol: previous?.weatherSymbol,
            now: now
        )
        if let activity {
            await activity.update(ActivityContent(state: state, staleDate: state.backgroundStaleDate(now: now)))
        }
        await ArrivalEstimateNotifier.schedule(for: ram, eta: state.barEnd)
    }

    // MARK: - Step sources

    /// Steps from the motion coprocessor between two dates, or `nil` when
    /// the pedometer is unavailable or not authorized.
    nonisolated private static func pedometerSteps(from start: Date, to end: Date) async -> Int? {
        guard CMPedometer.isStepCountingAvailable(), start < end else { return nil }
        let pedometer = UncheckedSendable(CMPedometer())
        return await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            pedometer.value.queryPedometerData(from: start, to: end) { data, error in
                continuation.resume(returning: error == nil ? data?.numberOfSteps.intValue : nil)
            }
        }
    }

    /// Deduplicated step total from Health between two dates (iPhone and
    /// Apple Watch together), or `nil` without Health access.
    nonisolated private static func healthSteps(from start: Date, to end: Date) async -> Int? {
        guard HKHealthStore.isHealthDataAvailable(), start < end else { return nil }
        let store = UncheckedSendable(HKHealthStore())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(.stepCount),
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                guard error == nil, let sum = statistics?.sumQuantity() else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Int(sum.doubleValue(for: .count())))
            }
            store.value.execute(query)
        }
    }
}

// MARK: - Arrival estimate notification

/// "Almost there" from the estimated arrival. Only scheduled while the app
/// is in the background and only for arrivals within the hour: an estimate
/// further out assumes a walk nobody promised to keep up. Opening the app
/// cancels it, because the real arrival (and the real notification) come
/// from the step pipeline.
enum ArrivalEstimateNotifier {
    private static let identifierPrefix = "eta-arrival-"
    private static let enabledKey = "com.baranov.notificationsEnabled"
    /// Estimates further ahead than this are not scheduled.
    static let maximumLead: TimeInterval = 60 * 60

    @MainActor
    static func schedule(for ram: Ram, eta: Date?) async {
        let center = UNUserNotificationCenter.current()
        let identifier = identifierPrefix + ram.id.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard !ram.isGuest,
              UserDefaults.standard.bool(forKey: enabledKey),
              let eta else { return }
        let interval = eta.timeIntervalSinceNow
        guard interval > 60, interval <= maximumLead else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Almost at \(ram.legDestinationCity)", bundle: .appLanguage, locale: .appLanguage)
        content.body = String(localized: "At the pace you were walking, \(ram.name) should be there about now. Open Baranov to count the last steps.", bundle: .appLanguage, locale: .appLanguage)
        content.sound = .default
        content.threadIdentifier = ram.id.uuidString
        content.userInfo = ["ramID": ram.id.uuidString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    /// Removes every pending estimate. Called when the app comes to the
    /// foreground and the real step count takes over.
    @MainActor
    static func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }
}
