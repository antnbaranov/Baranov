//
//  PassportGoalCard.swift
//  Baranov
//
//  The cards for milestones the person wrote themselves: a dashed "New
//  Milestone" card that opens the writing sheet, and the flip-able card for
//  each goal. Front: the goal in big type. Back: how to finish it, and once
//  it is done — Make Reel and Share.
//

import SwiftUI
import UIKit

extension RamGoal {
    var cardColor: Color {
        let palette: [Color] = [.orange, .pink, .indigo, .teal, .green, .purple]
        return palette[Int(StableSeed.value(for: id) % UInt64(palette.count))]
    }
}

// MARK: - New card

struct NewGoalCard: View {
    var body: some View {
        VStack(spacing: 12) {
            // The same Liquid Glass as every other button in the app.
            // Same glass as the reel's play button: accent tint, white glyph.
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .liquidGlass(in: Circle(), tint: Color.accentColor,
                             interactive: false, fallbackMaterial: .regularMaterial)
            Text("Write a Milestone")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
            Text("Say what has to happen")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 156, height: 212)
        .background(PassportInk.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Goal card

struct GoalCard: View {
    let goal: RamGoal
    let totalMeters: Int
    let isFlipped: Bool
    let shareImage: UIImage?
    let onDone: () -> Void
    let onReel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack {
            GoalCardFace(goal: goal, totalMeters: totalMeters, side: .front)
                .opacity(isFlipped ? 0 : 1)
            GoalCardFace(goal: goal, totalMeters: totalMeters, side: .back,
                         shareImage: shareImage, onDone: onDone, onReel: onReel, onDelete: onDelete)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)
                .allowsHitTesting(isFlipped)
        }
        .frame(width: 156, height: 212)
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
    }
}

struct GoalCardFace: View {
    enum Side { case front, back }

    let goal: RamGoal
    let totalMeters: Int
    let side: Side
    var shareImage: UIImage?
    var onDone: () -> Void = {}
    var onReel: () -> Void = {}
    var onDelete: () -> Void = {}

    private var isDone: Bool { goal.isDone(totalMeters: totalMeters) }
    private var fill: Color { isDone ? goal.cardColor.calmed() : Color(uiColor: .systemGray4) }
    private var textColor: Color { isDone ? .white : .primary }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(fill)
            switch side {
            case .front: front
            case .back: back
            }
        }
    }

    /// Same anatomy as the built-in feat cards (chip on top, big round
    /// symbol, title at the bottom) so the whole row reads as one deck.
    private var front: some View {
        VStack(spacing: 0) {
            HStack {
                Text("YOURS")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(isDone ? 0.28 : 0.5), in: Capsule())
                Spacer()
                if !isDone {
                    Image(systemName: "lock.fill").font(.caption.weight(.bold))
                }
            }
            .foregroundStyle(isDone ? Color.white : Color.secondary)

            Spacer()

            ZStack {
                Circle().fill(.white.opacity(isDone ? 0.22 : 0.45))
                    .frame(width: 80, height: 80)
                Image(systemName: isDone ? "flag.checkered" : "flag.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(isDone ? Color.white : Color.secondary)
            }

            Spacer()

            Text(goal.title)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(3, reservesSpace: true)
                .minimumScaleFactor(0.75)
                .foregroundStyle(isDone ? Color.white : Color.primary)

            if !isDone, let progress = goal.progress(totalMeters: totalMeters) {
                ProgressView(value: progress)
                    .tint(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding(14)
    }

    private var back: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isDone {
                Text(goal.completedAt == nil
                    ? String(localized: "Walked it out.", bundle: .appLanguage, locale: .appLanguage)
                    : String(localized: "It happened!", bundle: .appLanguage, locale: .appLanguage))
                    .scaledFont(size: 15, weight: .heavy, design: .rounded)
                Text(goal.completedAt.map { String(localized: "Ticked off \($0.formatted(.dateTime.day().month(.abbreviated).locale(.appLanguage))).", bundle: .appLanguage, locale: .appLanguage) }
                     ?? String(localized: "The steps added up on their own.", bundle: .appLanguage, locale: .appLanguage))
                    .scaledFont(size: 14, weight: .semibold, design: .serif)
                    .italic()
                Spacer(minLength: 0)
                Button(action: onReel) {
                    Label("Make reel", systemImage: "play.circle.fill")
                        .font(.footnote.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.28), in: Capsule())
                }
                .buttonStyle(.plain)
                if let shareImage {
                    ShareLink(
                        item: Image(uiImage: shareImage),
                        preview: SharePreview("Milestone", image: Image(uiImage: shareImage))
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.footnote.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.28), in: Capsule())
                    }
                }
            } else {
                Text("Not yet…")
                    .scaledFont(size: 15, weight: .heavy, design: .rounded)
                if let toGo = goal.metersToGo(totalMeters: totalMeters) {
                    Text("\(DistanceFormatter.string(forMeters: toGo)) to go, or tap when it happens.")
                        .scaledFont(size: 14, weight: .semibold, design: .serif)
                        .italic()
                } else {
                    Text("Tap when it happens. The ram will be insufferable.")
                        .scaledFont(size: 14, weight: .semibold, design: .serif)
                        .italic()
                }
                Spacer(minLength: 0)
                Button(action: onDone) {
                    Label("It happened!", systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(goal.cardColor.calmed(), in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Button(action: onReel) {
                    Label("Make reel", systemImage: "play.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            Button(role: .destructive, action: onDelete) {
                Text("Delete")
                    .font(.caption2.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .opacity(0.7)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(textColor)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
