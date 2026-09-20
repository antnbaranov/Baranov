//
//  WatchComplication.swift
//  BaranovWatch
//
//  WidgetKit complications for Apple Watch faces:
//  Modular, Infograph, Metropolitan, Activity, etc.
//

import SwiftUI
import WidgetKit

struct WatchComplicationEntry: TimelineEntry {
    let date: Date
    let ramName: String
    let progress: Double
    let remainingDistance: String
    let statusSymbol: String

    static var preview: WatchComplicationEntry {
        WatchComplicationEntry(
            date: Date(),
            ramName: String(localized: "Your ram"),
            progress: 0,
            remainingDistance: "—",
            statusSymbol: "leaf.fill"
        )
    }
}

struct WatchComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchComplicationEntry {
        .preview
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchComplicationEntry) -> Void) {
        completion(.preview)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchComplicationEntry>) -> Void) {
        let entry = currentEntry()
        let nextUpdate = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func currentEntry() -> WatchComplicationEntry {
        if let sharedDefaults = UserDefaults(suiteName: "group.com.baranov"),
           let data = sharedDefaults.data(forKey: "com.baranov.watchState"),
           let state = try? JSONDecoder().decode(WatchRamState.self, from: data) {
            return WatchComplicationEntry(
                date: Date(),
                ramName: state.ramName,
                progress: state.progress,
                remainingDistance: state.remainingDistance,
                statusSymbol: state.statusSymbol
            )
        }
        return .preview
    }
}

struct WatchComplicationView: View {
    let entry: WatchComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Gauge(value: entry.progress) {
                    Image(systemName: "pawprint.fill")
                } currentValueLabel: {
                    Image(systemName: entry.statusSymbol)
                        .font(.caption2)
                }
                .gaugeStyle(.accessoryCircular)
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "pawprint.fill")
                    Text(entry.ramName)
                        .font(.headline)
                        .lineLimit(1)
                }
                ProgressView(value: entry.progress)
                    .tint(.accentColor)
                Text("\(Int(entry.progress * 100))% · \(entry.remainingDistance)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .accessoryInline:
            HStack(spacing: 4) {
                Image(systemName: "pawprint.fill")
                Text("\(entry.ramName) · \(entry.remainingDistance)")
            }

        default:
            Image(systemName: "pawprint.fill")
        }
    }
}

struct BaranovWatchWidget: Widget {
    let kind: String = "BaranovWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchComplicationProvider()) { entry in
            WatchComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Baranov Ram")
        .description("Tracks your letter-carrying ram on your watch face.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
