//
//  RamReelMap.swift
//  Baranov
//
//  The "where has it actually been" beat of the reel: a real map of the
//  ram's stamped places, snapshotted once with MapKit and then drawn over
//  frame by frame (the route inking itself in, the ram running along it,
//  each place popping up as it is reached). MapKit's live `Map` cannot be
//  rendered into a video, but a snapshot can — and the route, pins and ram
//  are ordinary SwiftUI on top, so the beat stays a pure function of time.
//
//  Needs at least two stamps with real coordinates; otherwise the reel
//  simply keeps its hills.
//

import CoreLocation
import MapKit
import UIKit

struct ReelPlace: Sendable {
    let name: String
    let latitude: Double
    let longitude: Double
}

struct RamReelMap {
    struct Pin: Identifiable {
        let id = UUID()
        let name: String
        /// How far along the route (0…1) the ram is when it reaches this place.
        let fraction: Double
        let point: CGPoint
    }

    let image: UIImage
    let points: [CGPoint]
    let pins: [Pin]
    /// Cumulative fraction of the route at each point.
    private let cumulative: [Double]

    fileprivate init(image: UIImage, points: [CGPoint], names: [String]) {
        self.image = image
        self.points = points

        var lengths: [Double] = [0]
        for index in 1..<points.count {
            let dx = Double(points[index].x - points[index - 1].x)
            let dy = Double(points[index].y - points[index - 1].y)
            lengths.append(lengths[index - 1] + (dx * dx + dy * dy).squareRoot())
        }
        let total = max(lengths.last ?? 1, 1)
        cumulative = lengths.map { $0 / total }
        pins = zip(points.indices, names).map { index, name in
            Pin(name: name, fraction: lengths[index] / total, point: points[index])
        }
    }

    /// The point a given fraction of the way along the route.
    func point(at fraction: Double) -> CGPoint {
        let f = min(max(fraction, 0), 1)
        for index in 1..<points.count where f <= cumulative[index] {
            let span = max(cumulative[index] - cumulative[index - 1], 0.0001)
            let local = (f - cumulative[index - 1]) / span
            let a = points[index - 1], b = points[index]
            return CGPoint(x: a.x + (b.x - a.x) * local, y: a.y + (b.y - a.y) * local)
        }
        return points.last ?? .zero
    }
}

enum RamReelMapBuilder {
    /// A portrait snapshot framing every place, or `nil` when there are
    /// fewer than two places or the snapshot fails (offline with no cached
    /// tiles, say) — the reel then just skips this beat.
    @MainActor
    static func build(places: [ReelPlace]) async -> RamReelMap? {
        // Drop places with no real coordinate, and collapse consecutive repeats.
        var kept: [ReelPlace] = []
        for place in places where !(place.latitude == 0 && place.longitude == 0) {
            if let last = kept.last, abs(last.latitude - place.latitude) < 0.0005, abs(last.longitude - place.longitude) < 0.0005 { continue }
            kept.append(place)
        }
        guard kept.count >= 2 else { return nil }
        // Keep the reel readable: at most 6 stops, always including the first and last.
        if kept.count > 6 {
            let step = Double(kept.count - 1) / 5
            kept = (0..<6).map { kept[Int((Double($0) * step).rounded())] }
        }

        let coordinates = kept.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let size = CGSize(width: 360, height: 640)

        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        // Padding, a minimum extent, and the reel's portrait aspect ratio.
        let minExtent = 4_000 * MKMapPointsPerMeterAtLatitude(coordinates[0].latitude)
        var width = max(rect.size.width * 1.7, minExtent)
        var height = max(rect.size.height * 1.7, minExtent)
        let aspect = size.width / size.height
        if width / height < aspect { width = height * aspect } else { height = width / aspect }
        let framed = MKMapRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)

        let options = MKMapSnapshotter.Options()
        options.mapRect = framed
        options.size = size
        options.scale = 2
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration

        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            let points = coordinates.map { snapshot.point(for: $0) }
            return RamReelMap(image: snapshot.image, points: points, names: kept.map(\.name))
        } catch {
            return nil
        }
    }
}
