//
//  BestEffort.swift
//  Baranov
//
//  A "do this, but never let it hang the caller" wrapper for the handful
//  of system APIs (permission prompts, EventKit, CLGeocoder) that have a
//  real, observed history of occasionally never calling their completion
//  handler back — a stalled `UNUserNotificationCenter` or `CLGeocoder`
//  callback used to freeze whatever screen asked for it (onboarding's
//  "Turn on arrival alerts" step, Pasture's first calendar-trip refresh)
//  because nothing was ever waiting to give up on it.
//
//  Every caller here already treats a denial exactly like a timeout —
//  both just mean "carry on without this" — so letting a slow call keep
//  running in the background with its result discarded is a safe trade
//  for never freezing the screen that started it. Cancellation isn't an
//  option: none of these APIs check `Task.isCancelled`, so a plain
//  `Task.cancel()` wouldn't stop them, and `withTaskGroup` won't return
//  until every child task it holds actually finishes — which is exactly
//  the hang this exists to avoid.
//

import Foundation

/// Wraps a value that isn't (or isn't yet) marked `Sendable` so it can be
/// captured by the background task `BestEffort` races against a timeout.
/// Safe for the handful of system objects used with it here (a
/// permission-checking singleton, or a request object built fresh for
/// one single-shot query) — none of them are ever touched from more than
/// one place at a time.
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

enum BestEffort {
    /// Runs `work` in its own unstructured task and returns as soon as it
    /// finishes or `seconds` pass, whichever is first.
    static func run(seconds: Double = 5, _ work: @escaping @Sendable () async -> Void) async {
        let signal = Signal()
        Task {
            await work()
            await signal.fire()
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            await signal.fire()
        }
        await signal.wait()
    }

    /// Same idea, but for a call whose result is worth keeping when it
    /// arrives in time — `nil` on timeout, exactly as a real failure from
    /// the underlying API would be handled by every caller here.
    static func run<T: Sendable>(seconds: Double = 5, _ work: @escaping @Sendable () async -> T) async -> T? {
        let box = ResultBox<T>()
        Task {
            let value = await work()
            await box.fire(value)
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            await box.fire(nil)
        }
        return await box.wait()
    }

    private actor Signal {
        private var didFire = false
        private var continuation: CheckedContinuation<Void, Never>?

        func fire() {
            guard !didFire else { return }
            didFire = true
            continuation?.resume()
            continuation = nil
        }

        func wait() async {
            if didFire { return }
            await withCheckedContinuation { continuation = $0 }
        }
    }

    private actor ResultBox<T: Sendable> {
        private var didFire = false
        private var result: T?
        private var continuation: CheckedContinuation<T?, Never>?

        func fire(_ value: T?) {
            guard !didFire else { return }
            didFire = true
            result = value
            continuation?.resume(returning: value)
            continuation = nil
        }

        func wait() async -> T? {
            if didFire { return result }
            return await withCheckedContinuation { continuation = $0 }
        }
    }
}
