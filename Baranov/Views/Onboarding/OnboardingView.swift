//
//  OnboardingView.swift
//  Baranov
//
//  First launch. Five pages, in the order the idea actually happened:
//  the pain first — everything arrives instantly, so nothing arrives
//  meaning anything — then the ram, the walk, the ocean, the seal, and
//  finally the one thing the app needs from the person: their name, so
//  every letter can introduce them.
//
//  Each page is a small, native demonstration rather than a stock
//  illustration: the first stacks up the kind of messages the app is a
//  reaction to; the ram page shows the real walk-cycle sprite; the ocean
//  page passes a ram between two phones; the seal page is a working wax
//  seal the person can hold and feel break, the same gesture and the same
//  heavy haptic they'll meet for real at the gate. Nothing here is a
//  screenshot of a feature — it's the feature, in miniature.
//
//  Page changes use a plain `TabView` (`.page` style, dots hidden) with
//  the app's own dots and a single prominent button, so the flow is
//  swipeable like every iOS onboarding and never traps anyone: the button
//  advances, the last page is the only one that requires input, and it
//  falls back to a default name if the field is left empty.
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage("com.baranov.carrierDisplayName") private var storedDisplayName = ""
    @State private var page = 0
    @State private var name = ""
    @State private var pageTick = 0
    @FocusState private var isNameFocused: Bool

    let onFinished: () -> Void

    private let pageCount = 5

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isLastPage: Bool { page == pageCount - 1 }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                PainPage().tag(0)
                RamPage().tag(1)
                OceanPage().tag(2)
                SealPage().tag(3)
                namePage.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: page) { _, _ in
                pageTick += 1
                if isLastPage {
                    isNameFocused = true
                }
            }
            .sensoryFeedback(.selection, trigger: pageTick)

            footer
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: index == page ? 22 : 8, height: 8)
                        .animation(.snappy, value: page)
                }
            }
            .accessibilityLabel("Page \(page + 1) of \(pageCount)")

            Button(action: advance) {
                Text(isLastPage ? "Open the Gate" : (page == 0 ? "There's another way" : "Continue"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .padding(.horizontal, 32)
        }
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    private func advance() {
        if isLastPage {
            finish()
        } else {
            withAnimation(.easeInOut(duration: 0.35)) {
                page += 1
            }
        }
    }

    private func finish() {
        storedDisplayName = trimmedName.isEmpty ? "A Shepherd" : trimmedName
        onFinished()
    }

    // MARK: - Page 5: name

    private var namePage: some View {
        OnboardingPageLayout(
            eyebrow: "One last thing",
            title: "Who's writing?",
            text: "Every letter introduces you by name to whoever breaks the seal. That's the whole account system — there isn't one."
        ) {
            VStack(spacing: 14) {
                Image(systemName: "signature")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)

                TextField("Your Name", text: $name)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.title3.weight(.medium))
                    .focused($isNameFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(finish)
                    .pillFieldBackground()
                    .padding(.horizontal, 24)
            }
        }
    }
}

// MARK: - Shared page layout

/// The one shape every onboarding page has: a demonstration up top, an
/// eyebrow, a big title, a short body. Keeps the pages from drifting
/// apart visually as each one does its own thing in the demo slot.
private struct OnboardingPageLayout<Demo: View>: View {
    let eyebrow: String
    let title: String
    let text: String
    @ViewBuilder let demo: () -> Demo

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            demo()
                .frame(maxWidth: .infinity)
                .frame(height: 260)

            Spacer(minLength: 12)

            VStack(spacing: 10) {
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 24)
        }
    }
}

// MARK: - Page 1: the pain

/// The kind of inbox this app is a reaction to: messages that pile in,
/// get skimmed, and are gone. They arrive one after another, then dim —
/// nothing here was ever meant to be kept.
private struct PainPage: View {
    @State private var shown = 0
    @State private var dimmed = false

    private let messages: [(String, String)] = [
        ("hey", "now"),
        ("u up?", "now"),
        ("k", "now"),
        ("👍", "now"),
        ("lol ok", "now"),
    ]

    var body: some View {
        OnboardingPageLayout(
            eyebrow: "The problem",
            title: "Everything arrives instantly.",
            text: "So nothing arrives mattering. A message costs nothing to send — and it shows. Read in a queue, gone before the coffee."
        ) {
            VStack(spacing: 10) {
                ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                    HStack {
                        Text(message.0)
                            .font(.body)
                        Spacer()
                        Text(message.1)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .opacity(index < shown ? (dimmed ? 0.35 : 1) : 0)
                    .offset(y: index < shown ? 0 : 12)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0), value: shown)
                    .animation(.easeInOut(duration: 0.8), value: dimmed)
                }
            }
            .padding(.horizontal, 40)
            .task {
                shown = 0
                dimmed = false
                for _ in messages {
                    try? await Task.sleep(for: .milliseconds(320))
                    shown += 1
                }
                try? await Task.sleep(for: .milliseconds(900))
                dimmed = true
            }
        }
    }
}

// MARK: - Page 2: the ram

private struct RamPage: View {
    @State private var stepCount = 0

    var body: some View {
        OnboardingPageLayout(
            eyebrow: "Another way",
            title: "Send a letter that has to be carried.",
            text: "Write it, seal it, and your ram walks it to their city. It only moves when you do: one of your real steps is one metre of its road."
        ) {
            VStack(spacing: 14) {
                RamSpriteLoopView(frameNames: RamSpriteFrameSets.walkCycle, frameDuration: .milliseconds(80))
                    .frame(height: 150)

                HStack(spacing: 8) {
                    Image(systemName: "figure.walk")
                        .symbolEffect(.pulse, options: .repeating)
                    Text("\(stepCount) steps · \(stepCount) m")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())

                // Why rams, and why "Baranov": the name is the maker's
                // surname, and it means exactly this.
                Text("Baranov is the creator's surname, which directly translates to \u{201C}rams\u{201D} — the faithful messengers delivering your encrypted letters.")
                    .font(.system(.caption, design: .serif).italic())
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 36)
            }
            .task {
                stepCount = 0
                while !Task.isCancelled, stepCount < 1_200 {
                    try? await Task.sleep(for: .milliseconds(140))
                    withAnimation(.linear(duration: 0.14)) {
                        stepCount += Int.random(in: 7...19)
                    }
                }
            }
        }
    }
}

// MARK: - Page 3: the ocean

/// The two ways over water, shown together: a packet sailing below, and a
/// ram crossing phone to phone above. The point of the page is that the
/// boat is the guarantee and the person is the shortcut — a letter is
/// never stranded waiting for a stranger who may never come.
private struct OceanPage: View {
    @State private var crossed = false

    var body: some View {
        OnboardingPageLayout(
            eyebrow: "Borders and oceans",
            title: "Water waits for a boat.",
            text: "No road crosses an ocean. Your ram walks to a port and boards the next packet — it gets there on its own, slowly. Hand it to someone crossing sooner, phone to phone, and it skips the wait. No server ever sees your letter."
        ) {
            ZStack {
                HStack {
                    phone(label: "You")
                    Spacer()
                    phone(label: "Someone crossing sooner")
                }
                .padding(.horizontal, 44)

                ZStack {
                    Image(systemName: "water.waves")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        .symbolEffect(.variableColor.iterative, options: .repeating)

                    Image(systemName: "ferry.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .offset(x: crossed ? 46 : -46, y: -2)
                        .animation(.easeInOut(duration: 3.2), value: crossed)
                }
                .offset(y: 54)

                RamSpriteLoopView(frameNames: RamSpriteFrameSets.gallopRunningStride, frameDuration: .milliseconds(60))
                    .frame(height: 64)
                    .offset(x: crossed ? 92 : -92, y: -6)
                    .animation(.easeInOut(duration: 1.4), value: crossed)
            }
            .task {
                crossed = false
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(900))
                    crossed.toggle()
                }
            }
        }
    }

    private func phone(label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "iphone")
                .font(.system(size: 56, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 90)
        }
    }
}

// MARK: - Page 4: the seal

/// A working wax seal: hold it and cracks spread with soft ticks; at a
/// second and a half it shatters with the same heavy impact the real
/// arrival ritual uses, and the envelope opens. Resets a moment later so
/// it can be tried again. Same components as Compose and the gate
/// (`WaxSeal.swift`), so what's learned here is exactly what's used.
private struct SealPage: View {
    @State private var progress: Double = 0
    @State private var isPressing = false
    @State private var isShattering = false
    @State private var isOpen = false
    @State private var breakTick = 0
    @State private var crackTick = 0
    @State private var crackTask: Task<Void, Never>?

    var body: some View {
        OnboardingPageLayout(
            eyebrow: "On arrival",
            title: "Sealed until it's home.",
            text: "Sealed letters travel as ciphertext. Only the recipient's code breaks the wax — and only at their gate. Try it: hold the seal."
        ) {
            VStack(spacing: 16) {
                ZStack(alignment: .top) {
                    SealedEnvelopeView(wax: .crimson, monogram: "B", addressee: "You", isOpen: isOpen, width: 220, showsSeal: false)

                    ZStack {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(SealColor.crimson.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 76, height: 76)
                            .rotationEffect(.degrees(-90))
                            .opacity(isShattering ? 0 : 1)
                        WaxSealBreakView(wax: .crimson, monogram: "B", diameter: 64, crackProgress: progress, isShattering: isShattering)
                    }
                    .frame(width: 76, height: 76)
                    .scaleEffect(isPressing ? 0.94 : 1)
                    .animation(.easeOut(duration: 0.15), value: isPressing)
                    .opacity(isOpen ? 0 : 1)
                    .offset(y: SealedEnvelopeView.sealCenterY(width: 220) - 38)
                    .contentShape(Circle())
                    .onLongPressGesture(minimumDuration: 1.5, maximumDistance: 40) {
                        shatter()
                    } onPressingChanged: { pressing in
                        guard !isShattering else { return }
                        isPressing = pressing
                        if pressing {
                            withAnimation(.linear(duration: 1.5)) { progress = 1 }
                            startCrackTicks()
                        } else {
                            crackTask?.cancel()
                            if progress < 1 {
                                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                            }
                        }
                    }
                    .accessibilityLabel("Wax seal")
                    .accessibilityHint("Touch and hold to break")
                }
                .frame(height: 150)
                .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: crackTick)
                .sensoryFeedback(.impact(weight: .heavy), trigger: breakTick)

                Text(isOpen ? "Broken. That's the feeling." : "Hold the seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
        }
        .onDisappear { crackTask?.cancel() }
    }

    private func startCrackTicks() {
        crackTask?.cancel()
        crackTask = Task {
            for _ in 0..<5 {
                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled else { return }
                crackTick += 1
            }
        }
    }

    private func shatter() {
        crackTask?.cancel()
        breakTick += 1
        isPressing = false
        isShattering = true
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            isOpen = true
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeInOut) {
                isOpen = false
                isShattering = false
                progress = 0
            }
        }
    }
}

#Preview {
    OnboardingView(onFinished: {})
}
