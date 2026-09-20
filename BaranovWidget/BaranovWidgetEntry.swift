//
//  BaranovWidgetEntry.swift
//  BaranovWidget
//
import Foundation
import WidgetKit

struct BaranovWidgetEntry: TimelineEntry {
    let date: Date
    let ramName: String?
    let fromCity: String?
    let toCity: String?
    let progress: Double
    let remainingDistance: String?
    let statusSymbol: String
    let statusLabel: String

    static var placeholder: BaranovWidgetEntry {
        BaranovWidgetEntry(
            date: Date(),
            ramName: "Juniper",
            fromCity: "London",
            toCity: "Edinburgh",
            progress: 0.42,
            remainingDistance: "248 km",
            statusSymbol: "figure.walk",
            statusLabel: "Walking"
        )
    }

    static var empty: BaranovWidgetEntry {
        BaranovWidgetEntry(
            date: Date(),
            ramName: nil,
            fromCity: nil,
            toCity: nil,
            progress: 0,
            remainingDistance: nil,
            statusSymbol: "pawprint",
            statusLabel: "Resting"
        )
    }
}
