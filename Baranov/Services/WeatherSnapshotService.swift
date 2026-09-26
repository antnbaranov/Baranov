//
//  WeatherSnapshotService.swift
//  Baranov
//
//  One reading of the sky for one stamp, taken at the moment the stamp is
//  earned. Offline-first: any failure (no network, no WeatherKit access,
//  simulator without an account) returns nil and the stamp simply has no
//  weather — nothing here can interrupt step recording or the UI.
//

import CoreLocation
import Foundation
import WeatherKit

enum WeatherSnapshotService {
    /// Apple's free WeatherKit tier is one shared pool of calls per month
    /// for the whole app, so every device gets a small, fixed share. A
    /// stamp is a rare event (a named place, not a step), so this is far
    /// more than a real walker needs, and it is what keeps the app inside
    /// the free tier as the user base grows.
    static let monthlyCallsPerDevice = 60

    /// A reading is reused for stamps earned close together in space and
    /// time — the sky does not change in a few kilometres or minutes.
    private static let reuseRadiusMeters: CLLocationDistance = 5_000
    private static let reuseWindow: TimeInterval = 30 * 60

    private static let countKey = "com.baranov.weather.callCount"
    private static let monthKey = "com.baranov.weather.callMonth"
    private static let cacheKey = "com.baranov.weather.lastReading"

    private struct CachedReading: Codable {
        let weather: StampWeather
        let latitude: Double
        let longitude: Double
        let date: Date
    }

    static func snapshot(at coordinate: CLLocationCoordinate2D) async -> StampWeather? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        // 1. Free: a recent reading from nearby.
        if let cached = cachedReading(near: location) { return cached }

        // 2. Only spend a call if this device still has budget this month.
        guard reserveCall() else { return nil }

        do {
            let current = try await WeatherService.shared.weather(for: location, including: .current)
            let weather = StampWeather(
                condition: current.condition.description,
                symbolName: current.symbolName,
                temperatureCelsius: current.temperature.converted(to: .celsius).value,
                isWet: isWet(current.condition)
            )
            store(weather, at: location)
            return weather
        } catch {
            return nil
        }
    }

    // MARK: - Budget

    /// Counts the call up front (a failed call still counts against
    /// Apple's quota). Resets when the calendar month changes.
    private static func reserveCall() -> Bool {
        let defaults = UserDefaults.standard
        let month = Date().formatted(.iso8601.year().month())
        if defaults.string(forKey: monthKey) != month {
            defaults.set(month, forKey: monthKey)
            defaults.set(0, forKey: countKey)
        }
        let used = defaults.integer(forKey: countKey)
        guard used < monthlyCallsPerDevice else { return false }
        defaults.set(used + 1, forKey: countKey)
        return true
    }

    // MARK: - Reuse

    private static func cachedReading(near location: CLLocation) -> StampWeather? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(CachedReading.self, from: data),
              Date().timeIntervalSince(cached.date) < reuseWindow else { return nil }
        let there = CLLocation(latitude: cached.latitude, longitude: cached.longitude)
        return location.distance(from: there) < reuseRadiusMeters ? cached.weather : nil
    }

    private static func store(_ weather: StampWeather, at location: CLLocation) {
        let cached = CachedReading(
            weather: weather,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            date: Date()
        )
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private static func isWet(_ condition: WeatherCondition) -> Bool {
        switch condition {
        case .drizzle, .rain, .heavyRain, .sunShowers, .freezingDrizzle, .freezingRain,
             .isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms, .strongStorms:
            true
        default:
            false
        }
    }

    /// Apple requires its weather mark and legal link wherever the data is shown.
    static func attribution() async -> WeatherAttribution? {
        try? await WeatherService.shared.attribution
    }
}
