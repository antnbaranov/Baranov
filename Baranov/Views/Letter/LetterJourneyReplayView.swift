//
//  LetterJourneyReplayView.swift
//  Baranov
//
//  "How it travelled": under the passport in an opened letter, a small
//  replay of the road. The route inks itself in on a map, the ram runs
//  along it, every stop pops up as it is reached with the sky it was
//  stamped under, and a chain of hands underneath shows who carried the
//  letter and where they handed it on.
//
//  Everything here comes from the passport stamps the ram already carries
//  (place, carrier, time, weather), so it works offline, costs no extra
//  WeatherKit calls and needs nothing from a server. The map is a single
//  MapKit snapshot; the route, pins and ram are plain SwiftUI drawn over it
//  as a pure function of time, like the reel.
//

import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - Weather text shared by notes, milestones and the replay

extension StampWeather {
    var temperatureText: String {
        Measurement(value: temperatureCelsius.rounded(), unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow).locale(.appLanguage))
    }

    /// "Light Rain · 11°".
    var summaryLine: String { "\(condition) · \(temperatureText)" }
}

// MARK: - Data

struct ReplayStop: Identifiable {
    let id: UUID
    /// What the caption says: "Passed through · Hope", "Handed to Klaus".
    let title: String
    let kind: JourneyStampKind
    let carrier: String
    let weather: StampWeather?
    /// Where the stop sits on the snapshot, in the snapshot's own points.
    let point: CGPoint
    /// How far along the route (0…1) the ram is when it reaches this stop.
    let fraction: Double
}

struct ReplayMap {
    let image: UIImage
    let size: CGSize
    let stops: [ReplayStop]

    /// The point a given fraction of the way along the route.
    func point(at fraction: Double) -> CGPoint {
        let f = min(max(fraction, 0), 1)
        guard stops.count > 1 else { return stops.first?.point ?? .zero }
        for index in 1..<stops.count where f <= stops[index].fraction {
            let a = stops[index - 1], b = stops[index]
            let span = max(b.fraction - a.fraction, 0.0001)
            let local = (f - a.fraction) / span
            return CGPoint(x: a.point.x + (b.point.x - a.point.x) * local,
                           y: a.point.y + (b.point.y - a.point.y) * local)
        }
        return stops.last?.point ?? .zero
    }

    /// The last stop the ram has reached by `fraction`.
    func currentStop(at fraction: Double) -> ReplayStop? {
        stops.last { $0.fraction <= fraction + 0.0001 } ?? stops.first
    }
}

enum ReplayMapBuilder {
    static let size = CGSize(width: 640, height: 400)
    static let maxStops = 12

    /// Stamps with a real place, oldest first.
    static func usable(_ stamps: [JourneyStamp]) -> [JourneyStamp] {
        stamps
            .filter { !($0.latitude == 0 && $0.longitude == 0) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// At most `maxStops` stops, always keeping the first, the last and
    /// every handoff: the people are the point of this replay.
    private static func sampled(_ stamps: [JourneyStamp]) -> [JourneyStamp] {
        guard stamps.count > maxStops else { return stamps }
        var keep = Set<Int>([0, stamps.count - 1])
        for (index, stamp) in stamps.enumerated() where stamp.kind == .handoff { keep.insert(index) }
        let remaining = max(0, maxStops - keep.count)
        if remaining > 0 {
            let step = Double(stamps.count - 1) / Double(remaining + 1)
            for slot in 1...remaining { keep.insert(Int((Double(slot) * step).rounded())) }
        }
        return keep.sorted().prefix(maxStops).map { stamps[$0] }
    }

    private static func title(for stamp: JourneyStamp) -> String {
        if stamp.kind == .handoff { return stamp.displayPlaceName }
        return "\(stamp.kind.caption) · \(stamp.shortPlaceName)"
    }

    @MainActor
    static func build(stamps: [JourneyStamp]) async -> ReplayMap? {
        let chosen = sampled(usable(stamps))
        guard chosen.count >= 2 else { return nil }
        let coordinates = chosen.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }

        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        let minExtent = 3_000 * MKMapPointsPerMeterAtLatitude(coordinates[0].latitude)
        var width = max(rect.size.width * 1.5, minExtent)
        var height = max(rect.size.height * 1.5, minExtent)
        let aspect = size.width / size.height
        if width / height < aspect { width = height * aspect } else { height = width / aspect }
        let framed = MKMapRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)

        // Projected by hand, so the stops land in the right place whether
        // or not the snapshot itself could be taken.
        let points = coordinates.map { coordinate -> CGPoint in
            let p = MKMapPoint(coordinate)
            return CGPoint(x: (p.x - framed.minX) / framed.width * size.width,
                           y: (p.y - framed.minY) / framed.height * size.height)
        }

        var image: UIImage?
        let options = MKMapSnapshotter.Options()
        options.mapRect = framed
        options.size = size
        options.scale = 2
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        if let snapshot = try? await MKMapSnapshotter(options: options).start() { image = snapshot.image }
        let background = image ?? UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemGray5.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }

        // Every stop gets a little time on screen, even two stamps earned at the same spot.
        var lengths: [Double] = []
        for index in 1..<points.count {
            let dx = Double(points[index].x - points[index - 1].x)
            let dy = Double(points[index].y - points[index - 1].y)
            lengths.append((dx * dx + dy * dy).squareRoot())
        }
        let rawTotal = max(lengths.reduce(0, +), 1)
        let minimum = rawTotal * 0.06
        let padded = lengths.map { max($0, minimum) }
        let total = padded.reduce(0, +)

        var cumulative = 0.0
        var stops: [ReplayStop] = []
        for (index, stamp) in chosen.enumerated() {
            if index > 0 { cumulative += padded[index - 1] }
            stops.append(ReplayStop(
                id: stamp.id, title: title(for: stamp), kind: stamp.kind, carrier: stamp.carrierName,
                weather: stamp.weather, point: points[index], fraction: cumulative / total
            ))
        }
        return ReplayMap(image: background, size: size, stops: stops)
    }
}

// MARK: - View

struct LetterJourneyReplayView: View {
    let stamps: [JourneyStamp]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var map: ReplayMap?
    @State private var startedAt: Date?
    @State private var isFinished = false

    private let lead: TimeInterval = 0.5

    private var stopCount: Int { ReplayMapBuilder.usable(stamps).count }

    /// Longer roads take a little longer, never less than 6 s or more than 14 s.
    private var duration: TimeInterval { min(14, max(6, Double(min(stopCount, ReplayMapBuilder.maxStops)) * 1.6)) }

    var body: some View {
        if stopCount >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let map {
                    TimelineView(.animation(paused: isFinished || startedAt == nil)) { context in
                        let progress = progress(at: context.date)
                        VStack(alignment: .leading, spacing: 12) {
                            canvas(map, progress: progress)
                            caption(map, progress: progress)
                            chain(map, progress: progress)
                        }
                    }
                    if map.stops.contains(where: { $0.weather != nil }) {
                        WeatherAttributionView()
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .task {
                guard map == nil else { return }
                map = await ReplayMapBuilder.build(stamps: stamps)
                replay()
            }
            .task(id: startedAt) {
                guard startedAt != nil else { return }
                try? await Task.sleep(for: .seconds(lead + duration + 0.3))
                guard !Task.isCancelled else { return }
                isFinished = true
            }
        }
    }

    private var header: some View {
        HStack {
            JournalHeading(title: "How it travelled", symbol: "point.topleft.down.to.point.bottomright.curvepath")
            Spacer()
            if map != nil {
                Button(action: replay) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .liquidGlass(in: Circle(), interactive: true, fallbackMaterial: .regularMaterial)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Replay")
            }
        }
    }

    private func replay() {
        isFinished = false
        startedAt = Date()
    }

    private func progress(at date: Date) -> Double {
        if reduceMotion { return 1 }
        guard let startedAt else { return 0 }
        let raw = (date.timeIntervalSince(startedAt) - lead) / duration
        let clamped = min(1, max(0, raw))
        // Ease in and out, so the ram leaves and arrives gently.
        return clamped < 0.5 ? 2 * clamped * clamped : 1 - pow(-2 * clamped + 2, 2) / 2
    }

    // MARK: Map

    private func canvas(_ map: ReplayMap, progress: Double) -> some View {
        Image(uiImage: map.image)
            .resizable()
            .aspectRatio(map.size.width / map.size.height, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    let scale = proxy.size.width / map.size.width
                    ZStack {
                        Canvas { context, _ in
                            var whole = Path()
                            var walked = Path()
                            for (index, stop) in map.stops.enumerated() {
                                let point = CGPoint(x: stop.point.x * scale, y: stop.point.y * scale)
                                if index == 0 {
                                    whole.move(to: point)
                                    walked.move(to: point)
                                } else {
                                    whole.addLine(to: point)
                                    if stop.fraction <= progress { walked.addLine(to: point) }
                                }
                            }
                            let head = map.point(at: progress)
                            walked.addLine(to: CGPoint(x: head.x * scale, y: head.y * scale))
                            context.stroke(whole, with: .color(.primary.opacity(0.25)),
                                           style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 6]))
                            context.stroke(walked, with: .color(Color.wax),
                                           style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                        }

                        ForEach(map.stops) { stop in
                            pin(stop, reached: progress >= stop.fraction - 0.0001)
                                .position(x: stop.point.x * scale, y: stop.point.y * scale)
                        }

                        let head = map.point(at: progress)
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Color.wax, in: Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .position(x: head.x * scale, y: head.y * scale)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement()
            .accessibilityLabel("Map of the letter's journey")
    }

    private func pin(_ stop: ReplayStop, reached: Bool) -> some View {
        let isHandoff = stop.kind == .handoff
        return Image(systemName: isHandoff ? "person.2.fill" : stop.kind.symbolName)
            .font(.system(size: isHandoff ? 11 : 9, weight: .bold))
            .foregroundStyle(reached ? Color.white : Color.secondary)
            .frame(width: isHandoff ? 26 : 20, height: isHandoff ? 26 : 20)
            .background(reached ? Color.wax : Color(uiColor: .systemGray4), in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .scaleEffect(reached ? 1 : 0.6)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: reached)
    }

    // MARK: Caption

    private func caption(_ map: ReplayMap, progress: Double) -> some View {
        let stop = map.currentStop(at: progress)
        return VStack(alignment: .leading, spacing: 4) {
            if let stop {
                Label {
                    Text(verbatim: stop.title)
                } icon: {
                    Image(systemName: stop.kind == .handoff ? "person.2.fill" : stop.kind.symbolName)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                if let weather = stop.weather {
                    Label {
                        Text(verbatim: weather.summaryLine)
                    } icon: {
                        Image(systemName: weather.symbolName).symbolRenderingMode(.hierarchical)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: stop?.id)
    }

    // MARK: Chain of hands

    /// Everyone who carried it, in order, joined by the hand-overs.
    private func chain(_ map: ReplayMap, progress: Double) -> some View {
        var carriers: [String] = []
        for stop in map.stops {
            let name = stop.carrier.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, carriers.last != name { carriers.append(name) }
        }
        let current = map.currentStop(at: progress)?.carrier.trimmingCharacters(in: .whitespacesAndNewlines)
        return Group {
            if carriers.count >= 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Who carried it")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(carriers.enumerated()), id: \.offset) { index, name in
                                if index > 0 {
                                    Image(systemName: "arrow.right")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.tertiary)
                                }
                                carrierChip(name, isActive: name == current)
                            }
                        }
                    }
                }
            }
        }
    }

    private func carrierChip(_ name: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: String(name.prefix(1)).uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .frame(width: 22, height: 22)
                .background(isActive ? Color.wax : Color(uiColor: .systemGray5), in: Circle())
            Text(verbatim: name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.trailing, 10)
        .padding(.leading, 4)
        .padding(.vertical, 4)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}
