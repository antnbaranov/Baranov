//
//  WatchSpriteView.swift
//  BaranovWatch
//
//  Smooth animated ram sprite loop with letter in mouth,
//  running gait, idle breathing, and audible wrist bleating.
//

import SwiftUI
import WatchKit

struct WatchSpriteView: View {
    let name: String
    var isWalking: Bool = true
    var size: CGFloat = 86
    var onPet: (() -> Void)? = nil

    private let runningFrames: [String] = (2...8).map { "Object-\($0)" }
    private let idleFrames: [String] = ["Object-11", "Object-12"]

    @State private var currentFrameIndex: Int = 0
    @State private var isPetting: Bool = false
    @State private var petScale: CGFloat = 1.0

    private var activeFrames: [String] {
        isWalking ? runningFrames : idleFrames
    }

    private var currentImageName: String {
        if isPetting {
            return "Object-16" // Happy rearing pose on petting!
        }
        guard !activeFrames.isEmpty else { return "Object-2" }
        return activeFrames[currentFrameIndex % activeFrames.count]
    }

    var body: some View {
        Button {
            pet()
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    // Soft circular atmospheric backing
                    Circle()
                        .fill(RadialGradient(
                            colors: [Color.accentColor.opacity(0.2), Color.clear],
                            center: .center,
                            startRadius: 10,
                            endRadius: size * 0.6
                        ))
                        .frame(width: size + 10, height: size + 10)

                    Image(currentImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                        .scaleEffect(petScale)
                }

                Text(name)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pet \(name)")
        .accessibilityHint("Double tap to pet your ram and hear a bleat")
        .accessibilityAction(named: "Pet Ram") {
            pet()
        }
        .task(id: isWalking) {
            let interval = isWalking ? 0.09 : 0.8
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                currentFrameIndex = (currentFrameIndex + 1) % max(1, activeFrames.count)
            }
        }
    }

    private func pet() {
        WatchBleatPlayer.shared.play()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
            petScale = 0.88
            isPetting = true
        }

        Task {
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                petScale = 1.0
                isPetting = false
            }
        }

        onPet?()
    }
}

#Preview {
    WatchSpriteView(name: "Klaus", isWalking: true)
}
