//
//  JourneyStamp.swift
//  Baranov
//
//  One mark in a ram's passport: proof it actually passed through a real,
//  named place on its way somewhere. Stamps are earned by walking, never
//  awarded for opening a screen — `JourneyView` appends one the moment a
//  ram's accumulated steps carry it past a landmark `NextLandmarkService`
//  resolved ahead on the polyline, and `FlockViewModel` appends one when a
//  leg actually completes.
//
//  Stamps live on the `Ram` while a journey is in flight (so they travel
//  with it through an AirDrop handoff, exactly like `passengerLetters`),
//  and are folded into the ram's name-keyed `RamLedgerEntry` when the
//  letter is delivered — that's what makes a passport a lifetime
//  collection rather than a single journey's log.
//

import Foundation

/// What kind of place a stamp commemorates. Drives only the stamp's
/// symbol and wording — every kind is earned the same way.
enum JourneyStampKind: String, Codable, Hashable, Sendable {
    /// The place the ram set out from.
    case setOut
    /// A named town/city passed along the way.
    case town
    /// A river, lake, strait or coastline crossed.
    case water
    /// A pass, ridge, park or other named area of interest.
    case landmark
    /// A border/ocean gap where the ram waited for a handoff.
    case handoff
    /// The recipient's gate — the end of the whole journey.
    case arrival

    var symbolName: String {
        switch self {
        case .setOut: return "pawprint.fill"
        case .town: return "building.2.fill"
        case .water: return "water.waves"
        case .landmark: return "signpost.right.fill"
        case .handoff: return "airplane.departure"
        case .arrival: return "flag.checkered"
        }
    }

    /// The small line printed under a stamp's place name.
    var caption: String {
        switch self {
        case .setOut: return "Set out"
        case .town: return "Passed through"
        case .water: return "Crossed"
        case .landmark: return "Passed"
        case .handoff: return "Handed over"
        case .arrival: return "Arrived"
        }
    }
}

/// A single passport stamp.
struct JourneyStamp: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let placeName: String
    let kind: JourneyStampKind
    let latitude: Double
    let longitude: Double
    /// How many steps into the *whole journey* this stamp was earned —
    /// kept so a passport can be read in order even after several legs.
    let stepsAtStamp: Int
    /// Who was actually carrying the ram when it passed here. Not always
    /// the ram's own name: after a handoff, the person who walked this
    /// stretch is a different carrier entirely.
    let carrierName: String
    let timestamp: Date
    /// The weather where and when this stamp was earned, if the device was
    /// online at that moment. Optional and never back-filled: a stamp from
    /// before this existed, or earned offline, simply has none — Codable
    /// decodes the missing key as nil, so old passports still load.
    var weather: StampWeather?

    init(
        id: UUID = UUID(),
        placeName: String,
        kind: JourneyStampKind,
        latitude: Double,
        longitude: Double,
        stepsAtStamp: Int,
        carrierName: String,
        timestamp: Date = Date(),
        weather: StampWeather? = nil
    ) {
        self.id = id
        self.placeName = placeName
        self.kind = kind
        self.latitude = latitude
        self.longitude = longitude
        self.stepsAtStamp = stepsAtStamp
        self.carrierName = carrierName
        self.timestamp = timestamp
        self.weather = weather
    }
}

/// A frozen reading of the sky, saved on the stamp. Stored as plain values
/// (not WeatherKit types) so it is `Sendable`, tiny, and readable offline.
struct StampWeather: Codable, Hashable, Sendable {
    /// Localized condition name, e.g. "Light Rain".
    let condition: String
    /// An SF Symbol name.
    let symbolName: String
    let temperatureCelsius: Double
    /// Whether it was actually wet — drives the "Rain Walker" patch.
    let isWet: Bool
}
