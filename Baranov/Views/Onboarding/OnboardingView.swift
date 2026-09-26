//
//  OnboardingView.swift
//  Baranov
//
//  First launch. Eight pages (the pain, who it hurts, then the ram, the
//  walk, the ocean, the seal, arrival alerts, and the two names) in the
//  order the idea actually happened:
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
    @AppStorage(MissedPerson.storageKey) private var missedRaw = ""
    @State private var pageTick = 0
    // The same portrait, keys and picker the Profile tab uses, so what's
    // chosen here is exactly what shows there.
    @AppStorage(ShepherdIdentityKeys.avatarSelection) private var avatarSelection = ShepherdPreset.wanderer.rawValue
    @AppStorage(ShepherdIdentityKeys.avatarFile) private var avatarFile = ""
    @AppStorage(ShepherdIdentityKeys.motto) private var motto = ShepherdIdentityKeys.defaultMotto
    @State private var isAvatarPickerPresented = false
    @State private var avatarTick = 0
    @FocusState private var isNameFocused: Bool
    @FocusState private var isRamNameFocused: Bool
    /// True while a system permission sheet is up, so a second tap on the
    /// button can't stack another request behind it.
    @State private var isRequestingPermission = false
    @State private var locationRequester = OnboardingLocationRequester()

    let onFinished: () -> Void

    private let pageCount = 8

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedRamName: String {
        ramName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdvance: Bool {
        switch page {
        case 1:
            return missedPerson != nil
        case 6:
            return !trimmedName.isEmpty
        case 7:
            return !trimmedRamName.isEmpty
        default:
            return true
        }
    }

    private var isLastPage: Bool { page == pageCount - 1 }

    private var missedPerson: MissedPerson? { MissedPerson(rawValue: missedRaw) }

    /// Who the copy talks about from page 2 on ("walks it to Grandma").
    private var missedLabel: String { missedPerson?.label ?? String(localized: "them") }

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
                MissedPersonPage(selection: $missedRaw).tag(1)
                RamPage(recipientLabel: missedLabel).tag(2)
                OceanPage(isActive: page == 3, recipientLabel: missedLabel).tag(3)
                SealPage(person: missedPerson).tag(4)
                AlertsPage(person: missedPerson).tag(5)
                namePage.tag(6)
                ramCompanionPage.tag(7)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: page) { _, newPage in
                if newPage == 7 && trimmedName.isEmpty {
                    page = 6
                    return
                }
                pageTick += 1
                if newPage == 6 {
                    isNameFocused = true
                    isRamNameFocused = false
                } else if newPage == 7 {
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
            .tint(Color.primary)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .environment(\.locale, Locale(identifier: selectedLanguageCode))
        // Burgundy, the same wax as the seal, for the buttons and selection
        // on these pages only; the rest of the app keeps its own accent.
        .tint(SealColor.crimson.color)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                        .animation(.snappy, value: page)
                }
            }
            .accessibilityLabel("Page \(page + 1) of \(pageCount)")

            Button { advance() } label: {
                Group {
                    if isLastPage {
                        Text("Open the gate")
                    } else if page == 0 {
                        Text("That's me")
                    } else if page == 1 {
                        Text("There's another way")
                    } else if page == 2 {
                        Text("Count my steps")
                    } else if page == 3 {
                        Text("Use my location")
                    } else if page == 5 {
                        Text("Turn on arrival alerts")
                    } else {
                        Text("Continue")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .disabled(!canAdvance || isRequestingPermission)
            .animation(.easeInOut(duration: 0.2), value: canAdvance)
            .padding(.horizontal, 24)

            if page == 5 {
                Button("Not now") { advance(requestingPermission: false) }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .disabled(isRequestingPermission)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 28)
    }

    private func advance(requestingPermission: Bool = true) {
        guard canAdvance, !isRequestingPermission else { return }
        let currentPage = page
        Task { @MainActor in
            isRequestingPermission = true
            if requestingPermission {
                await requestPermission(forPage: currentPage)
            }
            isRequestingPermission = false
            if currentPage == pageCount - 1 {
                finish()
            } else {
                withAnimation(.easeInOut(duration: 0.35)) {
                    page = currentPage + 1
                }
            }
        }
    }

    /// One permission per page, asked in context when its button is
    /// tapped. Denying never blocks the flow.
    private func requestPermission(forPage page: Int) async {
        switch page {
        case 2: await OnboardingPermissions.requestMotion()
        case 3: await locationRequester.request()
        case 5: await OnboardingPermissions.requestNotifications()
        case 7: await OnboardingPermissions.requestHealthSteps()
        default: break
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

    // MARK: - name

    private var namePage: some View {
        OnboardingPageLayout(
            title: "Who's writing?",
            text: "Your name appears on every letter you send. That's the whole account system.",
            isCompact: isNameFocused
        ) {
            VStack(spacing: 16) {
                Button {
                    avatarTick += 1
                    isAvatarPickerPresented = true
                } label: {
                    ShepherdAvatarView(selection: avatarSelection, customFileName: avatarFile, size: 104,
                                       showsEditBadge: true, squareCornerRadius: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change shepherd avatar")
                .sensoryFeedback(.impact(weight: .light), trigger: avatarTick)

                TextField("Your name", text: $name)
                    .onboardingField()
                    .focused($isNameFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit {
                        if !trimmedName.isEmpty {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                page = 7
                            }
                        }
                    }

                if !isNameFocused {
                    Text("Tap the portrait to choose your shepherd.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .sheet(isPresented: $isAvatarPickerPresented) {
                ShepherdPickerSheet(selection: $avatarSelection, customFileName: $avatarFile, motto: $motto)
                    .tint(nil)
            }
        }
    }

    // MARK: - Welcome your ram companion

    private var ramCompanionPage: some View {
        OnboardingPageLayout(
            title: "Name your ram.",
            text: "It'll carry your letters for as long as you keep Baranov.",
            isCompact: isRamNameFocused
        ) {
            OnboardingRamCompanionCard(
                name: $ramName,
                isFocused: $isRamNameFocused,
                onDone: { advance() }
            )
        }
    }
}

// MARK: - Onboarding pill

private extension View {
    /// The one capsule readout used under the ram and ocean demos, so the
    /// steps counter and the hand-off hint are the same size and weight.
    func onboardingPill() -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
    }
}

// MARK: - Onboarding field

private extension View {
    /// The large, left-aligned text field used on the name pages: a
    /// grouped-row surface (the same one Settings uses) with title-size
    /// text, so it's easy to hit and easy to read.
    func onboardingField() -> some View {
        self
            .textFieldStyle(.plain)
            .font(.title3)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                        Text("Your ram")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(displayName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                    }

                    Text("Resting in the pasture")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Ram's name", text: $name)
                .onboardingField()
                .focused($isFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit {
                    if !displayName.isEmpty {
                        onDone()
                    }
                }

            Text("Opening the gate also asks to read your steps from Apple Health, so an Apple Watch counts too. Optional.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var portrait: some View {
        if !displayName.isEmpty, UIImage(named: "Ram-\(displayName)") != nil {
            Image("Ram-\(displayName)")
                .resizable()
                .scaledToFit()
                .frame(height: 120)
        } else if let first = RamSpriteFrameSets.walkCycle.first, RamSpriteFrameSets.assetExists(first) {
            RamSpriteLoopView(frameNames: RamSpriteFrameSets.walkCycle, frameDuration: .milliseconds(80))
                .frame(height: 120)
        } else if UIImage(named: "RamPortraitPlaceholder") != nil {
            Image("RamPortraitPlaceholder")
                .resizable()
                .scaledToFit()
                .frame(height: 120)
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

/// Every page shares one header: a large title and a line of secondary
/// body copy, leading-aligned at the same margin and the same distance from
/// the top, so the eye lands in the same place on every page (the way
/// Apple's own "What's New" screens read). The demo fills the space below.
/// While the keyboard is up the body copy steps aside; the title never
/// moves or changes size.
private struct OnboardingPageLayout<Demo: View>: View {
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    var isCompact = false
    /// Moves the demo up from the vertical centre of the space below the
    /// header, in points, on pages whose demo reads better higher.
    var demoLift: CGFloat = 0
    @ViewBuilder let demo: () -> Demo

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.largeTitle.bold())
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)

                        if !isCompact {
                            Text(text)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: isCompact ? nil : 216, alignment: .topLeading)
                    .animation(.snappy, value: isCompact)

                    demo()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 24)
                        .padding(.bottom, 24 + demoLift * 2)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

// MARK: - Messages-style bubbles

/// A message bubble drawn like the ones in Messages: blue and trailing for
/// what you sent, system gray and leading for what you received, with the
/// small tail only on the last bubble of a run.
private struct MessageBubble: View {
    let text: LocalizedStringKey
    let isOutgoing: Bool
    var showsTail = true
    /// A Messages tapback (SF Symbol name) pinned to the bubble's top corner.
    var reaction: String? = nil

    var body: some View {
        HStack(spacing: 0) {
            if isOutgoing { Spacer(minLength: 60) }
            Text(text)
                .font(.body)
                .foregroundStyle(isOutgoing ? Color.white : Color.primary)
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .padding(isOutgoing ? .trailing : .leading, showsTail ? 6 : 0)
                .background(
                    MessageBubbleShape(isOutgoing: isOutgoing, showsTail: showsTail)
                        .fill(isOutgoing ? Color.blue : Color(.systemGray5))
                )
                .overlay(alignment: .topLeading) {
                    if let reaction {
                        Image(systemName: reaction)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color(.systemGray5), in: Circle())
                            .overlay(Circle().strokeBorder(Color(.systemGroupedBackground), lineWidth: 2))
                            .offset(x: -12, y: -14)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            if !isOutgoing { Spacer(minLength: 60) }
        }
    }
}

private struct MessageBubbleShape: Shape {
    let isOutgoing: Bool
    let showsTail: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18
        let tail: CGFloat = showsTail ? 6 : 0
        let x0 = rect.minX, y0 = rect.minY, y1 = rect.maxY
        let bx = rect.maxX - tail
        var p = Path()
        p.move(to: CGPoint(x: x0 + r, y: y0))
        p.addLine(to: CGPoint(x: bx - r, y: y0))
        p.addQuadCurve(to: CGPoint(x: bx, y: y0 + r), control: CGPoint(x: bx, y: y0))
        if showsTail {
            p.addLine(to: CGPoint(x: bx, y: y1 - 14))
            p.addCurve(to: CGPoint(x: rect.maxX, y: y1),
                       control1: CGPoint(x: bx, y: y1 - 6),
                       control2: CGPoint(x: bx + 1.5, y: y1 - 1.5))
            p.addCurve(to: CGPoint(x: bx - 8, y: y1),
                       control1: CGPoint(x: rect.maxX - 2, y: y1),
                       control2: CGPoint(x: bx - 1, y: y1))
        } else {
            p.addLine(to: CGPoint(x: bx, y: y1 - r))
            p.addQuadCurve(to: CGPoint(x: bx - r, y: y1), control: CGPoint(x: bx, y: y1))
        }
        p.addLine(to: CGPoint(x: x0 + r, y: y1))
        p.addQuadCurve(to: CGPoint(x: x0, y: y1 - r), control: CGPoint(x: x0, y: y1))
        p.addLine(to: CGPoint(x: x0, y: y0 + r))
        p.addQuadCurve(to: CGPoint(x: x0 + r, y: y0), control: CGPoint(x: x0, y: y0))
        p.closeSubpath()
        if isOutgoing { return p }
        return p.applying(CGAffineTransform(translationX: rect.width, y: 0).scaledBy(x: -1, y: 1))
    }
}

// MARK: - who it hurts

/// The pain, made specific and personal: pick the one person you wish
/// you'd written to and see the last thing you actually sent them. It's
/// the whole app in one row — and the answer is remembered, so every
/// later screen talks about this person instead of "the recipient".
private struct MissedPersonPage: View {
    @Binding var selection: String

    private var person: MissedPerson? { MissedPerson(rawValue: selection) }

    var body: some View {
        OnboardingPageLayout(
            title: "Who do you miss?",
            text: "Pick one. Baranov is built around getting a real letter to them.",
            demoLift: 36
        ) {
            VStack(spacing: 20) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 18) {
                    ForEach(MissedPerson.allCases) { option in
                        let isSelected = option.rawValue == selection
                        Button {
                            withAnimation(.snappy) { selection = option.rawValue }
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: option.symbolName)
                                    .font(.title2)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                                    .frame(width: 68, height: 68)
                                    .background(
                                        isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                                        in: Circle()
                                    )
                                Text(option.chipTitle)
                                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .sensoryFeedback(.selection, trigger: selection)

                lastMessageRow
            }
        }
    }

    /// The last thing they sent that person, drawn as the thread it lives
    /// in: a centered timestamp, the blue bubble, and "Delivered".
    @ViewBuilder private var lastMessageRow: some View {
        if let person {
            VStack(spacing: 4) {
                Text(person.lastMessage.ago)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
                MessageBubble(text: LocalizedStringKey(person.lastMessage.text), isOutgoing: true, reaction: person.lastMessageReaction)
                    .padding(.top, person.lastMessageReaction == nil ? 0 : 10)
                Text("Delivered")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 4)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .id(person.rawValue)
        } else {
            Text("Tap the person you'd write to if it were easy.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(height: 64)
        }
    }
}

// MARK: - arrival alerts

/// Sells the one notification worth having: a real preview of the alert
/// they're about to allow, addressed to the person they just picked. The
/// promise (arrivals and handoffs only, never marketing) is stated on the
/// page because it's the reason to say yes.
private struct AlertsPage: View {
    let person: MissedPerson?
    @State private var shown = false

    var body: some View {
        OnboardingPageLayout(
            title: "Know the moment it arrives.",
            text: "A ram can be days from the gate. We tap you when it gets there, or when a letter arrives for you. Never for promotions. Ever.",
            demoLift: 36
        ) {
            NotificationPreviewCard(
                title: String(localized: "Your ram is at \(person?.possessive ?? String(localized: "their")) gate"),
                message: String(localized: "The seal is waiting. Hold it to break it."),
                time: String(localized: "now"),
                fill: AnyShapeStyle(Color(.secondarySystemGroupedBackground))
            )
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : -24)
            .sensoryFeedback(.impact(weight: .light), trigger: shown)
            .task {
                shown = false
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { shown = true }
            }
        }
    }
}

// MARK: - the pain

/// The kind of inbox this app is a reaction to: messages that pile in,
/// get skimmed, and are gone. They arrive one after another, then dim —
/// nothing here was ever meant to be kept.
private struct PainPage: View {
    @State private var shown = 0
    @State private var dimmed = false
    @State private var showsQuestion = false

    private struct Line {
        let text: LocalizedStringKey
        let isOutgoing: Bool
        let showsTail: Bool
    }

    private let lines: [Line] = [
        Line(text: "hey", isOutgoing: false, showsTail: false),
        Line(text: "u up?", isOutgoing: false, showsTail: true),
        Line(text: "k", isOutgoing: true, showsTail: true),
        Line(text: "👍", isOutgoing: false, showsTail: true),
        Line(text: "lol ok", isOutgoing: true, showsTail: true),
    ]

    var body: some View {
        OnboardingPageLayout(
            title: "Everything arrives instantly.",
            text: "So nothing feels like it matters. When did you last hold a message someone made for you?"
        ) {
            ZStack {
            VStack(spacing: 3) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    MessageBubble(text: line.text, isOutgoing: line.isOutgoing, showsTail: line.showsTail)
                        .padding(.bottom, line.showsTail ? 6 : 0)
                        .opacity(index < shown ? (dimmed ? 0.35 : 1) : 0)
                        .offset(y: index < shown ? 0 : 12)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: shown)
                        .animation(.easeInOut(duration: 0.8), value: dimmed)
                }
            }
            .opacity(showsQuestion ? 0 : 1)
            .animation(.easeInOut(duration: 0.6), value: showsQuestion)

            Image(systemName: "questionmark")
                .font(.system(size: 132, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .rotationEffect(.degrees(showsQuestion ? -14 : 12))
                .scaleEffect(showsQuestion ? 1 : 0.6)
                .opacity(showsQuestion ? 1 : 0)
                .animation(.spring(response: 0.7, dampingFraction: 0.6), value: showsQuestion)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("A stream of instant messages arriving one after another, then fading into irrelevance")
            .task {
                shown = 0
                dimmed = false
                showsQuestion = false
                for _ in lines {
                    try? await Task.sleep(for: .milliseconds(420))
                    shown += 1
                }
                try? await Task.sleep(for: .milliseconds(900))
                dimmed = true
                try? await Task.sleep(for: .milliseconds(1100))
                showsQuestion = true
            }
        }
    }
}

// MARK: - the ram

private struct RamPage: View {
    let recipientLabel: String
    @State private var stepCount = 0

    var body: some View {
        OnboardingPageLayout(
            title: "A letter that has to be carried.",
            text: "Your ram walks it to \(recipientLabel). One of your real steps moves it one metre closer."
        ) {
            VStack(spacing: 14) {
                RamSpriteLoopView(frameNames: RamSpriteFrameSets.walkCycle, frameDuration: .milliseconds(80))
                    .frame(height: 190)

                HStack(spacing: 8) {
                    Image(systemName: "figure.walk")
                        .symbolEffect(.pulse, options: .repeating)
                    Text("\(stepCount) steps · \(stepCount) m")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .onboardingPill()

                Text("\"Baranov\" is the maker's surname — it means rams.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(height: 380, alignment: .top)
            .task {
                stepCount = 0
                while !Task.isCancelled, stepCount < 1_200 {
                    try? await Task.sleep(for: .milliseconds(500))
                    withAnimation(.linear(duration: 0.3)) {
                        stepCount += Int.random(in: 1...2)
                    }
                }
            }
        }
    }
}

// MARK: - the ocean

/// The two ways over water, shown together: a packet sailing below, and a
/// ram crossing phone to phone above. The point of the page is that the
/// boat is the guarantee and the person is the shortcut — a letter is
/// never stranded waiting for a stranger who may never come.
private struct OceanPage: View {
    let isActive: Bool
    let recipientLabel: String
    @State private var crossed = false
    /// Easter egg: really shaking the phone on this page hands the ram
    /// over on the spot.
    @State private var shakeDetector = ShakeDetector()
    @State private var shakeCount = 0
    @State private var showsHandover = false

    var body: some View {
        OnboardingPageLayout(
            title: "No road crosses an ocean.",
            text: "Your ram walks to a port and boards a packet — it crosses on its own. Shake phones with someone crossing sooner and it hops to their phone instead."
        ) {
            VStack(spacing: 14) {
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
                .frame(height: 190)

                HStack(spacing: 8) {
                    Image(systemName: showsHandover ? "checkmark.circle.fill" : "iphone.radiowaves.left.and.right")
                    Text(showsHandover ? "Handed over. Nice shake." : "Shake phones or AirDrop to hand off")
                }
                .onboardingPill()
                .contentTransition(.opacity)
                .animation(.snappy, value: showsHandover)

                // What it would look like for real: the hand-off arriving
                // on the other phone.
                NotificationPreviewCard(
                    title: String(localized: "A ram just hopped onto your phone"),
                    message: String(localized: "It's carrying a letter for \(recipientLabel). Take it across the water."),
                    time: String(localized: "now"),
                    fill: AnyShapeStyle(Color(.secondarySystemGroupedBackground))
                )
                .opacity(showsHandover ? 1 : 0)
                .offset(y: showsHandover ? 0 : 12)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showsHandover)
            }
            .frame(height: 380, alignment: .top)
            .sensoryFeedback(.impact(weight: .heavy), trigger: shakeCount)
            .sensoryFeedback(.success, trigger: showsHandover) { _, isShown in isShown }
            .onChange(of: isActive) { _, active in
                if active { startShakeDetection() } else { shakeDetector.stop() }
            }
            .onAppear { if isActive { startShakeDetection() } }
            .onDisappear { shakeDetector.stop() }
            .task {
                crossed = false
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(1400))
                    crossed.toggle()
                }
            }
        }
    }

    private func startShakeDetection() {
        shakeDetector.onShake = { _ in
            shakeCount += 1
            crossed.toggle()
            showsHandover = true
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                showsHandover = false
            }
        }
        shakeDetector.start()
    }

    private func phone(label: LocalizedStringKey, isShaking: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "iphone")
                .font(.system(size: 56, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isShaking ? Color.accentColor : Color.secondary)
                .symbolEffect(.wiggle, value: crossed)
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 90)
        }
    }
}

// MARK: - the seal

/// A working wax seal: hold it and cracks spread with soft ticks; at a
/// second and a half it shatters with the same heavy impact the real
/// arrival ritual uses, and the envelope opens. Resets a moment later so
/// it can be tried again. Same components as Compose and the gate
/// (`WaxSeal.swift`), so what's learned here is exactly what's used.
private struct SealPage: View {
    let person: MissedPerson?

    /// The note from the maker under the opened envelope: a little
    /// different for a partner or a sibling, warm and general otherwise.
    private var authorNote: LocalizedStringKey {
        switch person {
        case .partner:
            "Hi, I'm Anton. I built Baranov for the love letters that stayed in my head. If you're thinking of someone you love right now, tell them. Every step your ram takes is a small proof of it."
        case .sibling:
            "Hi, I'm Anton. Nobody knows your whole story like a sibling does, and somehow they're the ones we forget to write. Write to them. Let your ram carry everything you haven't said."
        default:
            "Hi, I'm Anton. I made Baranov because I kept meaning to write to the people I love, and never did. If this made you think of someone, that was my hope. Write to them. Your ram will carry it with care."
        }
    }

    @State private var progress: Double = 0
    @State private var isPressing = false
    @State private var isShattering = false
    @State private var isOpen = false
    @State private var breakTick = 0
    @State private var crackTick = 0
    @State private var crackTask: Task<Void, Never>?

    var body: some View {
        OnboardingPageLayout(
            title: "Sealed until it's home.",
            text: "Only the recipient's code breaks it. Hold the seal to try.",
            demoLift: 24
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(authorNote)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Anton")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
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
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { isOpen = true }
            try? await Task.sleep(for: .seconds(9))
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
