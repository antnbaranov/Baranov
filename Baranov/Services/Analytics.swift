import Foundation
import UIKit

/// Names of every product event. Keep this list short: each event should answer a question.
enum AnalyticsEvent: String, Sendable {
    case appOpened = "app_opened"
    case onboardingCompleted = "onboarding_completed"
    case letterComposed = "letter_composed"
    case letterSent = "letter_sent"
    case letterArrived = "letter_arrived"
    case letterOpened = "letter_opened"
    case handoffStarted = "handoff_started"
    case handoffCompleted = "handoff_completed"
    case stepsBatch = "steps_batch"
    case paywallViewed = "paywall_viewed"
    case purchaseStarted = "purchase_started"
    case purchaseCompleted = "purchase_completed"
    case purchaseRestored = "purchase_restored"
    case logsSent = "logs_sent"
}

/// Anonymous, opt-out product analytics. Offline-first: events are queued on disk and
/// posted in batches to the course receiver (`POST /telemetry/usage-events`).
/// Never blocks the UI or step recording; every failure is swallowed and retried later.
actor Analytics {
    static let shared = Analytics()

    struct Payload: Codable, Sendable {
        var event_id: String
        var name: String
        var timestamp: String
        var anon_id: String
        var app_version: String
        var properties: [String: Int]
    }

    static let consentKey = "analyticsEnabled"
    private let defaults = UserDefaults.standard
    private let queueURL: URL
    private let baseURL: URL
    private var queue: [Payload] = []
    private var pendingSteps = 0
    private var lastStepFlush = Date()
    private var isFlushing = false
    private let batchSize = 20
    private let maxQueue = 2_000

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        queueURL = dir.appendingPathComponent("analytics-queue.json")
        let configured = Bundle.main.object(forInfoDictionaryKey: "TelemetryBaseURL") as? String
        baseURL = URL(string: configured ?? "http://localhost:8080") ?? URL(string: "http://localhost:8080")!
        if let data = try? Data(contentsOf: queueURL),
           let saved = try? JSONDecoder().decode([Payload].self, from: data) {
            queue = saved
        }
    }

    // MARK: Consent (opt-out, default on, anonymous)

    nonisolated var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.consentKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.consentKey) }
    }

    func setEnabled(_ on: Bool) {
        isEnabled = on
        if !on { queue.removeAll(); pendingSteps = 0; persist() }
    }

    /// Random ID generated on this device. Not linked to name, Apple ID, contacts or device identifiers.
    private var anonID: String {
        if let id = defaults.string(forKey: "analyticsAnonID") { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: "analyticsAnonID")
        return id
    }

    // MARK: Recording

    /// Fire-and-forget from any context.
    nonisolated func track(_ event: AnalyticsEvent, _ properties: [String: Int] = [:]) {
        Task { await record(event.rawValue, properties) }
    }

    /// Call with each CMPedometer delta. Steps are summed and sent as one event, never one per step.
    nonisolated func addSteps(_ steps: Int) {
        Task { await accumulate(steps) }
    }

    private func accumulate(_ steps: Int) async {
        guard isEnabled, steps > 0 else { return }
        pendingSteps += steps
        if pendingSteps >= 100 || Date().timeIntervalSince(lastStepFlush) > 300 {
            flushSteps()
            await flush()
        }
    }

    private func flushSteps() {
        guard pendingSteps > 0 else { return }
        appendEvent(AnalyticsEvent.stepsBatch.rawValue, ["steps": pendingSteps])
        pendingSteps = 0
        lastStepFlush = Date()
    }

    private func record(_ name: String, _ properties: [String: Int]) async {
        guard isEnabled else { return }
        appendEvent(name, properties)
        if queue.count >= batchSize { await flush() }
    }

    private func appendEvent(_ name: String, _ properties: [String: Int]) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        queue.append(Payload(event_id: UUID().uuidString, name: name,
                             timestamp: ISO8601DateFormatter().string(from: Date()),
                             anon_id: anonID, app_version: version, properties: properties))
        if queue.count > maxQueue { queue.removeFirst(queue.count - maxQueue) }
        persist()
    }

    // MARK: Sending

    /// Call when the app moves to the background.
    func flush() async {
        flushSteps()
        // No server: keep the (bounded) queue for when one is configured.
        guard isEnabled, !isFlushing, !queue.isEmpty, TelemetryService.isServerConfigured else { return }
        isFlushing = true
        defer { isFlushing = false }

        let batch = Array(queue.prefix(200))
        var request = URLRequest(url: baseURL.appendingPathComponent("telemetry/usage-events"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["events": batch])

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                let sent = Set(batch.map(\.event_id))
                queue.removeAll { sent.contains($0.event_id) }
                persist()
            }
        } catch {
            // Offline or receiver down: keep the queue and retry on the next flush.
            DiagnosticsLog.shared.log("analytics flush failed: \(error.localizedDescription)", category: "analytics")
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(queue) {
            try? data.write(to: queueURL, options: .atomic)
        }
    }
}
