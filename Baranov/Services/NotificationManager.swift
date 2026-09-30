//
//  NotificationManager.swift
//  Baranov
//
//  The app's one front door for notifications, local and remote.
//
//  - Delegate. It's `UNUserNotificationCenter`'s delegate from launch
//    (`AppDelegate`), so a tap that cold-launches the app is never lost.
//    Banners show in the foreground too, and a tap routes to the ram or
//    letter it's about (`tappedRamID`, `tappedLetterID`).
//  - Remote pushes. Once notifications are allowed, the phone registers
//    with APNs and uploads its device token to the relay under its Shepherd
//    ID (`POST /api/v1/devices/register`, proven with the inbox token). The
//    relay pushes the moments that happen on someone else's phone: a ram
//    sent your way, a ram at your gate, your letter opened, your link opened.
//  - Local fallback. The same moments are announced locally when the phone
//    notices them itself, unless the relay already covers them with pushes
//    (`pushesCoverLetterEvents`), so nothing arrives twice. A small ledger
//    also drops a local copy of a push that was shown while the app was open.
//
//  Respects the person's own switch (`com.baranov.notificationsEnabled`) as
//  well as the system permission. Every call is best-effort: failure means
//  "no notification", never a crash.
//

import Foundation
import Observation
import UIKit
import UserNotifications

extension Notification.Name {
    /// A push about a tracked letter arrived or was tapped: worth asking the
    /// relay right away rather than on the next tick.
    static let relayPushReceived = Notification.Name("com.baranov.relayPushReceived")
}

@MainActor
@Observable
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    /// A notification about a ram was tapped (`RootView` opens it).
    var tappedRamID: UUID?
    /// A push about a letter was tapped (`RootView` opens it if it's here).
    var tappedLetterID: UUID?

    /// The moments the relay can push, and the local fallbacks share.
    enum LetterEvent: String, Sendable {
        case dispatched, arrived, opened, gateSet, collected
    }

    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private var isActivated = false
    @ObservationIgnored private var authorization: UNAuthorizationStatus = .notDetermined

    private let enabledKey = "com.baranov.notificationsEnabled"
    private let deviceTokenKey = "com.baranov.apnsDeviceToken"
    private let uploadedKey = "com.baranov.apnsUploadedSignature"
    private let serverPushesKey = "com.baranov.serverPushesActive"
    private let ledgerKey = "com.baranov.notificationLedger"

    private override init() {
        super.init()
    }

    // MARK: - Launch

    /// Called from `AppDelegate` at launch, before any notification can be
    /// delivered to the app.
    func activate() {
        guard !isActivated else { return }
        isActivated = true
        center.delegate = self
        NotificationCenter.default.addObserver(
            forName: RamNotificationService.preferencesChanged, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                _ = Task {
                    await NotificationManager.shared.registerForRemoteIfAuthorized(forceUpload: true)
                }
            }
        }
        Task { await registerForRemoteIfAuthorized() }
    }

    private var isEnabledByPerson: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    // MARK: - Permission

    /// Asks once (on the first letter sent, if onboarding didn't already),
    /// then registers for pushes when allowed.
    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
        if settings.authorizationStatus == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            UserDefaults.standard.set(granted, forKey: enabledKey)
            authorization = granted ? .authorized : .denied
            NotificationCenter.default.post(name: RamNotificationService.preferencesChanged, object: nil)
        }
        await registerForRemoteIfAuthorized()
    }

    /// Registers with APNs when the system allows notifications. The token
    /// comes back through `AppDelegate`.
    func registerForRemoteIfAuthorized(forceUpload: Bool = false) async {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        default:
            break
        }
        await uploadIfPossible(force: forceUpload)
    }

    // MARK: - Device token

    func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: deviceTokenKey)
        Task { await uploadIfPossible() }
    }

    func didFailToRegister(_ error: Error) {
        DiagnosticsLog.shared.log("APNs registration failed: \(error.localizedDescription)", category: "push")
    }

    /// Sends the device token to the relay once this phone has a registered
    /// Shepherd ID, and again whenever the token, the ID or the person's
    /// switch changes. Called on every relay tick; costs nothing when
    /// nothing changed.
    func uploadIfPossible(force: Bool = false) async {
        guard TelemetryService.isServerConfigured,
              let token = UserDefaults.standard.string(forKey: deviceTokenKey),
              let address = RecipientKeyring.myAddress,
              let inboxToken = AddressKeychain.inboxToken else { return }
        let enabled = isEnabledByPerson && isSystemAuthorized
        let environment = Self.apnsEnvironment
        let signature = "\(token)|\(address)|\(environment)|\(enabled)"
        if !force, UserDefaults.standard.string(forKey: uploadedKey) == signature { return }
        let relay = LetterRelayService(baseURL: TelemetryService.configuredBaseURL)
        do {
            let receipt = try await relay.registerDevice(
                address: address, inboxToken: inboxToken, deviceToken: token,
                environment: environment, enabled: enabled
            )
            UserDefaults.standard.set(signature, forKey: uploadedKey)
            UserDefaults.standard.set(receipt.registered && receipt.pushEnabled && enabled, forKey: serverPushesKey)
        } catch {
            // Next tick.
        }
    }

    /// Debug builds get sandbox tokens; TestFlight and the App Store get
    /// production ones.
    static var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private var isSystemAuthorized: Bool {
        switch authorization {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    /// Whether the relay pushes the tracked-post moments to this phone, so
    /// the local copies should stay quiet.
    var pushesCoverLetterEvents: Bool {
        UserDefaults.standard.bool(forKey: serverPushesKey) && isEnabledByPerson && isSystemAuthorized
    }

    // MARK: - Local announcements

    /// Announces a tracked-post moment locally, unless a push covers it or
    /// the same moment was already shown.
    func announce(_ event: LetterEvent, letterID: UUID, title: String, body: String, ramID: UUID? = nil, evenWithPushes: Bool = false) {
        guard isEnabledByPerson else { return }
        if !evenWithPushes, pushesCoverLetterEvents, event != .collected { return }
        guard claim("\(event.rawValue)-\(letterID.uuidString)") else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = letterID.uuidString
        var info: [String: String] = ["letterId": letterID.uuidString, "kind": event.rawValue]
        if let ramID { info["ramID"] = ramID.uuidString }
        content.userInfo = info
        center.add(UNNotificationRequest(identifier: "\(event.rawValue)-\(letterID.uuidString)", content: content, trigger: nil))
    }

    /// Whether a local "at the gate" banner for this ram should be skipped:
    /// a letter the relay delivered, when the relay already pushed its arrival.
    func shouldSkipGateNotice(for ram: Ram) -> Bool {
        guard ram.addressedToThisPhone, let letterID = ram.letter?.id else { return false }
        if pushesCoverLetterEvents { return true }
        return !claim("arrived-\(letterID.uuidString)")
    }

    /// Records a moment as shown. `false` if it already was (in the last
    /// week), so the caller stays quiet.
    @discardableResult
    func claim(_ key: String, now: Date = Date()) -> Bool {
        var ledger = (UserDefaults.standard.dictionary(forKey: ledgerKey) as? [String: Double]) ?? [:]
        let cutoff = now.addingTimeInterval(-7 * 86_400).timeIntervalSince1970
        ledger = ledger.filter { $0.value > cutoff }
        if ledger[key] != nil { return false }
        ledger[key] = now.timeIntervalSince1970
        UserDefaults.standard.set(ledger, forKey: ledgerKey)
        return true
    }

    // MARK: - Remote payloads

    fileprivate func handleRemote(_ userInfo: [AnyHashable: Any], tapped: Bool) {
        let letterID = (userInfo["letterId"] as? String).flatMap(UUID.init(uuidString:))
        let ramID = (userInfo["ramID"] as? String).flatMap(UUID.init(uuidString:))
        if let kind = userInfo["kind"] as? String, let letterID {
            claim("\(kind)-\(letterID.uuidString)")
            NotificationCenter.default.post(name: .relayPushReceived, object: nil)
        }
        guard tapped else { return }
        if let ramID {
            tappedRamID = ramID
        } else if let letterID {
            tappedLetterID = letterID
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Banners show in the foreground too: a ram reaching the gate while
    /// you're looking at the map is still news.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let info = UncheckedSendable(notification.request.content.userInfo)
        Task { @MainActor in
            NotificationManager.shared.handleRemote(info.value, tapped: false)
        }
        completionHandler([.banner, .list, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = UncheckedSendable(response.notification.request.content.userInfo)
        Task { @MainActor in
            NotificationManager.shared.handleRemote(info.value, tapped: true)
        }
        completionHandler()
    }
}
