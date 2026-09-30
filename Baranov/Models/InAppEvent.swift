//
//  InAppEvent.swift
//  Baranov
//
//  Data model representing an App Store In-App Event or special seasonal
//  postal expedition triggered via custom URL deep link (e.g. baranov://event/new-york).
//

import CoreLocation
import Foundation

struct InAppEvent: Identifiable, Hashable, Sendable {
    let id: String
    let slug: String
    let title: String
    let subtitle: String
    let destinationCity: String
    let coordinate: RamCoordinate?
    let symbolName: String
    let eventDescription: String

    init(slug: String) {
        let cleanSlug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        self.slug = cleanSlug.isEmpty ? "new-york" : cleanSlug
        self.id = self.slug

        switch self.slug {
        case "new-york", "newyork":
            self.title = String(localized: "Expedition to New York", bundle: .appLanguage, locale: .appLanguage)
            self.subtitle = String(localized: "App Store In-App Event", bundle: .appLanguage, locale: .appLanguage)
            self.destinationCity = "New York, NY"
            self.coordinate = RamCoordinate(latitude: 40.7128, longitude: -74.0060)
            self.symbolName = "building.2.crop.circle.fill"
            self.eventDescription = String(localized: "Dispatch your carrier ram toward the Atlantic coast and New York. Walk your daily steps to carry letters across provinces and borders, earn commemorative passport stamps, and join fellow shepherds along the route.", bundle: .appLanguage, locale: .appLanguage)

        default:
            let formattedName = cleanSlug
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
            self.title = String(localized: "Expedition: \(formattedName)", bundle: .appLanguage, locale: .appLanguage)
            self.subtitle = String(localized: "App Store In-App Event", bundle: .appLanguage, locale: .appLanguage)
            self.destinationCity = formattedName
            self.coordinate = nil
            self.symbolName = "map.circle.fill"
            self.eventDescription = String(localized: "A special postal expedition for \(formattedName). Lace up your walking shoes and carry your letters with the flock.", bundle: .appLanguage, locale: .appLanguage)
        }
    }

    static let newYork = InAppEvent(slug: "new-york")
}
