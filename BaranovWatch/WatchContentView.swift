//
//  WatchContentView.swift
//  BaranovWatch
//
//  Primary Apple Watch interface for Baranov:
//  - Tactile ram petting with crown and haptics
//  - Live progress gauge and route distance
//  - Digital crown scroll and page indicators
//

import SwiftUI
import WatchKit

struct WatchContentView: View {
    @State private var session = WatchSessionManager.shared
    @State private var crownAccumulator: Double = 0
    @State private var isWalkSessionPresented: Bool = false

    var body: some View {
        NavigationStack {
            pager
                // Pushed (not a sheet) so the system clock and back button
                // stay visible on the walk screen.
                .navigationDestination(isPresented: $isWalkSessionPresented) {
                    WatchWalkView(ramName: session.state.ramName)
                }
        }
    }

    private var pager: some View {
        TabView {
            // Page 1: Ram & Petting
            ramPettingPage
                .tag(0)

            // Page 2: Route & Progress Gauge
            routeProgressPage
                .tag(1)

            // Page 3: Sea passage or dispatch status
            if session.state.isAtSea || session.state.seaVoyageTitle != nil {
                seaVoyagePage
                    .tag(2)
            }
        }
        .tabViewStyle(.page)
        .focusable()
        .digitalCrownRotation(
            $crownAccumulator,
            from: -100,
            through: 100,
            by: 1,
            sensitivity: .medium,
            isContinuous: true
        )
    }

    // MARK: - Pages

    private var ramPettingPage: some View {
        VStack(spacing: 6) {
            WatchSpriteView(
                name: session.state.ramName,
                isWalking: session.state.statusSymbol == "figure.walk",
                size: 72
            ) {
                // Petting trigger
            }

            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: session.state.statusSymbol)
                        .font(.caption2.weight(.semibold))
                    Text(session.state.statusLabel)
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.secondary)

                if !session.state.fromCity.isEmpty, !session.state.toCity.isEmpty {
                    Text("\(session.state.fromCity) → \(session.state.toCity)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Button {
                isWalkSessionPresented = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 11, weight: .bold))
                    Text(String(format: String(localized: "Walk with %@"), session.state.ramName))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.horizontal)
    }

    private var routeProgressPage: some View {
        VStack(spacing: 6) {
            Gauge(value: session.state.progress) {
                Text(session.state.ramName)
            } currentValueLabel: {
                Text("\(Int(session.state.progress * 100))%")
                    .font(.title3.weight(.bold))
            }
            .gaugeStyle(.circular)
            .tint(Color.accentColor)
            .frame(width: 86, height: 86)

            VStack(spacing: 1) {
                Text(session.state.remainingDistance)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)

                Text(String(localized: "to destination"))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal)
    }

    private var seaVoyagePage: some View {
        VStack(spacing: 8) {
            Image(systemName: "sailboat.fill")
                .font(.title2)
                .foregroundStyle(.cyan)

            Text(String(localized: "At Sea"))
                .font(.headline)

            Text(session.state.seaVoyageTitle ?? String(localized: "Crossing the water"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }
}

#Preview {
    WatchContentView()
}
