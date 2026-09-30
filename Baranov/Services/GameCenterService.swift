//
//  GameCenterService.swift
//  Baranov
//
//  Wires the flock's lifetime experience (from `RamLedger`) into
//  GameCenter as a leaderboard score. Everything GameKit shows *after*
//  sign-in — profile, leaderboard, highlights — goes through
//  `GKAccessPoint` rather than any manually-presented view controller,
//  Apple's own recommended lightweight path. Sign-in itself is the one
//  exception: GameKit still hands back a real view controller for that,
//  which has to actually be presented somewhere, so this does the
//  minimum UIKit bridging needed for that one step only.
//
//  `lettersDeliveredLeaderboardID` is a placeholder, exactly like
//  `EntitlementService.apiKey`: authentication, score submission, and the
//  Rankings button all safely no-op (never crash, never block the UI) until
//  a real leaderboard with this identifier is configured for this app in
//  App Store Connect — same for the "Game Center" capability itself, which
//  also isn't enabled on this target yet (Signing & Capabilities in
//  Xcode); that's a project-settings change no amount of source-editing
//  here can make for you.
//

import GameKit
import Observation
import UIKit
import SwiftUI

enum GameCenterAuthState: Sendable {
    /// GameKit hasn't answered yet — show a neutral state, not "Sign in".
    case unknown
    case signedIn
    case signedOut
}

enum LeaderboardScope: String, CaseIterable, Identifiable, Sendable {
    case everyone
    case friends

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .everyone: "Everyone"
        case .friends: "Friends"
        }
    }
}

enum FriendsAccess: Sendable {
    case unknown
    /// Never asked — asking shows the system prompt, so it waits for a tap.
    case notDetermined
    case authorized
    case denied
}

/// One page of a leaderboard for one scope.
struct LeaderboardSnapshot: Sendable {
    var rows: [LeaderboardRow]
    var local: LeaderboardRow?
    var total: Int
}

@Observable
@MainActor
final class GameCenterService {
    /// Placeholder — create a matching leaderboard in App Store Connect
    /// (Features > Game Center) before shipping, then this starts scoring
    /// for real with no other code changes.
    static let lettersDeliveredLeaderboardID = "com.baranov.lettersDelivered"

    /// How many rows of the table the Pasture shows.
    static let boardRowCount = 10

    /// One shared instance for the whole app, so every screen agrees on
    /// the sign-in state and `authenticateHandler` is installed once.
    static let shared = GameCenterService()

    /// `.unknown` until GameKit answers (unless the OS already says signed
    /// in). Screens show a neutral "checking" state for it rather than a
    /// sign-in button that flashes and then disappears.
    private(set) var authState: GameCenterAuthState = GKLocalPlayer.local.isAuthenticated ? .signedIn : .unknown
    var isAuthenticated: Bool { authState == .signedIn }

    private var didAttemptAuthentication = false
    private var didPresentAuthUI = false
    /// GameKit's sign-in controller, kept until it is actually on screen.
    private var pendingAuthViewController: UIViewController?

    /// Tables by scope, as last fetched by `refreshLeaderboard()`.
    private(set) var snapshots: [LeaderboardScope: LeaderboardSnapshot] = [:]
    private(set) var isLoadingLeaderboard = false
    private(set) var leaderboardLastRefreshedAt: Date?
    /// Why the table is empty when it isn't simply "nobody yet".
    private(set) var boardMessage: String?

    /// The player's Game Center friends and whether we may read them.
    private(set) var friends: [GameCenterFriend] = []
    private(set) var friendsAccess: FriendsAccess = .unknown

    /// The badges as configured in App Store Connect, keyed by identifier.
    private(set) var achievementInfo: [String: GameCenterAchievementInfo] = [:]

    /// Identifiers Game Center already lists as completed for this player.
    private(set) var completedAchievementIDs: Set<String> = []

    /// Achievement identifiers already reported this launch.
    private var reportedAchievementIDs: Set<String> = []

    init() {
        // Sign-in can change while the app is open (Settings, another
        // device, GameKit re-authenticating): follow it instead of only
        // trusting the first answer.
        NotificationCenter.default.addObserver(
            forName: .GKPlayerAuthenticationDidChangeNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncAuthenticationState() }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncAuthenticationState()
                self?.presentPendingAuthenticationUI()
            }
        }
    }

    /// Cached table for a scope, or empty.
    func snapshot(for scope: LeaderboardScope) -> LeaderboardSnapshot {
        snapshots[scope] ?? LeaderboardSnapshot(rows: [], local: nil, total: 0)
    }

    /// Brings `authState` in line with the OS. Only ever promotes to
    /// signed-in or demotes from it; "signed out" for a player who was
    /// never signed in is decided by GameKit's handler.
    private func syncAuthenticationState() {
        if GKLocalPlayer.local.isAuthenticated {
            authState = .signedIn
        } else if authState == .signedIn {
            authState = .signedOut
            snapshots = [:]
            friends = []
            friendsAccess = .unknown
            completedAchievementIDs = []
            reportedAchievementIDs = []
        }
    }

    /// Kicks off Game Center authentication once per app launch. Safe to
    /// call repeatedly. Never blocks or alerts on failure: the rest of the
    /// app works identically either way.
    func authenticateIfNeeded() {
        syncAuthenticationState()
        presentPendingAuthenticationUI()
        guard !didAttemptAuthentication else { return }
        didAttemptAuthentication = true

        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            Task { @MainActor in
                self?.handleAuthentication(viewController: viewController)
            }
        }
    }

    private func handleAuthentication(viewController: UIViewController?) {
        if let viewController {
            didPresentAuthUI = true
            pendingAuthViewController = viewController
            presentPendingAuthenticationUI()
            return
        }
        pendingAuthViewController = nil
        // The OS is the source of truth. A transient error while still
        // authenticated must not flip the UI to "signed out".
        if GKLocalPlayer.local.isAuthenticated {
            authState = .signedIn
            // The floating Game Center badge sat on top of the app's own
            // toolbar; the table lives on the Pasture instead.
            GKAccessPoint.shared.isActive = false
        } else {
            authState = .signedOut
        }
    }

    /// The "Sign in to Game Center" button: picks up an existing system
    /// sign-in, otherwise re-runs authentication so GameKit shows its
    /// sheet again, and if GameKit won't show one any more opens this
    /// app's page in Settings.
    func signIn() {
        syncAuthenticationState()
        guard !isAuthenticated else { return }
        didPresentAuthUI = false
        didAttemptAuthentication = false
        authenticateIfNeeded()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard authState != .signedIn, !didPresentAuthUI, pendingAuthViewController == nil,
                  let url = URL(string: UIApplication.openSettingsURLString) else { return }
            await UIApplication.shared.open(url)
        }
    }

    /// Presents GameKit's sign-in controller on the frontmost controller,
    /// retrying briefly while a sheet is mid-transition or no scene is
    /// active yet — dropping it would leave the player signed out with no
    /// way to get the prompt back until relaunch.
    private func presentPendingAuthenticationUI(attempt: Int = 0) {
        guard let controller = pendingAuthViewController, controller.presentingViewController == nil else { return }
        if let top = frontmostViewController(),
           !top.isBeingPresented, !top.isBeingDismissed, !top.isMovingToParent {
            top.present(controller, animated: true)
            return
        }
        guard attempt < 10 else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            self?.presentPendingAuthenticationUI(attempt: attempt + 1)
        }
    }

    private func frontmostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard
            let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
            let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    /// Submits the player's total lifetime experience points
    /// (`RamLedger.totalExperiencePoints` — every named ram's score added
    /// together). Best-effort — a network failure or unconfigured
    /// leaderboard is swallowed, never surfaced to the UI; `RamLedger`
    /// (local, always available) remains the actual source of truth for
    /// anything shown on-screen.
    func submitScore(_ score: Int) async {
        guard isAuthenticated else { return }
        do {
            try await GKLeaderboard.submitScore(
                score,
                context: 0,
                player: GKLocalPlayer.local,
                leaderboardIDs: [Self.lettersDeliveredLeaderboardID]
            )
        } catch {
            // Offline-first: silently retried next time a delivery changes
            // the score, never blocking or erroring the pasture UI.
        }
    }

    /// Opens GameCenter's own leaderboard UI via the access point. A no-op
    /// while unauthenticated, so the "Rankings" button is always safe to
    /// show without first checking `isAuthenticated` at every call site.
    func presentLeaderboard() {
        guard isAuthenticated else { return }
        GKAccessPoint.shared.trigger(leaderboardID: Self.lettersDeliveredLeaderboardID,
                                     playerScope: .global,
                                     timeScope: .allTime)
    }

    /// Loads the top of the lifetime-experience table for everyone and,
    /// when friend access was granted, for friends only — plus the local
    /// player's own row. Best-effort: offline keeps the last rows; a
    /// missing leaderboard says so instead of looking merely empty.
    func refreshLeaderboard() async {
        guard isAuthenticated, !isLoadingLeaderboard else { return }
        isLoadingLeaderboard = true
        defer { isLoadingLeaderboard = false }

        let board: GKLeaderboard
        do {
            guard let found = try await GKLeaderboard.loadLeaderboards(IDs: [Self.lettersDeliveredLeaderboardID]).first else {
                boardMessage = String(localized: "The shepherds' table isn't set up in Game Center yet.", bundle: .appLanguage, locale: .appLanguage)
                return
            }
            board = found
        } catch {
            boardMessage = String(localized: "Couldn't reach Game Center. Pull to try again.", bundle: .appLanguage, locale: .appLanguage)
            return
        }
        boardMessage = nil

        if let everyone = await loadSnapshot(of: board, scope: .global) {
            snapshots[.everyone] = everyone
        }
        if friendsAccess == .authorized, let friendsOnly = await loadSnapshot(of: board, scope: .friendsOnly) {
            snapshots[.friends] = friendsOnly
        }
        leaderboardLastRefreshedAt = Date()
    }

    private func loadSnapshot(of board: GKLeaderboard, scope: GKLeaderboard.PlayerScope) async -> LeaderboardSnapshot? {
        do {
            let (local, entries, total) = try await board.loadEntries(
                for: scope,
                timeScope: .allTime,
                range: NSRange(location: 1, length: Self.boardRowCount)
            )
            let localID = GKLocalPlayer.local.gamePlayerID
            return LeaderboardSnapshot(
                rows: entries.map { LeaderboardRow(entry: $0, isLocalPlayer: $0.player.gamePlayerID == localID) },
                local: local.map { LeaderboardRow(entry: $0, isLocalPlayer: true) },
                total: total
            )
        } catch {
            return nil
        }
    }

    /// Reads the achievements configured in App Store Connect and this
    /// player's completed ones. Best-effort: signed out, offline, or not
    /// yet configured all leave the local titles and captions in place.
    func refreshAchievements() async {
        guard isAuthenticated else { return }
        do {
            let descriptions = try await GKAchievementDescription.loadAchievementDescriptions()
            var info: [String: GameCenterAchievementInfo] = [:]
            for description in descriptions {
                info[description.identifier] = GameCenterAchievementInfo(
                    title: description.title,
                    unachievedDescription: description.unachievedDescription,
                    achievedDescription: description.achievedDescription,
                    maximumPoints: description.maximumPoints
                )
            }
            achievementInfo = info
        } catch {
            // Keep whatever was last shown.
        }
        do {
            let mine = try await GKAchievement.loadAchievements()
            let done = Set(mine.filter(\.isCompleted).map(\.identifier))
            completedAchievementIDs = done
            reportedAchievementIDs.formUnion(done)
        } catch {
            // Local badges stand on their own.
        }
    }

    /// Reports every newly-earned badge to Game Center, with the system's
    /// own completion banner. Locally-decided (`ShepherdAchievement`), so
    /// the Pasture shows the badge whether or not this call lands.
    func report(_ achievements: [ShepherdAchievement]) async {
        guard isAuthenticated else { return }
        let fresh = achievements.filter { !reportedAchievementIDs.contains($0.rawValue) }
        guard !fresh.isEmpty else { return }

        let reports = fresh.map { achievement -> GKAchievement in
            let report = GKAchievement(identifier: achievement.rawValue)
            report.percentComplete = 100
            report.showsCompletionBanner = true
            return report
        }
        do {
            try await GKAchievement.report(reports)
            reportedAchievementIDs.formUnion(fresh.map(\.rawValue))
        } catch {
            // Unconfigured in App Store Connect, or offline — try again on
            // the next flock change.
        }
    }

    /// The local player's Game Center friends. Reading them needs the
    /// player's permission: with `requestingAccess` false this only reads
    /// friends when access was already granted (so opening the Pasture
    /// never throws a system prompt at anyone); with true, an undecided
    /// player is asked — that is what the "Show my friends" button does.
    /// Never throws into the UI; keeps the last known list on failure.
    @discardableResult
    func loadFriends(requestingAccess: Bool = false) async -> [GameCenterFriend] {
        guard isAuthenticated else { return [] }
        do {
            let status = try await GKLocalPlayer.local.loadFriendsAuthorizationStatus()
            switch status {
            case .authorized:
                friendsAccess = .authorized
            case .notDetermined:
                friendsAccess = .notDetermined
                guard requestingAccess else { return friends }
            default:
                friendsAccess = .denied
                return []
            }
            let players = try await GKLocalPlayer.local.loadFriends()
            friendsAccess = .authorized
            friends = players.map { GameCenterFriend(id: $0.gamePlayerID, displayName: $0.displayName) }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            return friends
        } catch {
            if requestingAccess, friendsAccess != .authorized { friendsAccess = .denied }
            return friends
        }
    }
}

/// One row of the shepherds' leaderboard, trimmed to what the card shows.
struct LeaderboardRow: Identifiable, Hashable, Sendable {
    let id: String
    let rank: Int
    let displayName: String
    let score: Int
    let formattedScore: String
    let isLocalPlayer: Bool

    init(entry: GKLeaderboard.Entry, isLocalPlayer: Bool) {
        id = entry.player.gamePlayerID
        rank = entry.rank
        displayName = entry.player.displayName
        score = entry.score
        formattedScore = entry.formattedScore
        self.isLocalPlayer = isLocalPlayer
    }

    init(id: String, rank: Int, displayName: String, score: Int, isLocalPlayer: Bool) {
        self.id = id
        self.rank = rank
        self.displayName = displayName
        self.score = score
        self.formattedScore = "\(score) XP"
        self.isLocalPlayer = isLocalPlayer
    }
}

/// One achievement as configured in App Store Connect, trimmed to what
/// the badge row shows.
struct GameCenterAchievementInfo: Hashable, Sendable {
    let title: String
    let unachievedDescription: String
    let achievedDescription: String
    let maximumPoints: Int
}

/// A Game Center friend, trimmed down to just what `CarrierDirectoryView`
/// actually uses — a display name to prefill, and a stable id for
/// `ForEach`.
struct GameCenterFriend: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
}
