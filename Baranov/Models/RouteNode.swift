//
//  RouteNode.swift
//  Baranov
//
//  A single waypoint logged along a ram's journey: the place it passed
//  through, who walked the steps that got it there, and when. Route nodes
//  are appended by the routing/telemetry layer once a ram's progress is
//  resolved against its polyline — this model only describes the shape
//  of that record.
//

import Foundation

struct RouteNode: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let cityName: String
    let latitude: Double
    let longitude: Double
    let carrierName: String
    let stepsContributed: Int
    let timestamp: Date

    init(
        id: UUID = UUID(),
        cityName: String,
        latitude: Double,
        longitude: Double,
        carrierName: String,
        stepsContributed: Int,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.cityName = cityName
        self.latitude = latitude
        self.longitude = longitude
        self.carrierName = carrierName
        self.stepsContributed = stepsContributed
        self.timestamp = timestamp
    }
}
