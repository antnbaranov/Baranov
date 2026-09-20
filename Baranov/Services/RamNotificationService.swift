//
//  RamNotificationService.swift
//  Baranov
//
//  Local notifications that earn their interruption. A slow post has
//  exactly four moments worth a buzz:
//
//  1. A ram reached the recipient's gate — there's a letter to open.
//  2. A ram reached a coast or border and needs a carrier.
//  3. A ram arrived on this phone from someone else (AirDrop or a shake).
//  4. Nothing has moved for a day — one nudge, with the real distance
//     left, never a streak guilt-trip. A second, gentler one after three
//     days, then silence.
//
//  Plus one forecast each morning while something is walking: how far is
//  left, in real units. Everything is computed from the flock at schedule
//  time and re-scheduled on every change, so a notification never fires
//  for a state that no longer exists (a ram that was opened, handed off
//  or removed cancels its own pending nudges).
//
//  Respects the person's own switch (`com.baranov.notificationsEnabled`,
//  the Pasture toggle) on top of the system authorization; when either is
//  off, this service does nothing at all. `UNUserNotificationCenter` is
//  its own process boundary, so every call here is fire-and-forget and a
//  failure only ever means "no notification", never a crash.
//

import Foundation
import Observation
import UserNotifications

@Observable
@MainActor
final class RamNotificationService: NSObject {

    /// Set when the person taps a notification about a specific ram —
    /// `RootView` opens the Pasture on that ram and clears it.
    var tappedRamID: UUID?

    private let center = UNUserNotificationCenter.current()
    private let enabledKey = "com.baranov.notificationsEnabled"

    /// Last status seen per ram, so status *changes* can be detected
    /// across `sync` calls without diffing whole arrays.
    private var lastKnownStatus: [UUID: RamStatus] = [:]
    /// Last step count and when it last changed, per ram — what the idle
    /// nudge is timed from.
    private var lastStepChange: [UUID: (steps: Int, at: Date)] = [:]
    private var hasPrimed = false

    /// Pending transitions, keyed by ram ID — only the latest transition
    /// per ram survives the debounce window, so a cascade through
    /// `.atSea` → `.waitingForHandoff` → `.grazing` delivers one
    /// notification for the final state, not three.
    private var pendingTransitions: [UUID: (ram: Ram, from: RamStatus?)] = [:]
    private var debounceTask: Task<Void, Never>?

    override init() {
        super.init()
        center.delegate = self
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    // MARK: - Sync

    /// Call on every flock change (and once at launch). Transitions are
    /// buffered and delivered after a short debounce window, so a cascade
    /// of mutations (e.g. a voyage landing followed by a leg resolution)
    /// produces one notification for the final state, not one per
    /// intermediate step.
    func sync(rams: [Ram]) {
        // First call after launch only primes the memory — a relaunch must
        // never re-announce every ram already sitting at a gate.
        if !hasPrimed {
            for ram in rams {
                lastKnownStatus[ram.id] = ram.status
                lastStepChange[ram.id] = (ram.stepsWalked, Date())
            }
            hasPrimed = true
            Task { await replan(rams: rams) }
            return
        }

        for ram in rams {
            let previous = lastKnownStatus[ram.id]
            if previous != ram.status {
                // Buffer: keep the *original* `from` status for this ram
                // if it's already pending — that's the real transition the
                // person should know about. Only the ram snapshot (with its
                // latest state) is replaced.
                if pendingTransitions[ram.id] == nil {
                    pendingTransitions[ram.id] = (ram, previous)
                } else {
                    pendingTransitions[ram.id]?.ram = ram
                }
            }
            lastKnownStatus[ram.id] = ram.status

            if lastStepChange[ram.id]?.steps != ram.stepsWalked {
                lastStepChange[ram.id] = (ram.stepsWalked, Date())
            }
        }
        for gone in Set(lastKnownStatus.keys).subtracting(rams.map(\.id)) {
            lastKnownStatus[gone] = nil
            lastStepChange[gone] = nil
            pendingTransitions[gone] = nil
        }

        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            flushPendingTransitions()
        }

        Task { await replan(rams: rams) }
    }

    /// Delivers every buffered transition and clears the buffer.
    private func flushPendingTransitions() {
        let transitions = pendingTransitions
        pendingTransitions.removeAll()
        for (_, entry) in transitions {
            announceTransition(of: entry.ram, from: entry.from)
        }
    }

    // MARK: - Immediate

    private func announceTransition(of ram: Ram, from previous: RamStatus?) {
        guard isEnabled else { return }
        let letter = ram.letter

        switch (previous, ram.status) {
        case (_, .arrivedAtGate):
            deliver(
                id: "gate-\(ram.id.uuidString)",
                title: "\(ram.name) is at the gate",
                body: letter.map { "A letter from \($0.senderName) for \($0.recipientName) is waiting. Hold the seal to open it." }
                    ?? "A letter is waiting. Hold the seal to open it.",
                ramID: ram.id,
                interruptionLevel: .timeSensitive
            )
        case (.walking, .waitingForHandoff), (.grazing, .waitingForHandoff):
            // Only when the ram walked to a port — not when it's an
            // intermediate step after a voyage landing or a fresh import.
            deliver(
                id: "handoff-\(ram.id.uuidString)",
                title: "\(ram.name) reached \(ram.legDestinationCity)",
                body: "No road goes further. A packet will carry it across — or hand it to someone crossing sooner and it skips the wait.",
                ramID: ram.id
            )
        case (_, .atSea):
            deliver(
                id: "sailed-\(ram.id.uuidString)",
                title: "\(ram.name) is at sea",
                body: ram.voyage.map { "Aboard the packet out of \($0.departurePortName), due in \($0.arrivalPortName) \($0.arrivesAt.formatted(.relative(presentation: .named)))." }
                    ?? "Crossing the water. Nothing to walk until it lands.",
                ramID: ram.id
            )
        case (.atSea, .grazing), (.atSea, .walking):
            deliver(
                id: "landed-\(ram.id.uuidString)",
                title: "\(ram.name) came ashore in \(ram.currentCity)",
                body: "\(DistanceFormatter.string(forMeters: ram.remainingSteps)) to \(ram.legDestinationCity) — your steps move it again.",
                ramID: ram.id
            )
        case (nil, .grazing), (nil, .walking):
            // A brand-new ram that didn't start here is one that just
            // arrived from another phone; one we composed ourselves is
            // announced by the compose flow, not a notification.
            if ram.routeHistory.count > 1 || !ram.stamps.filter({ $0.kind == .handoff }).isEmpty {
                deliver(
                    id: "arrived-\(ram.id.uuidString)",
                    title: "\(ram.name) is in your pasture",
                    body: letter.map { "Carrying a letter from \($0.senderName) to \($0.recipientName). \(DistanceFormatter.string(forMeters: ram.remainingSteps)) to \(ram.legDestinationCity) — your steps move it now." }
                        ?? "\(DistanceFormatter.string(forMeters: ram.remainingSteps)) to \(ram.legDestinationCity) — your steps move it now.",
                    ramID: ram.id
                )
            }
        default:
            break
        }
    }

    private func deliver(
        id: String,
        title: String,
        body: String,
        ramID: UUID,
        interruptionLevel: UNNotificationInterruptionLevel = .active
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = ramID.uuidString
        content.userInfo = ["ramID": ramID.uuidString]
        content.interruptionLevel = interruptionLevel
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request)
    }

    // MARK: - Planned

    private func replan(rams: [Ram]) async {
        let settings = await center.notificationSettings()
        let authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        let pendingIDs = await center.pendingNotificationRequests().map(\.identifier)
        let ours = pendingIDs.filter { $0.hasPrefix("idle-") || $0.hasPrefix("morning") }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        // Badge: letters waiting to be opened, nothing else.
        let waiting = rams.filter { $0.status == .arrivedAtGate }.count
        try? await center.setBadgeCount(waiting)

        guard isEnabled, authorized else { return }

        let walking = rams.filter { $0.status == .walking || $0.status == .grazing }
        for ram in walking {
            scheduleIdleNudges(for: ram)
        }
        if let furthest = walking.max(by: { $0.remainingSteps < $1.remainingSteps }) {
            scheduleMorningForecast(for: furthest, others: walking.count - 1)
        }
    }

    /// One nudge after a day of no steps, a gentler one after three days,
    /// then nothing — timed from the ram's last step, and replaced on
    /// every sync so a ram that moved never gets nagged.
    private func scheduleIdleNudges(for ram: Ram) {
        let since = lastStepChange[ram.id]?.at ?? Date()
        let recipient = ram.letter?.recipientName ?? ram.targetCity
        let remaining = DistanceFormatter.string(forMeters: ram.remainingSteps)

        let nudges: [(String, TimeInterval, String, String)] = [
            (
                "idle-1d-\(ram.id.uuidString)", 24 * 3600,
                "\(ram.name) hasn't moved since yesterday",
                "\(recipient) is \(remaining) away. A walk to the shop and back is a few hundred metres closer."
            ),
            (
                "idle-3d-\(ram.id.uuidString)", 3 * 24 * 3600,
                "\(ram.name) is grazing",
                "Three quiet days. The letter keeps; the ram waits. \(remaining) left whenever you are."
            ),
        ]

        for (id, delay, title, body) in nudges {
            let fireAt = since.addingTimeInterval(delay)
            let interval = fireAt.timeIntervalSinceNow
            guard interval > 60 else { continue }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.threadIdentifier = ram.id.uuidString
            content.userInfo = ["ramID": ram.id.uuidString]
            content.interruptionLevel = .passive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    /// 8:30 every morning while something is walking: the honest distance
    /// left, refreshed on every sync so it's never stale by more than a
    /// day's walking.
    private func scheduleMorningForecast(for ram: Ram, others: Int) {
        let remaining = DistanceFormatter.string(forMeters: ram.remainingSteps)
        let content = UNMutableNotificationContent()
        content.title = "\(remaining) to \(ram.legDestinationCity)"
        content.body = others > 0
            ? "\(ram.name) is the farthest out, with \(others) more ram\(others == 1 ? "" : "s") walking. Every step today counts."
            : "\(ram.name) walks when you do. Every step today counts."
        content.threadIdentifier = ram.id.uuidString
        content.userInfo = ["ramID": ram.id.uuidString]
        content.interruptionLevel = .passive

        var components = DateComponents()
        components.hour = 8
        components.minute = 30
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: "morning", content: content, trigger: trigger))
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension RamNotificationService: UNUserNotificationCenterDelegate {
    /// Show a banner even while the app is in the foreground — a ram
    /// reaching the gate while you're looking at the map is still news.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let ramID = (response.notification.request.content.userInfo["ramID"] as? String).flatMap(UUID.init)
        Task { @MainActor [weak self] in
            self?.tappedRamID = ramID
        }
        completionHandler()
    }
}
