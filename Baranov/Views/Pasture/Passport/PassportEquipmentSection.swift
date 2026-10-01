//
//  PassportEquipmentSection.swift
//  Baranov
//
//  "Hoof Feats": the ram's lifetime milestones, deliberately silly and
//  deliberately not the Shepherd's Board — that one is about you and Game
//  Center; this one is about the ram's own bragging rights.
//
//  - A fun-fact line that turns the distance walked into something you can
//    picture (giraffes end to end, Eiffel Towers…). Tap it for the next
//    comparison.
//  - A grid of feats: absurd distance landmarks and odd jobs the stamps
//    prove. Tap any feat for its punchline, and how far is left if it is
//    still locked.
//
//  Everything is computed from the ledger and the stamps.
//

import SwiftUI
import UIKit

// MARK: - Fun facts

enum DistanceComparison: CaseIterable {
    case bananas, ramLengths, giraffes, footballFields, eiffelTowers, seawalls, marathons

    var meters: Double {
        switch self {
        case .bananas: 0.2
        case .ramLengths: 1.2
        case .giraffes: 5.5
        case .footballFields: 100
        case .eiffelTowers: 330
        case .seawalls: 8_800
        case .marathons: 42_195
        }
    }

    func sentence(for totalMeters: Int) -> String {
        let count = Double(totalMeters) / meters
        let number = count.formatted(.number.precision(.fractionLength(count < 10 ? 1 : 0)).locale(.appLanguage))
        switch self {
        case .bananas: return String(localized: "That is \(number) bananas in a row. Peels not included.", bundle: .appLanguage, locale: .appLanguage)
        case .ramLengths: return String(localized: "That is \(number) rams nose to tail. Nobody is cutting in line.", bundle: .appLanguage, locale: .appLanguage)
        case .giraffes: return String(localized: "That is \(number) giraffes lying nose to tail.", bundle: .appLanguage, locale: .appLanguage)
        case .footballFields: return String(localized: "That is \(number) football fields, and not a single touchdown.", bundle: .appLanguage, locale: .appLanguage)
        case .eiffelTowers: return String(localized: "That is \(number) Eiffel Towers laid flat. Very flat.", bundle: .appLanguage, locale: .appLanguage)
        case .seawalls: return String(localized: "That is \(number) laps of the Stanley Park seawall.", bundle: .appLanguage, locale: .appLanguage)
        case .marathons: return String(localized: "That is \(number) marathons. On four legs. Showing off.", bundle: .appLanguage, locale: .appLanguage)
        }
    }

    /// The comparisons that read well for this distance: at least a tenth
    /// of the unit, and not an absurd pile of them. Never empty.
    static func reachable(for totalMeters: Int) -> [DistanceComparison] {
        let meters = Double(totalMeters)
        let fitting = allCases.filter {
            let count = meters / $0.meters
            return count >= 0.1 && count <= 5_000
        }
        return fitting.isEmpty ? allCases : fitting
    }
}

// MARK: - Feats

struct Feat: Identifiable {
    let id: String
    let symbol: String
    let title: LocalizedStringKey
    let earnedLine: LocalizedStringKey
    let lockedLine: LocalizedStringKey
    /// Distance feats know how far away they are; odd jobs do not.
    let targetMeters: Int?
    let isEarned: Bool
    let color: Color
    let rarity: FeatRarity
    /// Overrides the distance-based progress (used by the Shepherd's Board badges).
    var progress: Double? = nil
}

enum FeatRarity {
    case common, rare, legendary

    var label: LocalizedStringKey {
        switch self {
        case .common: "COMMON"
        case .rare: "RARE"
        case .legendary: "LEGENDARY"
        }
    }
}

struct PassportEquipmentSection: View {
    let ramID: UUID
    let ramName: String
    let totalMeters: Int
    let lettersDelivered: Int
    let stamps: [JourneyStamp]

    @State private var shownComparison: DistanceComparison?
    @State private var muse = LetterMuseService()
    @State private var modelLine: String?
    @State private var zeroIndex = 0
    @State private var isWritingLine = false
    @State private var flippedId: String?
    @State private var comparisonTapTick = 0
    @State private var flipTick = 0
    @State private var shareImages: [String: UIImage] = [:]
    @State private var isReelPresented = false
    @State private var goalStore = RamGoalStore()
    @State private var isWritingGoal = false
    @State private var reelGoal: RamGoal?
    @State private var goalShareImages: [UUID: UIImage] = [:]
    @State private var goalTick = 0

    private var reachableComparisons: [DistanceComparison] {
        DistanceComparison.reachable(for: totalMeters)
    }

    /// The one on screen. Tracked by value, not by position, so the list
    /// growing as steps come in can never leave a tap pointing at the
    /// same sentence.
    private var comparison: DistanceComparison {
        let options = reachableComparisons
        if let shownComparison, options.contains(shownComparison) { return shownComparison }
        return options.last ?? .giraffes
    }

    /// Three hand-written lines for a ram that has not moved yet.
    private var zeroLines: [String] {
        [
            String(localized: "\(ramName) has not gone anywhere yet. Suspiciously relaxed.", bundle: .appLanguage, locale: .appLanguage),
            String(localized: "0 m so far. \(ramName) is still deciding which foot goes first.", bundle: .appLanguage, locale: .appLanguage),
            String(localized: "Not one step yet. The grass here is apparently excellent.", bundle: .appLanguage, locale: .appLanguage),
        ]
    }

    /// What the card says right now: the model's line if it wrote one,
    /// otherwise the current preset.
    private var currentLine: String {
        if let modelLine { return modelLine }
        if totalMeters <= 0 { return zeroLines[zeroIndex % zeroLines.count] }
        return comparison.sentence(for: totalMeters)
    }

    /// With Apple's on-device model: a fresh line each tap. Without it:
    /// cycle the three presets (or the reachable comparisons past 0 m).
    private func nextComparison() {
        guard !isWritingLine else { return }
        if LetterMuseService.isSupported {
            isWritingLine = true
            Task {
                let fresh = await muse.compare(ramName: ramName, totalMeters: totalMeters, avoiding: currentLine)
                isWritingLine = false
                if let fresh {
                    withAnimation(.snappy) { modelLine = fresh }
                    flipTick += 1
                } else {
                    advancePreset()
                }
            }
        } else {
            advancePreset()
        }
    }

    private func advancePreset() {
        withAnimation(.snappy) {
            modelLine = nil
            if totalMeters <= 0 {
                zeroIndex = (zeroIndex + 1) % zeroLines.count
            } else {
                let options = reachableComparisons
                if options.count > 1, let index = options.firstIndex(of: comparison) {
                    shownComparison = options[(index + 1) % options.count]
                }
            }
        }
        flipTick += 1
    }

    private var feats: [Feat] {
        let places = Set(stamps.map { $0.placeName.lowercased() }).count
        let calendar = Calendar.current
        let night = stamps.contains {
            let hour = calendar.component(.hour, from: $0.timestamp)
            return hour >= 21 || hour < 5
        }
        func distance(_ id: String, _ symbol: String, _ title: LocalizedStringKey, _ meters: Int,
                      _ color: Color, earned: LocalizedStringKey, locked: LocalizedStringKey) -> Feat {
            Feat(id: id, symbol: symbol, title: title, earnedLine: earned, lockedLine: locked,
                 targetMeters: meters, isEarned: totalMeters >= meters, color: color,
                 rarity: meters >= 42_195 ? .legendary : (meters >= 2_000 ? .rare : .common))
        }
        return [
            distance("barn", "door.left.hand.open", "Left the Barn", 100, .orange,
                     earned: "Hooves have officially left the building.",
                     locked: "Step one: get past the barn door."),
            distance("tower", "building.columns", "Tall Order", 330, .pink,
                     earned: "Walked the height of the Eiffel Tower. Sideways.",
                     locked: "The Eiffel Tower is waiting. It is not going anywhere."),
            distance("bridge", "road.lanes", "Bridge Over Fluffy Water", 2_737, .red,
                     earned: "Golden Gate Bridge, done. No toll for rams.",
                     locked: "A very long bridge is waiting for you."),
            distance("everest", "mountain.2.fill", "Everest, But Flat", 8_849, .indigo,
                     earned: "Walked the height of Everest without any of the cold.",
                     locked: "Everest, but flat. Bring snacks."),
            distance("marathon", "figure.run", "The Baa-thon", 42_195, .purple,
                     earned: "A whole marathon. No medal. Only pride, and clover.",
                     locked: "42.2 km. The finish line has a clover buffet."),
            distance("whistler", "snowflake", "All the Way to Whistler", 120_000, .cyan,
                     earned: "Vancouver to Whistler on hoof. Skis not included.",
                     locked: "Far, far up the Sea to Sky. Keep trotting."),
            Feat(id: "first", symbol: "envelope.fill", title: "Mail Call",
                 earnedLine: "Delivered a letter. Now insufferable about it.",
                 lockedLine: "Deliver one letter and the bragging begins.",
                 targetMeters: nil, isEarned: lettersDelivered >= 1, color: .green, rarity: .common),
            Feat(id: "night", symbol: "moon.stars.fill", title: "Night Owl Ram",
                 earnedLine: "Out after dark. Spooky. Fluffy. Still on time.",
                 lockedLine: "Earn a stamp after nightfall.",
                 targetMeters: nil, isEarned: night, color: .indigo, rarity: .rare),
            Feat(id: "rain", symbol: "cloud.rain.fill", title: "Soggy Wool",
                 earnedLine: "Wool: soaked. Spirit: undefeated.",
                 lockedLine: "Earn a stamp in the rain.",
                 targetMeters: nil, isEarned: stamps.contains { $0.weather?.isWet == true }, color: .blue, rarity: .rare),
            Feat(id: "water", symbol: "water.waves", title: "Not a Fan of Water",
                 earnedLine: "Crossed water anyway. Has opinions about it.",
                 lockedLine: "Cross a river, lake or sea.",
                 targetMeters: nil, isEarned: stamps.contains { $0.kind == .water }, color: .teal, rarity: .rare),
            Feat(id: "relay", symbol: "hand.wave.fill", title: "Pass the Hoof",
                 earnedLine: "Handed over mid-journey. Passed the baton, kept the dignity.",
                 lockedLine: "Hand the ram to someone at a border or coast.",
                 targetMeters: nil, isEarned: stamps.contains { $0.kind == .handoff }, color: .mint, rarity: .rare),
            Feat(id: "wayfarer", symbol: "signpost.right.fill", title: "Professional Tourist",
                 earnedLine: "Three different places stamped. Bought no souvenirs.",
                 lockedLine: "Collect stamps from three different places.",
                 targetMeters: nil, isEarned: places >= 3, color: .brown, rarity: .common),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            JournalHeading(title: "Milestones", symbol: "trophy.fill")
            reelCard
            funFact
            weatherFunFact
            deck
            // Apple Weather mark and legal link, as WeatherKit requires.
            WeatherAttributionView()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard()
        .sensoryFeedback(.selection, trigger: flipTick)
        .sensoryFeedback(.success, trigger: goalTick)
        .sheet(isPresented: $isReelPresented, onDismiss: { reelGoal = nil }) {
            RamReelSheet(base: reelData)
        }
        .sheet(isPresented: $isWritingGoal) {
            PassportGoalSheet(ramName: ramName, weather: latestWeather) { title, kilometers in
                goalStore.add(title: title, kilometers: kilometers, ramID: ramID, currentMeters: totalMeters)
            }
        }
    }

    /// The sky on the newest stamp that recorded one.
    private var latestWeather: StampWeather? {
        stamps.sorted { $0.timestamp < $1.timestamp }.compactMap(\.weather).last
    }

    // MARK: Reel

    private var reelData: RamReelData {
        var data = RamReelData.make(ramName: ramName, totalMeters: totalMeters, lettersDelivered: lettersDelivered, stamps: stamps)
        if let reelGoal {
            data.goal = reelGoal.title
            data.goalDone = reelGoal.isDone(totalMeters: totalMeters)
        }
        return data
    }

    /// The hero: a live, looping preview of the ram's shareable reel.
    private var reelCard: some View {
        let previewData = reelData
        let open = {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            isReelPresented = true
        }
        return HStack(alignment: .top, spacing: 14) {
            Button(action: open) {
                // Frozen while the reel sheet is up or a reel is rendering:
                // this preview redrawing every frame behind the export is
                // what used to make the whole app stutter. The data is built
                // once per body, not once per animation frame.
                TimelineView(.animation(paused: isReelPresented || ReelJobStore.shared.isRunning)) { context in
                    RamReelScene(
                        data: previewData,
                        time: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: RamReelSpec.duration)
                    )
                    .scaleEffect(0.30, anchor: .topLeading)
                    .frame(width: RamReelSpec.size.width * 0.30, height: RamReelSpec.size.height * 0.30, alignment: .topLeading)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(ramName)'s reel")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("A twelve-second reel to share.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                ReelCardButton(ramName: ramName, action: open)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(PassportInk.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: Fun fact

    private var funFact: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DistanceFormatter.string(forMeters: totalMeters))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(currentLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(isWritingLine ? 0.4 : 1)
                .id(currentLine)
                .transition(.opacity)
            // Icon-only, round and glassy — the same shape language as
            // the reel's play button (`RamReelSheet`), so "there's more
            // here, tap it" reads the same everywhere in the passport.
            Button {
                comparisonTapTick += 1
                nextComparison()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .liquidGlass(in: Circle(), fallbackMaterial: .regularMaterial)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: comparisonTapTick)
            .disabled(isWritingLine)
            .accessibilityLabel("Tap for another comparison")
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(PassportInk.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Weather fun fact

    /// Every stamp that happened to get a WeatherKit reading, oldest first.
    /// WeatherKit is best-effort and budget-capped, so this can be empty —
    /// that's a normal, silent state, not an error.
    private var weatherReadings: [StampWeather] {
        stamps.compactMap(\.weather)
    }

    /// A symbol and one sentence summarizing every reading collected so
    /// far, or `nil` until there is at least one. Favors a wet symbol when
    /// any stop was wet, since that's the more memorable detail.
    private var weatherSummary: (symbol: String, sentence: String)? {
        guard !weatherReadings.isEmpty else { return nil }
        let temps = weatherReadings.map(\.temperatureCelsius)
        guard let coldest = temps.min(), let warmest = temps.max() else { return nil }
        let wetCount = weatherReadings.filter(\.isWet).count
        let symbol = weatherReadings.last(where: { $0.isWet })?.symbolName ?? weatherReadings.last!.symbolName

        func degrees(_ celsius: Double) -> String {
            Measurement(value: celsius.rounded(), unit: UnitTemperature.celsius)
                .formatted(.measurement(width: .narrow).locale(.appLanguage))
        }

        let sentence: String
        if coldest == warmest {
            sentence = wetCount > 0
                ? String(localized: "One reading so far: \(degrees(coldest)), rain along the way.", bundle: .appLanguage, locale: .appLanguage)
                : String(localized: "One reading so far: \(degrees(coldest)).", bundle: .appLanguage, locale: .appLanguage)
        } else if wetCount > 0 {
            sentence = wetCount == 1
                ? String(localized: "From \(degrees(coldest)) to \(degrees(warmest)) — one stop caught in the rain.", bundle: .appLanguage, locale: .appLanguage)
                : String(localized: "From \(degrees(coldest)) to \(degrees(warmest)) — \(wetCount) stops caught in the rain.", bundle: .appLanguage, locale: .appLanguage)
        } else {
            sentence = String(localized: "From \(degrees(coldest)) to \(degrees(warmest)), dry the whole way.", bundle: .appLanguage, locale: .appLanguage)
        }
        return (symbol, sentence)
    }

    /// Renders nothing until at least one stamp has a real WeatherKit
    /// reading — never a placeholder or a loading state.
    @ViewBuilder
    private var weatherFunFact: some View {
        if let weatherSummary {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: weatherSummary.symbol)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .frame(width: 28)
                Text(weatherSummary.sentence)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(weatherSummary.sentence)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(PassportInk.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .animation(.easeInOut(duration: 0.25), value: weatherSummary.sentence)
        }
    }

    // MARK: Deck

    /// A stack of collectible cards you flip: the front is the trophy, the
    /// back is the punchline (and, once earned, a Share button that posts
    /// the card as a picture).
    private var deck: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                Button {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    isWritingGoal = true
                } label: {
                    NewGoalCard()
                }
                .buttonStyle(.plain)

                ForEach(Array(goalStore.goals(for: ramID).enumerated()), id: \.element.id) { index, goal in
                    let key = goal.id.uuidString
                    GoalCard(
                        goal: goal,
                        totalMeters: totalMeters,
                        isFlipped: flippedId == key,
                        shareImage: goalShareImages[goal.id],
                        onDone: {
                            goalStore.markDone(goal, weather: latestWeather)
                            goalTick += 1
                            renderShareImage(for: goal)
                        },
                        onReel: {
                            reelGoal = goal
                            isReelPresented = true
                        },
                        onDelete: {
                            withAnimation(.snappy) {
                                flippedId = nil
                                goalStore.delete(goal)
                            }
                        }
                    )
                    .rotationEffect(.degrees([1.5, -2.0, 1.0, -1.5, 2.0, -1.0][index % 6]))
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                            flippedId = flippedId == key ? nil : key
                        }
                        flipTick += 1
                        if goal.isDone(totalMeters: totalMeters), goalShareImages[goal.id] == nil { renderShareImage(for: goal) }
                    }
                    .accessibilityAddTraits(.isButton)
                }

                ForEach(Array(feats.enumerated()), id: \.element.id) { index, feat in
                    FeatCard(
                        feat: feat,
                        totalMeters: totalMeters,
                        isFlipped: flippedId == feat.id,
                        shareImage: shareImages[feat.id]
                    )
                    .rotationEffect(.degrees([-2.0, 1.5, -1.0, 2.0, -1.5, 1.0][index % 6]))
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                            flippedId = flippedId == feat.id ? nil : feat.id
                        }
                        flipTick += 1
                        if feat.isEarned, shareImages[feat.id] == nil { renderShareImage(for: feat) }
                    }
                    .accessibilityAddTraits(.isButton)
                }
            }
            .padding(.vertical, 8)
        }
        .contentMargins(.horizontal, 26, for: .scrollContent)
        .scrollIndicators(.hidden)
        .padding(.horizontal, -18)
    }

    @MainActor private func renderShareImage(for goal: RamGoal) {
        let renderer = ImageRenderer(content:
            VStack(spacing: 14) {
                GoalCardFace(goal: goal, totalMeters: totalMeters, side: .front)
                    .frame(width: 312, height: 424)
                Text("Baranov · letters that walk")
                    .scaledFont(size: 15, weight: .heavy, design: .rounded)
                    .foregroundStyle(Color(red: 0.20, green: 0.13, blue: 0.08).opacity(0.7))
            }
            .padding(24)
            .background(Color(red: 1.0, green: 0.94, blue: 0.82))
        )
        renderer.scale = 3
        if let image = renderer.uiImage { goalShareImages[goal.id] = image }
    }

    @MainActor private func renderShareImage(for feat: Feat) {
        let renderer = ImageRenderer(content:
            VStack(spacing: 14) {
                FeatCardFace(feat: feat, totalMeters: totalMeters, side: .front)
                    .frame(width: 312, height: 424)
                Text("Baranov · letters that walk")
                    .scaledFont(size: 15, weight: .heavy, design: .rounded)
                    .foregroundStyle(Color(red: 0.20, green: 0.13, blue: 0.08).opacity(0.7))
            }
            .padding(24)
            .background(Color(red: 1.0, green: 0.94, blue: 0.82))
        )
        renderer.scale = 3
        if let image = renderer.uiImage { shareImages[feat.id] = image }
    }
}

// MARK: - Card

enum CardSide { case front, back }

private struct FeatCard: View {
    let feat: Feat
    let totalMeters: Int
    let isFlipped: Bool
    let shareImage: UIImage?

    var body: some View {
        ZStack {
            FeatCardFace(feat: feat, totalMeters: totalMeters, side: .front)
                .opacity(isFlipped ? 0 : 1)
            FeatCardFace(feat: feat, totalMeters: totalMeters, side: .back, shareImage: shareImage)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)
        }
        .frame(width: 156, height: 212)
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
    }
}

struct FeatCardFace: View {
    let feat: Feat
    let totalMeters: Int
    let side: CardSide
    var shareImage: UIImage?

    private var fill: Color { feat.isEarned ? feat.color.calmed() : Color(uiColor: .systemGray4) }

    private var progress: Double {
        if let override = feat.progress { return override }
        guard let target = feat.targetMeters else { return feat.isEarned ? 1 : 0 }
        return min(1, Double(totalMeters) / Double(target))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous).fill(fill)
            switch side {
            case .front: front
            case .back: back
            }
        }
    }

    /// Just the picture: the symbol, a lock while it is still unearned and
    /// its progress. The name and the story are on the back — flip the card.
    private var front: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if !feat.isEarned {
                    Image(systemName: "lock.fill").font(.caption.weight(.bold))
                        .foregroundStyle(Color.secondary)
                }
            }
            .frame(height: 18)

            Spacer()

            ZStack {
                Circle().fill(.white.opacity(feat.isEarned ? 0.22 : 0.45))
                    .frame(width: 104, height: 104)
                Image(systemName: feat.symbol)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(feat.isEarned ? Color.white : Color.secondary)
            }

            Spacer()

            if !feat.isEarned, feat.targetMeters != nil || feat.progress != nil {
                ProgressView(value: progress)
                    .tint(.secondary)
            } else {
                Color.clear.frame(height: 4)
            }
        }
        .padding(14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(feat.title))
    }

    private var back: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(feat.title)
                .scaledFont(size: 15, weight: .heavy, design: .rounded)
            Text(feat.isEarned ? feat.earnedLine : feat.lockedLine)
                .scaledFont(size: 16, weight: .semibold, design: .serif)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if feat.isEarned {
                if let shareImage {
                    ShareLink(
                        item: Image(uiImage: shareImage),
                        preview: SharePreview("Hoof Feat", image: Image(uiImage: shareImage))
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.footnote.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.28), in: Capsule())
                    }
                }
            } else if let target = feat.targetMeters {
                Text("\(DistanceFormatter.string(forMeters: max(0, target - totalMeters))) to go")
                    .font(.footnote.weight(.bold))
            }
        }
        .foregroundStyle(feat.isEarned ? Color.white : Color.primary)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// The reel card's one action: a Liquid Glass capsule in the accent colour
/// (play, then a progress ring while it renders, then share). It watches the
/// reel job on its own so the rest of the passport doesn't redraw as
/// progress ticks by.
private struct ReelCardButton: View {
    let ramName: String
    let action: () -> Void
    private var job: ReelJobStore { .shared }

    private var isThisRam: Bool { job.ramName == ramName }

    var body: some View {
        Button(action: tap) {
            Group {
                if isThisRam, job.phase == .writing || job.phase == .rendering {
                    ProgressView(value: job.phase == .rendering ? job.progress : nil)
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(.white)
                } else if isThisRam, job.phase == .ready {
                    Image(systemName: "square.and.arrow.up")
                } else if isThisRam, job.phase == .failed {
                    Image(systemName: "arrow.clockwise")
                } else {
                    Image(systemName: "play.fill")
                }
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 64, height: 40)
            .liquidGlass(in: Capsule(style: .continuous), tint: Color.accentColor)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isThisRam && job.phase == .ready ? "Share reel" : "Play reel")
    }

    private func tap() {
        if isThisRam, job.phase == .ready, let url = job.videoURL {
            let message = job.data?.shareMessage
                ?? String(localized: "Made with Baranov, letters that walk: \(AppLinks.appStore.absoluteString)", bundle: .appLanguage, locale: .appLanguage)
            ActivitySharer.present(items: [url, message])
        } else {
            action()
        }
    }
}
