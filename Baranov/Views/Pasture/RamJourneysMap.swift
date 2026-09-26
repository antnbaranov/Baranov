//
//  RamJourneysMap.swift
//  Baranov
//
//  The passport as a map: every journey this ram has ever walked, drawn
//  as a line between the places it was stamped, with each stamp's own
//  symbol at its place. Chips above the map pick "All journeys" or one of
//  them; the camera frames what is showing. Numbers under it — journeys,
//  places, distance — are the same figures the passport already keeps.
//
//  Past journeys only remember where they were stamped, so their lines run
//  stamp to stamp (great-circle); the journey still in flight also shows
//  its planned road, dashed. Native `Map`, system materials, semantic
//  styles — no gradients, no glow.
//

import MapKit
import SwiftUI

/// One journey out of a ram's stamps: from a `.setOut` stamp to whatever
/// came last (usually an `.arrival`).
struct RamJourney: Identifiable, Hashable {
    let id: UUID
    let number: Int
    let stamps: [JourneyStamp]

    var origin: String { stamps.first?.placeName ?? "" }
    var destination: String { stamps.last?.placeName ?? "" }
    var isFinished: Bool { stamps.last?.kind == .arrival }
    var date: Date? { stamps.first?.timestamp }
    var coordinates: [CLLocationCoordinate2D] {
        stamps.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// Splits a ram's whole stamp collection into journeys: a new one
    /// starts at every "set out" stamp, oldest first.
    static func journeys(from stamps: [JourneyStamp]) -> [RamJourney] {
        var groups: [[JourneyStamp]] = []
        for stamp in stamps.sorted(by: { $0.timestamp < $1.timestamp }) {
            if stamp.kind == .setOut || groups.isEmpty {
                groups.append([stamp])
            } else {
                groups[groups.count - 1].append(stamp)
            }
        }
        return groups.enumerated().map { index, group in
            RamJourney(id: group[0].id, number: index + 1, stamps: group)
        }
    }
}

struct RamJourneysMap: View {
    let ramName: String
    let stamps: [JourneyStamp]
    /// The road of the journey still in flight, if any (dashed).
    let plannedRoute: [CLLocationCoordinate2D]
    let totalMeters: Int

    @Environment(\.dismissPasture) private var dismissPasture
    @State private var selectedId: UUID?
    @State private var camera: MapCameraPosition = .automatic

    private static let palette: [Color] = [.orange, .blue, .green, .purple, .pink, .teal]

    private var journeys: [RamJourney] { RamJourney.journeys(from: stamps) }

    private var visibleJourneys: [RamJourney] {
        guard let selectedId else { return journeys }
        return journeys.filter { $0.id == selectedId }
    }

    private var placeCount: Int {
        Set(stamps.map { $0.placeName.lowercased() }).count
    }

    private func color(for journey: RamJourney) -> Color {
        Self.palette[(journey.number - 1) % Self.palette.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if stamps.isEmpty {
                emptyState
            } else {
                chips
                map
                statsRow
            }
        }
        .onAppear { frameVisibleJourneys() }
        .onChange(of: selectedId) { frameVisibleJourneys() }
        .onChange(of: stamps.count) { frameVisibleJourneys() }
    }

    // MARK: - Pieces

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No journeys yet. Send a letter and \(ramName)'s route will be drawn here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                dismissPasture()
            } label: {
                Label("Send a letter", systemImage: "paperplane.fill")
            }
            .buttonStyle(ShareCodeGlassButtonStyle(tint: PastureTheme.green, expands: true))
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: String(localized: "All journeys"), tint: .primary, isSelected: selectedId == nil) {
                    selectedId = nil
                }
                ForEach(journeys) { journey in
                    chip(
                        title: "\(journey.number) · \(journey.origin) → \(journey.destination)",
                        tint: color(for: journey),
                        isSelected: selectedId == journey.id
                    ) {
                        selectedId = (selectedId == journey.id) ? nil : journey.id
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedId)
    }

    private func chip(title: String, tint: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(title)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? AnyShapeStyle(Color.primary.opacity(0.14)) : AnyShapeStyle(.thinMaterial), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var map: some View {
        Map(position: $camera) {
            if plannedRoute.count > 1 {
                MapPolyline(coordinates: plannedRoute)
                    .stroke(Color.orange.opacity(0.45),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 6]))
            }
            ForEach(visibleJourneys) { journey in
                journeyContent(journey)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityLabel("Map of \(ramName)'s journeys")
    }

    @MapContentBuilder
    private func journeyContent(_ journey: RamJourney) -> some MapContent {
        let tint = color(for: journey)
        if journey.stamps.count > 1 {
            MapPolyline(coordinates: journey.coordinates, contourStyle: .geodesic)
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        ForEach(journey.stamps) { stamp in
            Annotation(stamp.placeName,
                       coordinate: CLLocationCoordinate2D(latitude: stamp.latitude, longitude: stamp.longitude),
                       anchor: .center) {
                stampGlyph(stamp, tint: tint)
            }
            .annotationTitles(stamp.kind == .setOut || stamp.kind == .arrival ? .visible : .hidden)
        }
    }

    private func stampGlyph(_ stamp: JourneyStamp, tint: Color) -> some View {
        let isEnd = stamp.kind == .setOut || stamp.kind == .arrival
        return Image(systemName: stamp.kind.symbolName)
            .font(.system(size: isEnd ? 13 : 10, weight: .semibold))
            .foregroundStyle(isEnd ? Color.white : tint)
            .frame(width: isEnd ? 30 : 22, height: isEnd ? 30 : 22)
            .background(isEnd ? AnyShapeStyle(tint) : AnyShapeStyle(.regularMaterial), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: isEnd ? 2 : 1))
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat(value: "\(journeys.count)", label: journeys.count == 1 ? "journey" : "journeys")
            Divider().frame(height: 28)
            stat(value: "\(placeCount)", label: placeCount == 1 ? "place" : "places")
            Divider().frame(height: 28)
            stat(value: DistanceFormatter.string(forMeters: totalMeters), label: "walked")
        }
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func stat(value: String, label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Camera

    private func frameVisibleJourneys() {
        var points = visibleJourneys.flatMap(\.coordinates)
        if selectedId == nil { points += plannedRoute }
        guard let rect = Self.rect(framing: points) else { return }
        withAnimation(.smooth(duration: 0.6)) {
            camera = .rect(rect)
        }
    }

    /// A map rect around the points, padded so nothing sits on the edge
    /// and never so tight that a single place is a street-level zoom.
    private static func rect(framing points: [CLLocationCoordinate2D]) -> MKMapRect? {
        guard !points.isEmpty else { return nil }
        var rect = MKMapRect.null
        for point in points {
            let mapPoint = MKMapPoint(point)
            rect = rect.union(MKMapRect(x: mapPoint.x, y: mapPoint.y, width: 0, height: 0))
        }
        let minSpan = MKMapPointsPerMeterAtLatitude(points[0].latitude) * 4_000
        let width = max(rect.size.width * 1.4, minSpan)
        let height = max(rect.size.height * 1.4, minSpan)
        return MKMapRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }
}
