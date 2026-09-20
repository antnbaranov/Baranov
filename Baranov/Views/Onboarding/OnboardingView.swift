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
    @AppStorage("com.baranov.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("com.baranov.carrierDisplayName") private var storedDisplayName = ""
    @State private var page = 0
    @State private var name = ""
    @State private var ramName = ""
    @State private var pageTick = 0
    @FocusState private var isNameFocused: Bool
    @FocusState private var isRamNameFocused: Bool

    let onFinished: () -> Void

    private let pageCount = 6

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedRamName: String {
        ramName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdvance: Bool {
        switch page {
        case 4:
            return !trimmedName.isEmpty
        case 5:
            return !trimmedRamName.isEmpty
        default:
            return true
        }
    }

    private var isLastPage: Bool { page == pageCount - 1 }

    @AppStorage(AppLanguagePickerView.storageKey) private var selectedLanguageCode = Locale.current.language.languageCode?.identifier ?? "en"
    @State private var isLanguagePickerPresented = false

    private var currentLanguageDisplayName: String {
        let targetLocale = Locale(identifier: selectedLanguageCode)
        return targetLocale.localizedString(forIdentifier: selectedLanguageCode)?.capitalized(with: targetLocale)
            ?? targetLocale.localizedString(forLanguageCode: selectedLanguageCode)?.capitalized(with: targetLocale)
            ?? selectedLanguageCode
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    isLanguagePickerPresented = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "globe")
                        Text(currentLanguageDisplayName)
                            .font(.footnote.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .padding(.trailing, 20)
            }

            TabView(selection: $page) {
                PainPage().tag(0)
                RamPage().tag(1)
                OceanPage().tag(2)
                SealPage().tag(3)
                namePage.tag(4)
                ramCompanionPage.tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: page) { _, newPage in
                if newPage == 5 && trimmedName.isEmpty {
                    page = 4
                    return
                }
                pageTick += 1
                if newPage == 4 {
                    isNameFocused = true
                    isRamNameFocused = false
                } else if newPage == 5 {
                    isNameFocused = false
                    isRamNameFocused = true
                } else {
                    isNameFocused = false
                    isRamNameFocused = false
                }
            }
            .sensoryFeedback(.selection, trigger: pageTick)

            footer
        }
        .sheet(isPresented: $isLanguagePickerPresented) {
            NavigationStack {
                AppLanguagePickerView()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .environment(\.locale, Locale(identifier: selectedLanguageCode))
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
                Group {
                    if isLastPage {
                        Text("Open the Gate")
                    } else if page == 0 {
                        Text("There's another way")
                    } else {
                        Text("Continue")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .disabled(!canAdvance)
            .animation(.easeInOut(duration: 0.2), value: canAdvance)
            .padding(.horizontal, 32)
        }
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    private func advance() {
        guard canAdvance else { return }
        if isLastPage {
            finish()
        } else {
            withAnimation(.easeInOut(duration: 0.35)) {
                page += 1
            }
        }
    }

    private func finish() {
        guard !trimmedName.isEmpty, !trimmedRamName.isEmpty else { return }
        storedDisplayName = trimmedName
        let store = RamCompanionStore()
        store.createIfNeeded(name: trimmedRamName)
        hasCompletedOnboarding = true
        onFinished()
    }

    // MARK: - Page 5: name

    private var namePage: some View {
        OnboardingPageLayout(
            eyebrow: "Almost there",
            title: "Who's writing?",
            text: "Your name appears on every letter you send. That's the whole account system."
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
                    .submitLabel(.next)
                    .onSubmit {
                        if !trimmedName.isEmpty {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                page = 5
                            }
                        }
                    }
                    .pillFieldBackground()
                    .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Page 6: Welcome your ram companion

    private var ramCompanionPage: some View {
        OnboardingPageLayout(
            eyebrow: "One last thing",
            title: "Name your ram.",
            text: "It'll carry your letters for as long as you keep Baranov."
        ) {
            OnboardingRamCompanionCard(
                name: $ramName,
                isFocused: $isRamNameFocused,
                onDone: {
                    if !trimmedRamName.isEmpty {
                        finish()
                    }
                }
            )
        }
    }
}

// MARK: - Onboarding Ram Companion Card

private struct OnboardingRamCompanionCard: View {
    @Binding var name: String
    @FocusState.Binding var isFocused: Bool
    let onDone: () -> Void

    @State private var bleatTrigger = 0

    private var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                portrait
                    .contentShape(Rectangle())
                    .onTapGesture {
                        bleatTrigger += 1
                        RamBleatPlayer.shared.play()
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: bleatTrigger)
                    .accessibilityLabel(displayName.isEmpty ? "Pet your ram" : "Pet \(displayName)")

                VStack(spacing: 2) {
                    if displayName.isEmpty {
                        Text("Your Ram")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(displayName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                    }

                    Text("Resting in the pasture")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Ram's Name", text: $name)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.body.weight(.medium))
                .focused($isFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit {
                    if !displayName.isEmpty {
                        onDone()
                    }
                }
                .pillFieldBackground()
                .padding(.horizontal, 24)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var portrait: some View {
        if !displayName.isEmpty, UIImage(named: "Ram-\(displayName)") != nil {
            Image("Ram-\(displayName)")
                .resizable()
                .scaledToFit()
                .frame(height: 140)
        } else if let first = RamSpriteFrameSets.walkCycle.first, RamSpriteFrameSets.assetExists(first) {
            RamSpriteLoopView(frameNames: RamSpriteFrameSets.walkCycle, frameDuration: .milliseconds(80))
                .frame(height: 140)
        } else if UIImage(named: "RamPortraitPlaceholder") != nil {
            Image("RamPortraitPlaceholder")
                .resizable()
                .scaledToFit()
                .frame(height: 140)
        } else {
            Image(systemName: "pawprint.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
        }
    }
}

// MARK: - Shared page layout

private struct OnboardingPageLayout<Demo: View>: View {
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    @ViewBuilder let demo: () -> Demo

    @State private var textAppeared = false

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
                    .opacity(textAppeared ? 1 : 0)
                    .offset(y: textAppeared ? 0 : 16)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05), value: textAppeared)

                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(textAppeared ? 1 : 0)
                    .offset(y: textAppeared ? 0 : 16)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.13), value: textAppeared)

                Text(text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(textAppeared ? 1 : 0)
                    .offset(y: textAppeared ? 0 : 16)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.22), value: textAppeared)
            }
            .padding(.horizontal, 28)
            .onAppear { textAppeared = true }
            .onDisappear { textAppeared = false }

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

    private let messages: [(LocalizedStringKey, LocalizedStringKey)] = [
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
            text: "So nothing feels like it matters. Read, skipped, gone."
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("A stream of instant messages arriving one after another, then fading into irrelevance")
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
            title: "A letter that has to be carried.",
            text: "Your ram walks it to them. One of your real steps moves it one metre closer."
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

                Text("\"Baranov\" is the maker's surname — it means rams.")
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
            title: "No road crosses an ocean.",
            text: "Your ram walks to a port and boards a packet — it crosses on its own. Shake phones with someone crossing sooner and it hops to their phone instead."
        ) {
            VStack(spacing: 8) {
                ZStack {
                    HStack {
                        phone(label: "You", isShaking: !crossed)
                        Spacer()
                        phone(label: "Someone crossing sooner", isShaking: crossed)
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
                    .offset(y: 44)

                    RamSpriteLoopView(frameNames: RamSpriteFrameSets.gallopRunningStride, frameDuration: .milliseconds(60))
                        .frame(height: 64)
                        .offset(x: crossed ? 92 : -92, y: -6)
                        .animation(.easeInOut(duration: 1.4), value: crossed)
                }

                HStack(spacing: 6) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.caption2)
                    Text("Shake phones or AirDrop to hand off")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.thinMaterial, in: Capsule())
            }
            .task {
                crossed = false
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(1400))
                    crossed.toggle()
                }
            }
        }
    }

    private func phone(label: LocalizedStringKey, isShaking: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "iphone")
                .font(.system(size: 56, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isShaking ? Color.accentColor : Color.secondary)
                .symbolEffect(.wiggle, value: crossed)
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
            text: "Only the recipient's code breaks it. Hold the seal to try."
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
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: "Break Seal") {
                        shatter()
                    }
                }
                .frame(height: 150)
                .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: crackTick)
                .sensoryFeedback(.impact(weight: .heavy), trigger: breakTick)

                if isOpen {
                    Text("Broken. That's the feeling.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                } else {
                    Text("Hold the seal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
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
