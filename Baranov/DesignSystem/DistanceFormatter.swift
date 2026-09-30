//
//  DistanceFormatter.swift
//  Baranov
//
//  Displays a ram's real-world travel distance the way a person actually
//  thinks about it (km/m, locale-aware) instead of a bare step count. The
//  number behind it is never a guess: `RouteService` resolves every leg as
//  a real MapKit driving route, so the meters fed in here are the same
//  meters the ram is actually walking along real roads.
//

import Foundation

enum DistanceFormatter {
    /// The `@AppStorage` key the Settings segmented picker (`PastureView`)
    /// writes to — "km" or "mi". Read directly here (rather than via a
    /// property wrapper, since this is a static formatter, not a view)
    /// so every distance readout in the app picks it up without each
    /// call site having to plumb the preference through itself.
    static let unitStorageKey = "distanceUnit"

    /// No preference saved yet (first launch, before Settings is ever
    /// touched) falls back to the locale's own convention — the same
    /// behavior this formatter had before the setting existed — rather
    /// than silently defaulting to kilometers everywhere.
    private static var preferredUnit: UnitLength {
        switch UserDefaults.standard.string(forKey: unitStorageKey) {
        case "mi": return .miles
        case "km": return .kilometers
        default: return Locale.current.measurementSystem == .metric ? .kilometers : .miles
        }
    }

    private static func formatter(for unit: UnitLength) -> MeasurementFormatter {
        let formatter = MeasurementFormatter()
        // The app's language, not the phone's: "3,2 км", not "3.2 km".
        formatter.locale = .appLanguage
        // `.providedUnit` is what makes this respect the person's chosen
        // unit — without it, `MeasurementFormatter` is free to convert
        // back to whatever its own locale-driven "natural" unit is,
        // which is exactly what made a manual km/mi toggle pointless.
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter
    }

    /// Formats a real distance, in meters, as a human string such as
    /// "3.2 km" or "2 mi" — the same road-distance convention Apple's
    /// own Maps app uses, in whichever unit the person picked in
    /// Settings.
    static func string(forMeters meters: Int) -> String {
        let unit = preferredUnit
        let measurement = Measurement(value: Double(max(meters, 0)), unit: UnitLength.meters)
            .converted(to: unit)
        return formatter(for: unit).string(from: measurement)
    }
}
