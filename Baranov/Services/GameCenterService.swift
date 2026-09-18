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

@Observable
@MainActor
final class GameCenterService {
    /// Placeholder — create a matching leaderboard in App Store Connect
    /// (Features > Game Center) before shipping, then this starts scoring
    /// for real with no other code changes.
    static let lettersDeliveredLeaderboardID = "com.baranov.lettersDelivered"

    private(set) var isAuthenticated = false
    private var didAttemptAuthentication = false

    /// The top of the leaderboard and where this player sits on it, as
    /// last fetched by `refreshLeaderboard()` — what `ShepherdsBoardCard`
    /// renders. Empty until signed in and the leaderboard exists in App
    /// Store Connect.
    private(set) var topEntries: [LeaderboardRow] = []
    private(set) var localEntry: LeaderboardRow?
    private(set) var totalPlayers = 0
    private(set) var isLoadingLeaderboard = false
    private(set) var leaderboardLastRefreshedAt: Date?

    /// Achievement identifiers already reported this launch, so a flock
    /// change never re-reports the same badge.
    private var reportedAchievementIDs: Set<String> = []

    /// Kicks off GameCenter authentication once per app launch. Safe to
    /// call repeatedly — a request already made is a no-op. Never blocks
    /// or alerts on failure (declined sign-in, no network, GameCenter
    /// disabled): the rest of the app works identically either way, with
    /// the Rankings button and score submission simply becoming inert.
    ///
    /// GameKit calls `authenticateHandler` with a non-nil view controller
    /// whenever the player isn't already signed in at the OS level — that
    /// controller has to actually be presented for sign-in to happen at
    /// all. Silently discarding it (as this used to do) meant nobody who
    /// wasn't already signed into Game Center system-wide ever saw a
    /// sign-in prompt, so `isAuthenticated` just stayed false forever and
    /// the access point never appeared. That's `presentAuthenticationViewController`
    /// below.
    func authenticateIfNeeded() {
        guard !didAttemptAuthentication else { return }
        didAttemptAuthentication = true

        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }

                if let viewController {
                    self.presentAuthenticationViewController(viewController)
                    return
                }

                self.isAuthenticated = (error == nil) && GKLocalPlayer.local.isAuthenticated
                guard self.isAuthenticated else { return }

                // GKAccessPoint draws its own small overlay badge and
                // handles sign-in/profile/leaderboard UI natively — no
                // UIViewControllerRepresentable bridging needed.
                GKAccessPoint.shared.location = .topTrailing
                GKAccessPoint.shared.showHighlights = true
                GKAccessPoint.shared.isActive = true
            }
        }
    }

    /// Finds the frontmost presented view controller in the active scene
    /// and presents GameKit's own sign-in UI on it. The only bit of UIKit
    /// bridging this service needs — everything else GameKit shows
    /// (profile, leaderboard, highlights) goes through `GKAccessPoint`
    /// instead, which needs none of this.
    private func presentAuthenticationViewController(_ viewController: UIViewController) {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
            let rootViewController = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }

        var topController = rootViewController
        while let presented = topController.presentedViewController {
            topController = presented
        }
        topController.present(viewController, animated: true)
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

    /// Loads the top three on the lifetime-experience leaderboard plus
    /// the local player's own entry. Best-effort: unauthenticated, offline,
    /// or an unconfigured leaderboard all just leave the last known rows
    /// in place. The board is a nice thing to look at, never something the
    /// pasture waits on.
    func refreshLeaderboard() async {
        guard isAuthenticated, !isLoadingLeaderboard else { return }
        isLoadingLeaderboard = true
        defer { isLoadingLeaderboard = false }

        do {
            let boards = try await GKLeaderboard.loadLeaderboards(IDs: [Self.lettersDeliveredLeaderboardID])
            guard let board = boards.first else { return }
            let (local, entries, total) = try await board.loadEntries(
                for: .global,
                timeScope: .allTime,
                range: NSRange(location: 1, length: 3)
            )
            let localID = GKLocalPlayer.local.gamePlayerID
            topEntries = entries.map { LeaderboardRow(entry: $0, isLocalPlayer: $0.player.gamePlayerID == localID) }
            localEntry = local.map { LeaderboardRow(entry: $0, isLocalPlayer: true) }
            totalPlayers = total
            leaderboardLastRefreshedAt = Date()
        } catch {
            // Offline-first: keep whatever we last showed.
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

    /// The local player's Game Center friends, for `CarrierDirectoryView`
    /// to offer as a fast way to fill in a known carrier's name — GameKit
    /// has no idea where any of them are actually headed, so this only
    /// ever prefills the name field, never the destination. Returns an
    /// empty list (never throws into the UI) if unauthenticated, if the
    /// person hasn't granted friend-list access, or if the request just
    /// fails — friend discovery is a nice-to-have, not load-bearing.
    func loadFriends() async -> [GameCenterFriend] {
        guard isAuthenticated else { return [] }
        do {
            let status = try await GKLocalPlayer.local.loadFriendsAuthorizationStatus()
            guard status == .authorized else { return [] }
            let players = try await GKLocalPlayer.local.loadFriends()
            return players.map { GameCenterFriend(id: $0.gamePlayerID, displayName: $0.displayName) }
        } catch {
            return []
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

/// A Game Center friend, trimmed down to just what `CarrierDirectoryView`
/// actually uses — a display name to prefill, and a stable id for
/// `ForEach`.
struct GameCenterFriend: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
}
