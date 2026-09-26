//
//  ShepherdsBoardCard.swift
//  Baranov
//
//  Game Center, shown rather than hidden behind a "Rankings" button: the
//  person's lifetime experience, where they sit on the shepherds'
//  leaderboard with the top three around them, and the six badges a slow
//  post hands out — each one decided locally (`ShepherdAchievement`) so
//  it is real on every phone, then reported to Game Center with the
//  system's own banner.
//
//  Honest in every state: signed out shows a sign-in row, not fake ranks;
//  an empty board says so; a badge not yet earned shows how far along it
//  is. Native materials, semantic colours, SF Symbols, no glow.
//

import SwiftUI
import UIKit

struct ShepherdsBoardCard: View {
    let experiencePoints: Int
    let progress: ShepherdAchievement.Progress
    let isAuthenticated: Bool
    /// GameKit hasn't answered yet — show "checking", never a sign-in button.
    var isCheckingSignIn = false
    let isLoading: Bool
    @Binding var scope: LeaderboardScope
    let topEntries: [LeaderboardRow]
    let localEntry: LeaderboardRow?
    let totalPlayers: Int
    /// Titles and unlock texts from App Store Connect, keyed by achievement id.
    var achievementInfo: [String: GameCenterAchievementInfo] = [:]
    /// Achievements Game Center already lists as completed for this player.
    var remoteCompletedIDs: Set<String> = []
    /// The player's Game Center friends and whether we may read them.
    var friends: [GameCenterFriend] = []
    var friendsAccess: FriendsAccess = .unknown
    /// Why the table is empty when it isn't simply "nobody yet".
    var boardMessage: String? = nil
    let onSignInTapped: () -> Void
    var onRequestFriends: () -> Void = {}
    var onOpenFullBoard: () -> Void = {}

    @State private var earnedTick = 0
    @State private var selectedAchievement: ShepherdAchievement = .firstLetter

    private var earned: Set<ShepherdAchievement> {
        Set(ShepherdAchievement.earned(progress))
            .union(ShepherdAchievement.allCases.filter { remoteCompletedIDs.contains($0.rawValue) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            scoreRow
            board
            achievements
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onChange(of: earned.count) { old, new in
            if new > old { earnedTick += 1 }
        }
        .sensoryFeedback(.success, trigger: earnedTick)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("Shepherds' Board", systemImage: "trophy.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Score

    private var scoreRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            KeyframeAnimator(
                initialValue: XPAnimationValues(),
                trigger: experiencePoints
            ) { values in
                Text("\(experiencePoints)")
                    .scaledFont(size: 34, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: false))
                    .scaleEffect(values.scale, anchor: .bottom)
                    .offset(y: values.verticalOffset)
            } keyframes: { _ in
                KeyframeTrack(\.verticalOffset) {
                    SpringKeyframe(0, duration: 0.1)
                    SpringKeyframe(-8, duration: 0.15)
                    SpringKeyframe(0, spring: .bouncy(duration: 0.35))
                }
                KeyframeTrack(\.scale) {
                    SpringKeyframe(1, duration: 0.1)
                    SpringKeyframe(1.14, duration: 0.15)
                    SpringKeyframe(1, spring: .bouncy(duration: 0.35))
                }
            }
            Text("XP")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                if let localEntry {
                    Text("#\(localEntry.rank)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .contentTransition(.numericText())
                        .animation(.snappy, value: localEntry.rank)
                    Text(totalPlayers > 0 ? "of \(totalPlayers) shepherds" : "on the board")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(isAuthenticated ? "Not ranked yet" : (isCheckingSignIn ? "Checking…" : "Not signed in"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private struct XPAnimationValues {
        var verticalOffset: Double = 0
        var scale: Double = 1
    }

    // MARK: - Leaderboard

    @ViewBuilder
    private var board: some View {
        if isCheckingSignIn {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking Game Center…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } else if !isAuthenticated {
            signInRow
        } else {
            VStack(spacing: 10) {
                Picker("Table", selection: $scope) {
                    ForEach(LeaderboardScope.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                tableContent
            }
        }
    }

    private var signInRow: some View {
        Button(action: onSignInTapped) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sign in to Game Center")
                        .font(.subheadline.weight(.semibold))
                    Text("See where you stand among other shepherds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tableContent: some View {
        if scope == .friends, friendsAccess != .authorized {
            friendsAccessRow
        } else {
            if topEntries.isEmpty {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(topEntries.enumerated()), id: \.element.id) { index, row in
                        boardRow(row)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .trailing)
                                        .combined(with: .opacity)
                                        .animation(.spring(response: 0.45, dampingFraction: 0.8)
                                            .delay(Double(min(index, 5)) * 0.05)),
                                    removal: .opacity
                                )
                            )
                    }
                    if let localEntry, !topEntries.contains(where: { $0.isLocalPlayer }) {
                        Divider().padding(.vertical, 2)
                        boardRow(localEntry)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            if scope == .friends {
                unrankedFriends
            }
        }
    }

    private var emptyMessage: LocalizedStringKey {
        if isLoading { return "Fetching the table…" }
        if let boardMessage { return LocalizedStringKey(boardMessage) }
        return scope == .friends
            ? "None of your friends are on the table yet."
            : "The table is empty — be the first shepherd on it."
    }

    /// Friends who haven't earned a place yet, so the list is never
    /// missing anyone the player expects to see.
    @ViewBuilder
    private var unrankedFriends: some View {
        let ranked = Set(topEntries.map(\.id))
        let others = friends.filter { !ranked.contains($0.id) }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Friends not on the table yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                ForEach(others.prefix(10)) { friend in
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                        Text(friend.displayName)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var friendsAccessRow: some View {
        if friendsAccess == .denied {
            VStack(alignment: .leading, spacing: 6) {
                Text("Friends are turned off for Baranov.")
                    .font(.subheadline.weight(.semibold))
                Text("Allow Baranov to see your Game Center friends in Settings to compare tables.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: url)
                        .font(.footnote.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Button(action: onRequestFriends) {
                HStack(spacing: 10) {
                    Image(systemName: "person.2.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Show my friends")
                            .font(.subheadline.weight(.semibold))
                        Text("Game Center will ask once before Baranov can see them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func boardRow(_ row: LeaderboardRow) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(row.rank <= 3 ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                    .frame(width: 28, height: 28)
                Text("\(row.rank)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(row.rank <= 3 ? Color.accentColor : Color.secondary)
            }
            Text(row.isLocalPlayer ? "You" : row.displayName)
                .font(.subheadline.weight(row.isLocalPlayer ? .semibold : .regular))
                .lineLimit(1)
            Spacer()
            Text(row.formattedScore)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(row.isLocalPlayer ? .primary : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            row.isLocalPlayer ? AnyShapeStyle(Color.accentColor.opacity(0.10)) : AnyShapeStyle(.background.opacity(0.5)),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    // MARK: - Achievements

    private var achievements: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Badges")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(earned.count) of \(ShepherdAchievement.allCases.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Pictures only: the card's front is the badge, and turning it
            // over (tap) tells its story. Generous spacing and vertical
            // room so the selected card can lift and flip without being
            // clipped by the row.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(ShepherdAchievement.allCases.enumerated()), id: \.element.id) { index, achievement in
                        AchievementBadge(
                            achievement: achievement,
                            title: title(for: achievement),
                            isEarned: earned.contains(achievement),
                            fraction: achievement.fraction(progress),
                            isSelected: achievement == selectedAchievement,
                            // The same hand-placed tilts as the passport's milestones.
                            tilt: [-2.0, 1.5, -1.0, 2.0, -1.5, 1.0][index % 6]
                        ) {
                            withAnimation(.snappy) { selectedAchievement = achievement }
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 4)
            }
            .sensoryFeedback(.selection, trigger: selectedAchievement)
        }
    }

    private func title(for achievement: ShepherdAchievement) -> String {
        let remote = achievementInfo[achievement.rawValue]?.title ?? ""
        return remote.isEmpty ? achievement.title : remote
    }
}

/// One badge, drawn with the same collectible card face as the passport's
/// Milestones (`FeatCardFace`) so the two read as one family. Scaled down to
/// sit in a row; tapping turns the card over.
private struct AchievementBadge: View {
    let achievement: ShepherdAchievement
    let title: String
    let isEarned: Bool
    let fraction: Double
    let isSelected: Bool
    let tilt: Double
    let onSelect: () -> Void

    private var feat: Feat {
        let color: Color
        let rarity: FeatRarity
        switch achievement {
        case .firstLetter: color = .orange; rarity = .common
        case .sealBroken: color = .red; rarity = .common
        case .tenKilometres: color = .teal; rarity = .rare
        case .hundredKilometres: color = .indigo; rarity = .legendary
        case .oceanCrossing: color = .blue; rarity = .rare
        case .fullPasture: color = .purple; rarity = .legendary
        }
        return Feat(id: achievement.rawValue, symbol: achievement.symbolName,
                    title: LocalizedStringKey(title),
                    earnedLine: achievement.localizedCaption, lockedLine: achievement.localizedCaption,
                    targetMeters: nil, isEarned: isEarned, color: color, rarity: rarity,
                    progress: fraction)
    }

    @State private var isFlipped = false

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) { isFlipped.toggle() }
            onSelect()
        } label: {
            // The same double-sided card as the passport's milestones: tap
            // to turn it over, tap again to turn it back. The name and the
            // story are on the back; nothing is repeated under the card.
            FlippingCard(angle: isFlipped ? 180 : 0) {
                FeatCardFace(feat: feat, totalMeters: 0, side: .front)
            } back: {
                FeatCardFace(feat: feat, totalMeters: 0, side: .back)
            }
            .frame(width: 156, height: 212)
            .rotationEffect(.degrees(tilt))
            .scaleEffect(isSelected ? 1.04 : 1)
            .animation(.spring(duration: 0.35, bounce: 0.45), value: isSelected)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: isFlipped)
        .accessibilityLabel("\(title), \(isEarned ? "earned" : "\(Int(fraction * 100)) percent")")
        .accessibilityValue(achievement.caption)
        .accessibilityHint("Turns the card over")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A card that turns over. The angle is animatable, and the face drawn
/// follows it — front up to the edge-on midpoint, back after, pre-mirrored
/// so its text reads the right way round. Drawing one face at a time (rather
/// than stacking both and fading) means the back can never be hidden behind
/// the picture.
private struct FlippingCard<Front: View, Back: View>: View, Animatable {
    var angle: Double
    @ViewBuilder let front: () -> Front
    @ViewBuilder let back: () -> Back

    init(angle: Double, @ViewBuilder front: @escaping () -> Front, @ViewBuilder back: @escaping () -> Back) {
        self.angle = angle
        self.front = front
        self.back = back
    }

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        ZStack {
            if angle < 90 {
                front()
            } else {
                back().rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
    }
}

#Preview("Signed in") {
    ShepherdsBoardCard(
        experiencePoints: 1_240,
        progress: .init(ramsDispatched: 3, lettersDelivered: 1, metresWalked: 24_000, handoffsMade: 0, mostRamsAtOnce: 2),
        isAuthenticated: true,
        isLoading: false,
        scope: .constant(.everyone),
        topEntries: [
            LeaderboardRow(id: "a", rank: 1, displayName: "Marta", score: 4_120, isLocalPlayer: false),
            LeaderboardRow(id: "b", rank: 2, displayName: "Teo", score: 2_300, isLocalPlayer: false),
            LeaderboardRow(id: "c", rank: 3, displayName: "Ivy", score: 1_900, isLocalPlayer: false),
        ],
        localEntry: LeaderboardRow(id: "me", rank: 7, displayName: "Anton", score: 1_240, isLocalPlayer: true),
        totalPlayers: 42,
        onSignInTapped: {}
    )
    .padding()
}

#Preview("Signed out") {
    ShepherdsBoardCard(
        experiencePoints: 0,
        progress: .init(ramsDispatched: 0, lettersDelivered: 0, metresWalked: 0, handoffsMade: 0, mostRamsAtOnce: 0),
        isAuthenticated: false,
        isLoading: false,
        scope: .constant(.everyone),
        topEntries: [],
        localEntry: nil,
        totalPlayers: 0,
        onSignInTapped: {}
    )
    .padding()
}
