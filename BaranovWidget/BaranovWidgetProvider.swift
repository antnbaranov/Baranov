//
//  BaranovWidgetProvider.swift
//  BaranovWidget
//
import Foundation
import WidgetKit

struct BaranovWidgetProvider: TimelineProvider {
    private static let appGroupID = "group.com.baranov"
    private static let flockFileName = "Baranov/flock.json"

    func placeholder(in context: Context) -> BaranovWidgetEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (BaranovWidgetEntry) -> Void) {
        completion(context.isPreview ? .placeholder : makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BaranovWidgetEntry>) -> Void) {
        let entry = makeEntry()
        let policy: TimelineReloadPolicy = entry.ramName != nil
            ? .after(Date().addingTimeInterval(15 * 60))
            : .never
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func makeEntry() -> BaranovWidgetEntry {
        guard
            let containerURL = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID),
            let data = try? Data(contentsOf: containerURL.appendingPathComponent(Self.flockFileName)),
            let snapshot = try? JSONDecoder.isoDecoder.decode(FlockSnapshot.self, from: data)
        else { return .empty }

        let active = snapshot.activeRams.filter {
            ["walking", "grazing", "atSea", "waitingForHandoff", "arrivedAtGate"].contains($0.status)
        }
        guard let ram = active.sorted(by: { priorityOrder($0.status) < priorityOrder($1.status) }).first else {
            return .empty
        }

        let remaining = max(0, ram.totalStepsRequired - ram.stepsWalked)
        let progress = ram.totalStepsRequired > 0
            ? min(1.0, Double(ram.stepsWalked) / Double(ram.totalStepsRequired)) : 0
        let distanceStr = remaining >= 1000
            ? String(format: "%.1f km", Double(remaining) / 1000)
            : "\(remaining) m"
        let (symbol, label) = statusDisplay(ram.status)

        return BaranovWidgetEntry(
            date: Date(),
            ramName: ram.name,
            fromCity: ram.currentCity,
            toCity: ram.targetCity,
            progress: progress,
            remainingDistance: distanceStr,
            statusSymbol: symbol,
            statusLabel: label
        )
    }

    private func priorityOrder(_ status: String) -> Int {
        switch status {
        case "walking": return 0
        case "atSea": return 1
        case "waitingForHandoff": return 2
        case "arrivedAtGate": return 3
        default: return 4
        }
    }

    private func statusDisplay(_ status: String) -> (String, String) {
        switch status {
        case "walking": return ("figure.walk", "Walking")
        case "atSea": return ("sailboat", "At Sea")
        case "waitingForHandoff": return ("ferry", "At Port")
        case "arrivedAtGate": return ("flag.checkered", "Arrived")
        default: return ("pawprint", "Resting")
        }
    }
}

private struct FlockSnapshot: Codable {
    var activeRams: [RamSnapshot]
}

private struct RamSnapshot: Codable {
    var name: String
    var status: String
    var stepsWalked: Int
    var totalStepsRequired: Int
    var currentCity: String
    var targetCity: String
}

private extension JSONDecoder {
    static var isoDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
