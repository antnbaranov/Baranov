//
//  RamOnboardingView.swift
//  Baranov
//
//  Shown once, the first time Pasture is opened and no `RamCompanion`
//  exists yet: names the person's own default ram. That ram then ages for
//  real from this moment on (`RamCompanion.bornAt`), shows up as the
//  guaranteed first choice in Compose's ram picker, and is what the
//  Pasture's empty state refers to by name before any letter has ever
//  actually been sent.
//

import SwiftUI

struct RamOnboardingView: View {
    let store: RamCompanionStore
    let onFinished: () -> Void

    @State private var name = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "pawprint.circle.fill")
                .font(.system(size: 64))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Welcome Your Ram")
                    .font(.title2.weight(.semibold))
                Text("Give it a name — it'll grow up carrying your letters, for as long as you keep Baranov.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            TextField("Ram's Name", text: $name)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.title3.weight(.medium))
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(confirm)
                .pillFieldBackground()
                .padding(.horizontal, 48)

            Spacer()

            Button(action: confirm) {
                Text("Welcome to the Pasture")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .task {
            isFocused = true
        }
    }

    private func confirm() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        store.createIfNeeded(name: trimmed.isEmpty ? "Klaus" : trimmed)
        onFinished()
    }
}

#Preview {
    RamOnboardingView(store: RamCompanionStore(), onFinished: {})
}
