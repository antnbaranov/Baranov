//
//  RamActivityAttributes.swift
//  BaranovWidget
//
import ActivityKit
import Foundation

struct RamActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var progress: Double
        var remainingSteps: Int
        var remainingDistance: String
        var statusSymbol: String
        var statusLabel: String
    }
    var ramName: String
    var fromCity: String
    var toCity: String
}
