//
//  PlaceSearchCompleter.swift
//  Baranov
//
//  Live, tap-to-select place suggestions as you type — the same MapKit
//  mechanism behind Apple Maps' own search bar — so picking a city means
//  choosing a real place from a real list instead of typing a guess and
//  hoping `CLGeocoder` resolves it the way you meant.
//

import Foundation
import MapKit
import Observation

@Observable
@MainActor
final class PlaceSearchCompleter: NSObject {
    private(set) var results: [MKLocalSearchCompletion] = []

    private let completer: MKLocalSearchCompleter

    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
    }

    /// The in-progress search text. Setting this drives new suggestions
    /// asynchronously into `results` via the delegate callback below.
    var queryFragment: String {
        get { completer.queryFragment }
        set { completer.queryFragment = newValue }
    }

    func clearResults() {
        results = []
    }

    /// Resolves a tapped suggestion to a real coordinate — completions
    /// themselves carry no coordinate, only display text, so this is a
    /// second real MapKit lookup, not a guess from the suggestion's title.
    func resolve(_ completion: MKLocalSearchCompletion) async throws -> CLLocationCoordinate2D {
        let request = MKLocalSearch.Request(completion: completion)
        let response = try await MKLocalSearch(request: request).start()
        guard let coordinate = response.mapItems.first?.placemark.location?.coordinate else {
            throw PlaceSearchError.noResult
        }
        return coordinate
    }
}

enum PlaceSearchError: Error, Sendable {
    case noResult
}

// MARK: - MKLocalSearchCompleterDelegate

extension PlaceSearchCompleter: MKLocalSearchCompleterDelegate {
    /// Called on an arbitrary queue by MapKit — re-enters the main actor
    /// before touching `results`, the same pattern `StepTrackerService`
    /// and `EntitlementService` use for their own non-isolated callbacks.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let newResults = completer.results
        Task { @MainActor [weak self] in
            self?.results = newResults
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.results = []
        }
    }
}
