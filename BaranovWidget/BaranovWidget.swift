//
//  BaranovWidget.swift
//  BaranovWidget
//
import SwiftUI
import WidgetKit

@main
struct BaranovWidgetBundle: WidgetBundle {
    var body: some Widget {
        BaranovHomeWidget()
        BaranovLiveActivityView()
    }
}

struct BaranovHomeWidget: Widget {
    let kind: String = "BaranovWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BaranovWidgetProvider()) { entry in
            BaranovWidgetView(entry: entry)
        }
        .configurationDisplayName("Baranov")
        .description("See your ram's journey at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
