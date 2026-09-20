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

struct ShepherdsBoardCard: View {
    let experiencePoints: Int
    let progress: ShepherdAchievement.Progress
    let isAuthenticated: Bool
    let isLoading: Bool
    let topEntries: [LeaderboardRow]
    let localEntry: LeaderboardRow?
    let totalPlayers: Int
    let onSignInTapped: () -> Void

    @State private var earnedTick = 0

    private var earned: Set<ShepherdAchievement> {
        Set(ShepherdAchievement.earned(progress))
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
                    .font(.system(size: 34, weight: .bold, design: .rounded))
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
                    Text(isAuthenticated ? "Not ranked yet" : "Not signed in")
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
        if !isAuthenticated {
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
        } else if topEntries.isEmpty {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(isLoading ? "Fetching the board…" : "The board is empty — be the first shepherd on it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
                                        .delay(Double(index) * 0.05)),
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
            HStack {
                Text("Badges")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(earned.count) of \(ShepherdAchievement.allCases.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(ShepherdAchievement.allCases) { achievement in
                        AchievementBadge(
                            achievement: achievement,
                            isEarned: earned.contains(achievement),
                            fraction: achievement.fraction(progress)
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

/// One badge: a ring that fills toward the goal, a tinted disc once
/// earned, the title underneath. Tapping it explains what it's for.
private struct AchievementBadge: View {
    let achievement: ShepherdAchievement
    let isEarned: Bool
    let fraction: Double

    @State private var showsCaption = false

    var body: some View {
        Button {
            withAnimation(.snappy) { showsCaption.toggle() }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: isEarned ? 1 : fraction)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: fraction)
                    Circle()
                        .fill(isEarned ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.thinMaterial))
                        .padding(6)
                    Image(systemName: achievement.symbolName)
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isEarned ? Color.white : Color.secondary)
                        .symbolEffect(.bounce, value: isEarned)
                }
                .frame(width: 58, height: 58)

                Text(showsCaption ? achievement.localizedCaption : achievement.localizedTitle)
                    .font(.caption2.weight(isEarned ? .semibold : .regular))
                    .foregroundStyle(isEarned ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(showsCaption ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: showsCaption ? 170 : 74)
                    .contentTransition(.opacity)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(achievement.title), \(isEarned ? "earned" : "\(Int(fraction * 100)) percent")")
        .accessibilityHint(achievement.caption)
    }
}

#Preview("Signed in") {
    ShepherdsBoardCard(
        experiencePoints: 1_240,
        progress: .init(ramsDispatched: 3, lettersDelivered: 1, metresWalked: 24_000, handoffsMade: 0, mostRamsAtOnce: 2),
        isAuthenticated: true,
        isLoading: false,
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
        topEntries: [],
        localEntry: nil,
        totalPlayers: 0,
        onSignInTapped: {}
    )
    .padding()
}
