//
//  Ram.swift
//  Baranov
//
//  A single virtual carrier ram: the flock member walking a letter's route.
//  Owned and mutated by `FlockViewModel`; `RouteNode` legs accumulate in
//  `routeHistory` as the ram's progress is resolved, and `letter` carries
//  the encrypted payload it's transporting.
//
//  A ram's journey is walked one leg at a time. `routeCoordinates` is the
//  real, road-following path (from `RouteService`/MapKit) for the CURRENT
//  leg only, running from `currentCity` to `legDestinationCity`. When
//  `legDestinationCity` differs from `targetCity`, the leg ends at a
//  handoff point, not the letter's true destination — an ocean or border
//  the ram can't cross on its own — and `requiresHandoffAtLegEnd` is what
//  tells `FlockViewModel` to stop there and wait for another person to
//  carry it onward, rather than pretending it can swim.
//

import CoreLocation
import Foundation

/// Lifecycle of a single carrier ram's journey.
enum RamStatus: String, Codable, Hashable, Sendable, CaseIterable {
    /// At rest in the pasture; not yet dispatched.
    case grazing
    /// Actively accumulating real-world steps toward its current leg.
    case walking
    /// Step quota met (or handoff forced early); waiting for a foreground
    /// AirDrop handoff at a border/ocean crossing.
    case waitingForHandoff
    /// Booked onto a packet and crossing water no road spans. Its position
    /// is a function of the clock, not of anyone's steps — see `SeaVoyage`.
    case atSea
    /// Passed to another carrier. The ram is kept on this device as
    /// history (its passport and the letter's fate stay visible) but it
    /// walks on nobody's steps here and no longer holds a pasture slot.
    case handedOff
    /// Reached the recipient's gate; the wax seal has not yet been broken.
    case arrivedAtGate
    /// The letter has been revealed and the journey archived.
    case delivered

    var displayName: String {
        switch self {
        case .grazing: return "Grazing"
        case .walking: return "Walking"
        case .waitingForHandoff: return "At the Port"
        case .atSea: return "At Sea"
        case .handedOff: return "Handed On"
        case .arrivedAtGate: return "At the Gate"
        case .delivered: return "Delivered"
        }
    }

    var symbolName: String {
        switch self {
        case .grazing: return "pawprint"
        case .walking: return "figure.walk"
        case .waitingForHandoff: return "ferry"
        case .atSea: return "sailboat"
        case .handedOff: return "hand.wave"
        case .arrivedAtGate: return "flag.checkered"
        case .delivered: return "checkmark.seal.fill"
        }
    }
}

/// A single virtual carrier ram and the letter it is transporting.
struct Ram: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var status: RamStatus
    /// Steps recorded toward `totalStepsRequired` for the ram's current leg
    /// (1 step = 1 meter, per `StepTrackerService`).
    var stepsWalked: Int
    /// The real driving distance, in meters, for the CURRENT leg only —
    /// resolved by `RouteService`, not a straight-line guess.
    var totalStepsRequired: Int
    /// The city this leg started walking from. Updated only when a leg
    /// completes (including after a handoff) — the ram's live position
    /// mid-leg is `currentCoordinate`, not this.
    var currentCity: String
    /// The letter's true, final destination city — unchanged across
    /// however many handoffs the journey actually needs.
    var targetCity: String
    /// Where the CURRENT leg ends: equal to `targetCity` when the whole
    /// remaining journey is drivable in one leg, or an intermediate
    /// handoff city when an ocean/border gap requires one.
    var legDestinationCity: String
    /// Legs already resolved and logged as the ram's progress advances.
    var routeHistory: [RouteNode]
    /// The real, road-following path for the current leg only, from
    /// `currentCity` to `legDestinationCity`.
    var routeCoordinates: [RamCoordinate]
    /// Whether reaching the step quota for this leg should hand the ram to
    /// `.waitingForHandoff` (a gap remains before `targetCity`) rather than
    /// `.arrivedAtGate` (this leg's end IS the final destination).
    var requiresHandoffAtLegEnd: Bool
    /// The encrypted letter this ram is carrying, once drafted.
    var letter: Letter?
    /// Other people's letters picked up along the way — via the "Receive
    /// a Letter…" import in Pasture, when this ram was already out
    /// walking toward its own `targetCity` and the incoming letter's ram
    /// wasn't already tracked locally. Carried alongside `letter`, toward
    /// this ram's own single destination, without spending a separate
    /// pasture slot on a whole new tracked ram. AirDrops with this ram
    /// (`RamTransitPackage` just wraps `Ram` as-is), so passengers travel
    /// with it automatically through any further hand-off.
    var passengerLetters: [Letter] = []
    /// The ram's passport: every real, named place it has actually walked
    /// past on this journey. Carried on the `Ram` itself (not a side
    /// store) so stamps survive an AirDrop handoff along with everything
    /// else, and folded into the name-keyed `RamLedgerEntry` on delivery.
    var stamps: [JourneyStamp] = []
    /// The crossing this ram is booked onto, if any: set the moment it
    /// reaches a port with water in front of it, cleared when it makes
    /// land on the far side. Non-nil while `.waitingForHandoff` means the
    /// packet is booked but has not cast off yet — the ram is on the quay
    /// and a person can still take it instead.
    var voyage: SeaVoyage?
    /// `targetCity`'s coordinate, persisted so a later leg — after a
    /// handoff — can be resolved without re-geocoding the destination
    /// city name, which could resolve differently a second time.
    var finalDestinationCoordinate: RamCoordinate

    init(
        id: UUID = UUID(),
        name: String,
        status: RamStatus = .grazing,
        stepsWalked: Int = 0,
        totalStepsRequired: Int,
        currentCity: String,
        targetCity: String,
        legDestinationCity: String? = nil,
        routeHistory: [RouteNode] = [],
        routeCoordinates: [RamCoordinate] = [],
        requiresHandoffAtLegEnd: Bool = false,
        letter: Letter? = nil,
        passengerLetters: [Letter] = [],
        stamps: [JourneyStamp] = [],
        voyage: SeaVoyage? = nil,
        finalDestinationCoordinate: RamCoordinate
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.stepsWalked = stepsWalked
        self.totalStepsRequired = totalStepsRequired
        self.currentCity = currentCity
        self.targetCity = targetCity
        self.legDestinationCity = legDestinationCity ?? targetCity
        self.routeHistory = routeHistory
        self.routeCoordinates = routeCoordinates
        self.requiresHandoffAtLegEnd = requiresHandoffAtLegEnd
        self.letter = letter
        self.passengerLetters = passengerLetters
        self.stamps = stamps
        self.voyage = voyage
        self.finalDestinationCoordinate = finalDestinationCoordinate
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, status, stepsWalked, totalStepsRequired, currentCity
        case targetCity, legDestinationCity, routeHistory, routeCoordinates
        case requiresHandoffAtLegEnd, letter, passengerLetters, stamps
        case voyage
        case finalDestinationCoordinate
    }

    /// A hand-written decode rather than the synthesized one, for the same
    /// reason `Letter` has one: a `.ram` transit package written by an
    /// older build of the app has no `passengerLetters`/`stamps` key at
    /// all, and the synthesized decoder would reject the whole package
    /// over a missing key — meaning a real letter someone AirDropped from
    /// an older install would simply fail to arrive. Every field added
    /// after the original wire format is decoded leniently, defaulting to
    /// empty, so an old package still lands.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        status = try container.decode(RamStatus.self, forKey: .status)
        stepsWalked = try container.decode(Int.self, forKey: .stepsWalked)
        totalStepsRequired = try container.decode(Int.self, forKey: .totalStepsRequired)
        currentCity = try container.decode(String.self, forKey: .currentCity)
        targetCity = try container.decode(String.self, forKey: .targetCity)
        legDestinationCity = try container.decode(String.self, forKey: .legDestinationCity)
        routeHistory = try container.decode([RouteNode].self, forKey: .routeHistory)
        routeCoordinates = try container.decode([RamCoordinate].self, forKey: .routeCoordinates)
        requiresHandoffAtLegEnd = try container.decode(Bool.self, forKey: .requiresHandoffAtLegEnd)
        letter = try container.decodeIfPresent(Letter.self, forKey: .letter)
        passengerLetters = try container.decodeIfPresent([Letter].self, forKey: .passengerLetters) ?? []
        stamps = try container.decodeIfPresent([JourneyStamp].self, forKey: .stamps) ?? []
        voyage = try container.decodeIfPresent(SeaVoyage.self, forKey: .voyage)
        finalDestinationCoordinate = try container.decode(RamCoordinate.self, forKey: .finalDestinationCoordinate)
    }

    var progress: Double {
        // At sea the clock, not the pedometer, is what moves the ram — so
        // every progress bar in the app reads the crossing instead of a
        // step quota that is frozen for the duration of the voyage.
        if status == .atSea, let voyage {
            return voyage.progress()
        }
        guard totalStepsRequired > 0 else { return 0 }
        return min(1.0, Double(stepsWalked) / Double(totalStepsRequired))
    }

    /// Whether this ram's next move is the packet's, not the carrier's:
    /// it is standing on a quay with a booked departure, or already out on
    /// the water. Views use this to stop asking the person to walk.
    var isAwaitingOrAtSea: Bool {
        status == .atSea || (status == .waitingForHandoff && voyage != nil)
    }

    var remainingSteps: Int {
        max(0, totalStepsRequired - stepsWalked)
    }

    /// Total steps walked across every leg already logged plus the one in
    /// progress — what a passport stamp records, so stamps stay in order
    /// across a journey that took several handoffs rather than each leg
    /// restarting the count from zero.
    var journeyStepsSoFar: Int {
        routeHistory.reduce(0) { $0 + $1.stepsContributed } + stepsWalked
    }

    /// Whether this ram already carries a stamp for a place — stamping is
    /// driven by a live step stream that can fire repeatedly around the
    /// same spot, so every awarding path checks here first rather than
    /// letting a passport fill up with the same town six times.
    func hasStamp(named placeName: String) -> Bool {
        stamps.contains { $0.placeName.caseInsensitiveCompare(placeName) == .orderedSame }
    }

    /// The ram's live position along `routeCoordinates`, interpolated by
    /// how many meters of the current leg it has actually walked. This is
    /// what makes it move like a car tracing real streets instead of
    /// cutting a straight line toward the endpoint; `nil` only if no route
    /// has been resolved yet.
    var currentCoordinate: CLLocationCoordinate2D? {
        if status == .atSea, let voyage {
            return voyage.coordinate()
        }
        return Self.interpolatedPoint(along: routeCoordinates, metersWalked: Double(stepsWalked))?.coordinate
    }

    /// The coordinate a given number of meters along the current leg's
    /// polyline — the same interpolation `currentCoordinate` uses, but
    /// for an arbitrary point rather than only "where the ram is now".
    /// `NextLandmarkService` walks this forward to look at what's ahead
    /// on the road before the ram actually gets there.
    func coordinate(atMetersAlongRoute meters: Double) -> CLLocationCoordinate2D? {
        Self.interpolatedPoint(along: routeCoordinates, metersWalked: meters)?.coordinate
    }

    /// The compass bearing (0..<360) of the road segment the ram is
    /// currently on — orients its map marker like a moving car rather than
    /// pointing at the journey's overall endpoint.
    var currentBearingDegrees: Double? {
        if status == .atSea, let voyage {
            return voyage.bearingDegrees()
        }
        return Self.interpolatedPoint(along: routeCoordinates, metersWalked: Double(stepsWalked))?.bearing
    }

    /// How close (in metres) the recipient has to be to the spot where a
    /// letter was left before it can be picked up — GPS is good to tens of
    /// metres, and a gate is a place, not a doorstep.
    static let pickupRadiusMeters: CLLocationDistance = 150

    /// Where the letter is left when the ram reaches the gate: the end of
    /// the route it walked, falling back to the letter's final destination.
    var gateCoordinate: CLLocationCoordinate2D? {
        routeCoordinates.last?.clLocationCoordinate ?? finalDestinationCoordinate.clLocationCoordinate
    }

    /// Straight-line distance from a position to the gate, in metres.
    func distanceToGate(from position: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard let gate = gateCoordinate else { return nil }
        return CLLocation(latitude: position.latitude, longitude: position.longitude)
            .distance(from: CLLocation(latitude: gate.latitude, longitude: gate.longitude))
    }

    /// The exact first vertex of the current leg's polyline — where a
    /// freshly dispatched ram stands, and what `FlockViewModel.dispatch`
    /// guarantees `currentCoordinate` resolves to by forcing
    /// `stepsWalked` back to zero. Exposed separately so callers that need
    /// "the origin" (camera flyover, waypoint labels) never reach for an
    /// interpolated point that could drift off the vertex.
    var originCoordinate: CLLocationCoordinate2D? {
        routeCoordinates.first?.clLocationCoordinate
    }

    /// The bearing of the first real street segment — what the marker
    /// faces on frame 0, before a single step has landed. Skips any
    /// zero-length leading segments (MapKit polylines routinely repeat
    /// their first vertex), which is what previously made a just-
    /// dispatched ram face due north until it moved.
    var originBearingDegrees: Double? {
        Self.interpolatedPoint(along: routeCoordinates, metersWalked: 0)?.bearing
    }

    private struct RoutePoint {
        let coordinate: CLLocationCoordinate2D
        let bearing: Double?
    }

    private static func interpolatedPoint(along coordinates: [RamCoordinate], metersWalked: Double) -> RoutePoint? {
        guard let first = coordinates.first?.clLocationCoordinate else { return nil }
        guard coordinates.count > 1 else { return RoutePoint(coordinate: first, bearing: nil) }

        var remaining = max(0, metersWalked)

        for index in 0..<(coordinates.count - 1) {
            let start = coordinates[index].clLocationCoordinate
            let end = coordinates[index + 1].clLocationCoordinate
            let segmentLength = CLLocation(latitude: start.latitude, longitude: start.longitude)
                .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
            let isLastSegment = index == coordinates.count - 2

            if remaining <= segmentLength || isLastSegment {
                let fraction = segmentLength > 0 ? min(1, remaining / segmentLength) : 1
                let coordinate = CLLocationCoordinate2D(
                    latitude: start.latitude + (end.latitude - start.latitude) * fraction,
                    longitude: start.longitude + (end.longitude - start.longitude) * fraction
                )
                return RoutePoint(coordinate: coordinate, bearing: forwardBearing(along: coordinates, from: index))
            }

            remaining -= segmentLength
        }

        let last = coordinates[coordinates.count - 1].clLocationCoordinate
        return RoutePoint(coordinate: last, bearing: forwardBearing(along: coordinates, from: coordinates.count - 1))
    }

    /// The bearing of the road at segment `index`, looking forward along
    /// the polyline. A resolved `MKDirections` polyline often contains
    /// consecutive duplicate vertices (a zero-length segment); `atan2` of a
    /// zero vector is 0°, which would snap the marker to face north for a
    /// frame. So the bearing is taken from `coordinates[index]` to the
    /// next vertex that is actually somewhere else — and if none lies
    /// ahead, from the last distinct vertex behind, so the ram keeps its
    /// final heading at the leg's end rather than spinning.
    private static func forwardBearing(along coordinates: [RamCoordinate], from index: Int) -> Double? {
        let start = coordinates[index].clLocationCoordinate

        var next = index + 1
        while next < coordinates.count {
            let candidate = coordinates[next].clLocationCoordinate
            if candidate.latitude != start.latitude || candidate.longitude != start.longitude {
                return bearing(from: start, to: candidate)
            }
            next += 1
        }

        var previous = index - 1
        while previous >= 0 {
            let candidate = coordinates[previous].clLocationCoordinate
            if candidate.latitude != start.latitude || candidate.longitude != start.longitude {
                return bearing(from: candidate, to: start)
            }
            previous -= 1
        }
        return nil
    }

    /// Great-circle initial bearing from `from` to `to`, in degrees, 0..<360.
    private static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180

        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let degrees = atan2(y, x) * 180 / .pi

        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}


extension Ram {
    /// A ram with no journey behind it, standing in for the person's
    /// companion so its passport can open before any letter has walked.
    /// Marked delivered so nothing treats it as in flight, and given a
    /// fixed id so the goals and notes kept on its passport survive
    /// between visits.
    static func restingStub(for companion: RamCompanion) -> Ram {
        Ram(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE") ?? UUID(),
            name: companion.name,
            status: .delivered,
            totalStepsRequired: 0,
            currentCity: "",
            targetCity: "",
            finalDestinationCoordinate: RamCoordinate(latitude: 0, longitude: 0)
        )
    }
}
