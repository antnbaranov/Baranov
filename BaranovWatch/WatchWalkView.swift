//
//  WatchWalkView.swift
//  BaranovWatch
//
//  Active walking session with your ram on Apple Watch:
//  - Live step tracking via CMPedometer (with simulator fallback)
//  - Hoofbeat haptic feedback as you walk
//  - Galloping ram companion sprite
//  - Session summary and instant two-way sync back to iPhone
//

import CoreMotion
import SwiftUI
import WatchKit

struct WatchWalkView: View {
    @Environment(\.dismiss) private var dismiss

    let ramName: String

    @State private var pedometer = CMPedometer()
    @State private var stepsWalked: Int = 0
    @State private var startDate: Date = Date()
    @State private var elapsedTime: TimeInterval = 0
    @State private var isFinished: Bool = false
    @State private var lastHapticStep: Int = 0

    #if targetEnvironment(simulator)
    @State private var simTask: Task<Void, Never>?
    #endif

    private var formattedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var distanceString: String {
        let meters = Int(Double(stepsWalked) * 0.75)
        if meters >= 1000 {
            return String(format: "%.2f km", Double(meters) / 1000.0)
        } else {
            return "\(meters) m"
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            VStack(spacing: 8) {
                if !isFinished {
                    activeWalkContent
                } else {
                    summaryContent
                }
            }
            .padding(.horizontal, 6)
            .onChange(of: context.date) { _, newDate in
                if !isFinished {
                    elapsedTime = newDate.timeIntervalSince(startDate)
                }
            }
        }
        .onAppear {
            startTracking()
        }
        .onDisappear {
            stopTracking()
        }
    }

    // MARK: - Active Walk UI

    private var activeWalkContent: some View {
        VStack(spacing: 4) {
            // Header: Timer & Ram Name
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "stopwatch.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                    Text(formattedTime)
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                }
                Spacer()
                Text(ramName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            // Galloping Ram Sprite
            WatchSpriteView(name: "", isWalking: true, size: 68)
                .frame(height: 70)

            // Step Counter
            VStack(spacing: 0) {
                Text("\(stepsWalked)")
                    .font(.system(size: 32, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    Text(String(localized: "Steps Walked"))
                        .font(.system(size: 10, weight: .medium))
                    Text("•")
                        .font(.system(size: 8))
                    Text(distanceString)
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                }
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 2)

            // Finish Walk Button
            Button(role: .destructive) {
                finishWalk()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11))
                    Text(String(localized: "End Walk"))
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red.opacity(0.85))
        }
    }

    // MARK: - Summary Celebration UI

    private var summaryContent: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 4)

            Text(String(localized: "Well Walked!"))
                .font(.headline.weight(.bold))

            Text(String(format: String(localized: "+%lld steps added to %@"), Int64(stepsWalked), ramName))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text(formattedTime)
                        .font(.caption.monospacedDigit().weight(.semibold))
                    Text(String(localized: "Time"))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }

                Divider()
                    .frame(height: 20)

                VStack(spacing: 2) {
                    Text(distanceString)
                        .font(.caption.monospacedDigit().weight(.semibold))
                    Text(String(localized: "Distance"))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text(String(localized: "Done"))
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Tracking Logic

    private func startTracking() {
        startDate = Date()
        elapsedTime = 0
        stepsWalked = 0
        lastHapticStep = 0

        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: startDate) { data, error in
                guard let data, error == nil else { return }
                DispatchQueue.main.async {
                    self.stepsWalked = data.numberOfSteps.intValue
                    if self.stepsWalked - self.lastHapticStep >= 25 {
                        self.lastHapticStep = self.stepsWalked
                        WKInterfaceDevice.current().play(.directionUp)
                    }
                }
            }
        }

        #if targetEnvironment(simulator)
        simTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !self.isFinished {
                    self.stepsWalked += 2
                    if self.stepsWalked - self.lastHapticStep >= 20 {
                        self.lastHapticStep = self.stepsWalked
                        WKInterfaceDevice.current().play(.directionUp)
                    }
                }
            }
        }
        #endif
    }

    private func stopTracking() {
        pedometer.stopUpdates()
        #if targetEnvironment(simulator)
        simTask?.cancel()
        simTask = nil
        #endif
    }

    private func finishWalk() {
        stopTracking()
        WKInterfaceDevice.current().play(.success)
        WatchBleatPlayer.shared.play()
        WatchSessionManager.shared.sendWalkSteps(stepsWalked)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            isFinished = true
        }
    }
}

#Preview {
    WatchWalkView(ramName: "Klaus")
}
