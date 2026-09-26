//
//  PasturePaywallView.swift
//  Baranov
//
//  Native, ethical paywall for "Expand the Pasture".
//
//  What it sells, and what it refuses to: one ram — writing, walking,
//  handing off, receiving, breaking the seal — is free forever and is
//  never gated here or anywhere. The pasture expansion is for people who
//  want to run five rams at once and seal in colours other than crimson;
//  adopting a ram is the one-time alternative for people who'd rather own
//  a second ram than rent a pasture. The screen only ever appears when
//  someone actually bumps into the limit (a third ram, a locked wax), not
//  on launch, not on a timer.
//
//  Styled after the highest-converting RevenueCat paywall patterns — a
//  bold hero badge, a clean checkmark feature list, and a real,
//  selectable package picker with an honest "SAVE X%" badge computed
//  from the actual fetched prices — but built entirely from native
//  System Materials and standard controls. No custom glass effects,
//  gradient borders, glow shadows, or third-party UI. The one gradient in
//  here is `Color.gradient`, SwiftUI's own vibrancy treatment, applied as
//  a plain fill.
//
//  With RevenueCat live, every price on screen is the App Store's; the
//  Customer Center (RevenueCatUI) handles cancel/refund/restore so none
//  of that had to be hand-built. Without a key, the picker shows clearly
//  labelled sample options and the mock flow unlocks the local store, so
//  the whole screen is still walkable end-to-end.
//

import Foundation
import RevenueCat
import RevenueCatUI
import SwiftUI

/// A modal paywall sheet offering the pasture expansion and ram adoption.
/// Present with `.sheet(isPresented:)` from anywhere in the app.
///
/// Built like the onboarding: every section is a small working
/// demonstration of what the purchase actually changes, not a bullet
/// list. The pasture at the top shows the person's own ram alone, then
/// — a beat after the sheet opens, and again whenever they pick a plan —
/// the locked pens open and more rams walk in. The wax row seals a real
/// envelope in whichever colour they tap. The plan toggle morphs the price
/// in place. Nothing here is a picture of a feature; it's the feature in
/// miniature.
struct PasturePaywallView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(EntitlementService.self) private var entitlementService
    @Environment(FlockViewModel.self) private var flockViewModel: FlockViewModel?
    @State private var viewModel = PasturePaywallViewModel()
    @State private var companionStore = RamCompanionStore()
    @State private var isCustomerCenterPresented = false
    @State private var unlockTick = 0

    /// How many pens the pasture scene is currently showing open — starts
    /// at what the person really has, then previews what the selected
    /// plan would give them.
    @State private var previewedSlots = 1
    @State private var hasRunIntro = false

    /// The wax the demo envelope is currently sealed with.
    @State private var demoWax: SealColor = .crimson
    @State private var waxTick = 0

    @State private var legalDocument: LegalDocument?
    private let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    private var companionName: String {
        companionStore.companion?.name ?? "Your ram"
    }

    /// Slots the selected option would unlock — what the scene previews.
    private var slotsForSelection: Int {
        guard let option = viewModel.selectedOption else { return entitlementService.allowedRamSlots }
        return option.isOneTime ? max(2, entitlementService.allowedRamSlots) : FlockViewModel.pastureCapacity
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    pastureScene
                    titleBlock
                    if entitlementService.hasPastureExpansion {
                        alreadyExpanded
                    } else {
                        planPicker
                    }
                    waxDemo
                    featureList
                    walkedSoFar
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 210)
            }
            .background(.regularMaterial)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Same standard close control as Pasture.
                ToolbarItem(placement: .topBarLeading) {
                    if #available(iOS 26.0, *) {
                        Button(role: .close) { dismiss() }
                    } else {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Close")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
            .alert(
                "Something Went Wrong",
                isPresented: $viewModel.showsError,
                presenting: viewModel.errorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .task {
                viewModel.entitlementService = entitlementService
                previewedSlots = entitlementService.allowedRamSlots
                await viewModel.loadOffering()
                await runIntroIfNeeded()
            }
            .onChange(of: viewModel.selectedOption?.id) { _, _ in
                guard hasRunIntro else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    previewedSlots = slotsForSelection
                }
            }
            .onChange(of: entitlementService.allowedRamSlots) { old, new in
                // A successful unlock: a real haptic, then the sheet goes
                // away so the person lands back in the pasture that just
                // grew, rather than on a paywall for something they own.
                guard new > old else { return }
                unlockTick += 1
                Task {
                    try? await Task.sleep(for: .milliseconds(650))
                    dismiss()
                }
            }
            .sensoryFeedback(.success, trigger: unlockTick)
            .sensoryFeedback(.impact(weight: .light), trigger: waxTick)
            .presentCustomerCenter(isPresented: $isCustomerCenterPresented)
        }
    }

    /// The beat that makes the sheet feel alive: a moment after it opens,
    /// the locked pens swing open and two more rams walk in, so the person
    /// sees the expansion before reading a word about it.
    private func runIntroIfNeeded() async {
        guard !hasRunIntro, !entitlementService.hasPastureExpansion else {
            hasRunIntro = true
            return
        }
        try? await Task.sleep(for: .milliseconds(700))
        withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
            previewedSlots = slotsForSelection
        }
        hasRunIntro = true
    }

    // MARK: - Pasture scene

    /// Sample rams shown in the pasture preview (every pen but the
    /// person's own). Routed through the string catalog — rather than a
    /// hardcoded English array — so a translated build shows names in
    /// that language's own script instead of Latin names sitting oddly
    /// next to Cyrillic, Chinese, etc. copy. English and Russian are
    /// filled in here; every other language falls back to the English
    /// name until translated in the catalog.
    private static var previewRamNames: [String] {
        [
            String(localized: "Juniper", comment: "Sample ram name shown in the paywall's pasture preview. A name that would suit a farm animal — keep all 5 preview ram names in the same language/script as each other when translating."),
            String(localized: "Basalt", comment: "Sample ram name shown in the paywall's pasture preview. See note on \"Juniper\": keep all 5 names in one language/script."),
            String(localized: "Thistle", comment: "Sample ram name shown in the paywall's pasture preview. See note on \"Juniper\": keep all 5 names in one language/script."),
            String(localized: "Clove", comment: "Sample ram name shown in the paywall's pasture preview. See note on \"Juniper\": keep all 5 names in one language/script."),
            String(localized: "Ember", comment: "Sample ram name shown in the paywall's pasture preview. See note on \"Juniper\": keep all 5 names in one language/script."),
        ]
    }

    private var pastureScene: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<FlockViewModel.pastureCapacity, id: \.self) { index in
                        PasturePenView(
                            index: index,
                            isOpen: index < previewedSlots,
                            isOwned: index < entitlementService.allowedRamSlots,
                            name: index == 0 ? companionName : Self.previewRamNames[index % Self.previewRamNames.count]
                        )
                        .frame(width: 64)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
            }
            .frame(height: 112)

            Text(sceneCaption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: previewedSlots)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var sceneCaption: LocalizedStringKey {
        switch previewedSlots {
        case ...1: return "Right now: \(companionName), one letter at a time."
        case 2: return "With an adopted ram: two letters out at once, for good."
        default: return "With the pasture expanded: five rams, five people, at the same time."
        }
    }

    // MARK: - Title

    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text("Expand the Pasture")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text("More rams out at once, and every colour of wax to seal them with.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Plan picker

    @ViewBuilder
    private var planPicker: some View {
        if viewModel.isLoadingOffering {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if viewModel.options.isEmpty {
            Text("Pricing unavailable right now")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else {
            VStack(spacing: 14) {
                planList

                if viewModel.isShowingSamplePricing {
                    Label("Sample pricing — RevenueCat isn't configured in this build.", systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// Every way to pay, as one list of equal-weight rows — a subscription
    /// and a one-time purchase side by side, nothing shouting. Selection is
    /// a plain primary stroke; the only accent on the whole screen is the
    /// button at the bottom.
    private var planList: some View {
        VStack(spacing: 10) {
            ForEach(viewModel.orderedOptions) { option in
                PlanRow(
                    option: option,
                    badge: viewModel.badge(for: option),
                    isSelected: viewModel.selectedOption?.id == option.id
                ) {
                    withAnimation(.snappy) { viewModel.selectedOption = option }
                }
            }
        }
    }

    // MARK: - Wax demo

    private var waxDemo: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.thickMaterial)
                        .frame(width: 96, height: 62)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(.secondary.opacity(0.3), lineWidth: 1)
                        )
                    Circle()
                        .fill(demoWax.color)
                        .frame(width: 26, height: 26)
                        .overlay(Image(systemName: "seal.fill").font(.caption).foregroundStyle(.white))
                        .id(demoWax)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Seal in \(demoWax.displayName.lowercased())")
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.opacity)
                    Text(demoWax.isIncludedFree
                         ? "Crimson is every shepherd's. Tap another wax."
                         : "Comes with the pasture. The recipient breaks the colour you chose.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                ForEach(SealColor.allCases) { wax in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { demoWax = wax }
                        waxTick += 1
                    } label: {
                        ZStack {
                            Circle().fill(wax.color).frame(width: 26, height: 26)
                            if demoWax == wax {
                                Circle().strokeBorder(.primary, lineWidth: 2).frame(width: 34, height: 34)
                            }
                            if !wax.isIncludedFree, !entitlementService.hasPastureExpansion {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                        }
                        .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(wax.displayName) wax")
                }
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Feature list

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatureRow(
                symbol: "pawprint.fill",
                title: "Five Rams at Once",
                subtitle: "Five letters walking to five people at the same time."
            )
            FeatureRow(
                symbol: "seal.fill",
                title: "Every Wax Colour, Plus Three Rare Ones",
                subtitle: "Gold to obsidian black — including three shimmering rare finishes and heirloom parchment."
            )
            FeatureRow(
                symbol: "lock.clock.fill",
                title: "Time-Capsules & Geo-Locks",
                subtitle: "Hold a letter for a future date, or lock it to a real spot on the ground."
            )
            FeatureRow(
                symbol: "sparkles",
                title: "Scratch-Off Secrets",
                subtitle: "Hide a second line behind a foil the recipient scratches clear by hand."
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Already subscribed

    private var alreadyExpanded: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
            Text("Your pasture is expanded")
                .font(.headline)
            Text("Five rams, every wax. Thank you for keeping a slow post alive.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - What you've walked

    /// Real numbers only: how far this person's rams have actually walked.
    /// Hidden until there's something to say, never a made-up stat.
    @ViewBuilder
    private var walkedSoFar: some View {
        if let flock = flockViewModel, flock.totalStepsWalked > 0 {
            HStack(spacing: 10) {
                Image(systemName: "figure.walk")
                    .foregroundStyle(.secondary)
                Text("Your rams have walked \(DistanceFormatter.string(forMeters: flock.totalStepsWalked)) so far.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Actions

    private var ctaTitle: LocalizedStringKey {
        guard let option = viewModel.selectedOption else { return "Continue" }
        if option.isOneTime { return "Adopt a Ram" }
        return option.hasIntroductoryOffer ? "Start Free Week" : "Expand the Pasture"
    }

    private var ctaSubtitle: LocalizedStringKey? {
        guard let option = viewModel.selectedOption, option.hasIntroductoryOffer else { return nil }
        let priceLine = option.periodDescription.isEmpty
            ? option.priceString
            : "\(option.priceString) \(option.periodDescription)"
        return "Then \(priceLine). Cancel anytime."
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            if entitlementService.hasPastureExpansion {
                if entitlementService.isLive {
                    Button {
                        isCustomerCenterPresented = true
                    } label: {
                        Text("Manage Subscription")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .buttonBorderShape(.roundedRectangle(radius: 16))
                }
            } else {
                if let ctaSubtitle {
                    Text(ctaSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await viewModel.purchase() }
                } label: {
                    Group {
                        if viewModel.isPurchasing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(ctaTitle)
                                .font(.headline)
                                .contentTransition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                .disabled(viewModel.isPurchasing || viewModel.isRestoring || viewModel.selectedOption == nil)
                .animation(.snappy, value: ctaTitle)
            }

            Text("One ram is free, forever. No letter is ever behind this screen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button {
                    Task { await viewModel.restore() }
                } label: {
                    if viewModel.isRestoring {
                        ProgressView()
                    } else {
                        Text("Restore Purchases")
                    }
                }
                .disabled(viewModel.isPurchasing || viewModel.isRestoring)

                Text("·")
                    .foregroundStyle(.tertiary)
                Button("Privacy") { legalDocument = .privacy }
                Text("·")
                    .foregroundStyle(.tertiary)
                Link("Terms", destination: termsOfUseURL)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 2)

            Text("For RevenueCat Shipaton 2026 · Anton Baranov @antnbaranov")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
        .sheet(item: $legalDocument) { LegalDocumentView(document: $0) }
    }
}

// MARK: - Plan row

/// One way to pay. Same shape for a subscription and for adopting a ram,
/// so neither reads as the "real" option and the other as an afterthought.
private struct PlanRow: View {
    let option: PaywallOption
    let badge: String?
    let isSelected: Bool
    let onTap: () -> Void

    private var subtitle: LocalizedStringKey {
        if option.isOneTime {
            return "Pay once. A second ram, yours for good."
        }
        if option.hasIntroductoryOffer {
            return "7 days free, then \(option.priceString) \(option.periodDescription). Cancel anytime."
        }
        return "\(option.priceString) \(option.periodDescription). Cancel anytime."
    }

    private var title: LocalizedStringKey {
        if option.isOneTime {
            return "Adopt a Ram"
        } else {
            return "Expand the Pasture · \(option.title)"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.4))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let badge {
                        // Its own line, after the full title text — never
                        // inline with it, so a long localized title (e.g.
                        // "Expand the Pasture · Annual" in Russian) can
                        // wrap to two lines without the badge landing in
                        // the middle of it.
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.thinMaterial, in: Capsule())
                            .foregroundStyle(.primary)
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(option.priceString)
                        .font(.headline.monospacedDigit())
                    Text(option.isOneTime ? "once" : option.shortPeriod)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(option.priceString) \(option.isOneTime ? "once" : option.periodDescription)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Pasture pen

/// One pen in the paywall's pasture scene. Closed: a dashed fence and a
/// lock. Open: the lock fades and a ram walks in from the left, each pen
/// a beat after the last, then settles into a slow idle. The first pen is
/// always the person's own ram.
private struct PasturePenView: View {
    let index: Int
    let isOpen: Bool
    let isOwned: Bool
    let name: String

    @State private var hasArrived = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: isOpen ? [] : [5, 4]))
                    .foregroundStyle(isOpen ? Color.primary.opacity(0.35) : Color.secondary.opacity(0.35))
                    .animation(.easeInOut(duration: 0.4), value: isOpen)

                if isOpen {
                    RamSpriteLoopView(
                        frameNames: hasArrived ? RamSpriteFrameSets.idleHold : RamSpriteFrameSets.walkCycle,
                        frameDuration: hasArrived ? .milliseconds(520) : .milliseconds(80)
                    )
                    .frame(height: 46)
                    .padding(.horizontal, 3)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .task {
                        hasArrived = false
                        try? await Task.sleep(for: .milliseconds(900 + index * 200))
                        hasArrived = true
                    }
                } else {
                    Image(systemName: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .animation(.spring(response: 0.7, dampingFraction: 0.8).delay(Double(index) * 0.14), value: isOpen)

            Text(isOpen ? name : (isOwned ? "Open" : "Locked"))
                .font(.system(size: 10, weight: isOpen ? .semibold : .regular))
                .foregroundStyle(isOpen ? .primary : .tertiary)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isOpen ? "\(name), pen open" : "Locked pen")
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    @State private var bounce = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 26)
                .symbolEffect(.bounce, value: bounce)
                .task {
                    try? await Task.sleep(for: .milliseconds(1_500))
                    bounce += 1
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Paywall option

/// One purchasable thing on the screen. Wraps a live RevenueCat `Package`
/// when the SDK is configured, or carries sample values when it isn't —
/// so the picker, the badge math and the CTA are the same code either
/// way, and nothing on the view layer ever touches `Purchases` directly.
struct PaywallOption: Identifiable {
    let id: String
    let title: String
    let periodDescription: String
    let priceString: String
    /// Real decimal price, used only to rank options against each other.
    let price: Decimal
    /// Approximate days the price covers; `nil` for a one-time purchase.
    let approximateDays: Double?
    let hasIntroductoryOffer: Bool
    let isOneTime: Bool
    let package: Package?

    /// "/ year", "/ month" — the price's small suffix in a plan row.
    var shortPeriod: String {
        switch approximateDays {
        case 7: return "/ week"
        case 30: return "/ month"
        case 365: return "/ year"
        default: return periodDescription
        }
    }

    /// Price per week, for comparing subscriptions honestly.
    var normalizedWeeklyPrice: Decimal? {
        guard let approximateDays, approximateDays > 0 else { return nil }
        return price / Decimal(approximateDays) * 7
    }

    init(package: Package) {
        let product = package.storeProduct
        id = package.identifier
        switch package.packageType {
        case .weekly:
            title = "Weekly"; periodDescription = "per week"; approximateDays = 7
        case .monthly:
            title = "Monthly"; periodDescription = "per month"; approximateDays = 30
        case .twoMonth:
            title = "Every 2 Months"; periodDescription = "every 2 months"; approximateDays = 60
        case .threeMonth:
            title = "Every 3 Months"; periodDescription = "every 3 months"; approximateDays = 90
        case .sixMonth:
            title = "Every 6 Months"; periodDescription = "every 6 months"; approximateDays = 180
        case .annual:
            title = "Annual"; periodDescription = "per year"; approximateDays = 365
        case .lifetime:
            title = "Adopt a Ram"; periodDescription = "one-time purchase"; approximateDays = nil
        default:
            if product.subscriptionPeriod == nil {
                title = "Adopt a Ram"; periodDescription = "one-time purchase"; approximateDays = nil
            } else {
                title = product.localizedTitle.isEmpty ? "Custom" : product.localizedTitle
                periodDescription = ""; approximateDays = nil
            }
        }
        priceString = product.localizedPriceString
        price = product.price
        hasIntroductoryOffer = product.introductoryDiscount != nil
        isOneTime = product.subscriptionPeriod == nil
        self.package = package
    }

    /// A sample option for builds with no RevenueCat key.
    init(sampleID: String, title: String, periodDescription: String, priceString: String, price: Decimal, approximateDays: Double?, hasIntroductoryOffer: Bool = false) {
        id = sampleID
        self.title = title
        self.periodDescription = periodDescription
        self.priceString = priceString
        self.price = price
        self.approximateDays = approximateDays
        self.hasIntroductoryOffer = hasIntroductoryOffer
        isOneTime = approximateDays == nil
        package = nil
    }
}

// MARK: - View Model

/// Drives the paywall's offering lookup, option selection, purchase, and
/// restore flows.
///
/// When RevenueCat has not been configured for the running build (no API
/// key yet), the picker shows clearly labelled sample options and
/// purchases run a short mock flow that flips `MockEntitlementStore`, so
/// the UI remains fully navigable during development and design review
/// — it never calls into an unconfigured `Purchases` singleton.
@MainActor
@Observable
final class PasturePaywallViewModel {

    /// Injected by `PasturePaywallView` once the environment is available.
    /// `refresh()` is called on it after any purchase/restore/mock-unlock
    /// so `FlockViewModel.maxAllowedRams` actually updates, not just the
    /// paywall's own local state.
    var entitlementService: EntitlementService?

    private(set) var options: [PaywallOption] = []
    var selectedOption: PaywallOption?

    private(set) var isLoadingOffering = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var isShowingSamplePricing = false

    var showsError = false
    private(set) var errorMessage: String?

    var subscriptionOptions: [PaywallOption] { options.filter { !$0.isOneTime } }
    var oneTimeOptions: [PaywallOption] { options.filter { $0.isOneTime } }

    /// Rows in the order they're shown: best-value subscription first, the
    /// other subscriptions, then the one-time adoption last but equal.
    var orderedOptions: [PaywallOption] {
        let subs = subscriptionOptions.sorted { ($0.normalizedWeeklyPrice ?? 0) < ($1.normalizedWeeklyPrice ?? 0) }
        return subs + oneTimeOptions
    }

    func loadOffering() async {
        guard Purchases.isConfigured else {
            options = Self.sampleOptions
            isShowingSamplePricing = true
            selectedOption = bestValueSubscription() ?? options.first
            return
        }

        isLoadingOffering = true
        defer { isLoadingOffering = false }

        do {
            let offerings = try await Purchases.shared.offerings()
            guard let current = offerings.current else { return }
            options = current.availablePackages.map(PaywallOption.init(package:))
            #if DEBUG
            // Prices here come from the RevenueCat offering, not from the
            // local .storekit file. If these lines show old IDs/prices, the
            // RevenueCat dashboard (Products / Offerings) is what to update.
            for package in current.availablePackages {
                print("[Paywall] offering '\(current.identifier)' package \(package.identifier) → \(package.storeProduct.productIdentifier) \(package.storeProduct.localizedPriceString)")
            }
            #endif
            selectedOption = bestValueSubscription() ?? options.first
        } catch {
            // Non-fatal: the picker falls back to a "pricing unavailable"
            // label; RevenueCat's own cache usually answers offline anyway.
        }
    }

    func purchase() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        guard let selectedOption else {
            present(error: "This offer isn't available right now. Please try again later.")
            return
        }

        guard Purchases.isConfigured, let package = selectedOption.package else {
            await mockPurchase(selectedOption)
            return
        }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled { return }
            if result.customerInfo.entitlements.active.isEmpty {
                present(error: "Your purchase couldn't be completed. Please try again.")
            } else {
                // `EntitlementService`'s delegate callback will catch this
                // too, but refreshing explicitly means the pasture unlocks
                // immediately rather than waiting on it.
                await entitlementService?.refresh()
            }
        } catch {
            present(error: "Your purchase couldn't be completed. Please try again.")
        }
    }

    func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        guard Purchases.isConfigured else {
            present(error: "Purchases aren't configured in this build.")
            return
        }

        do {
            _ = try await Purchases.shared.restorePurchases()
            await entitlementService?.refresh()
        } catch {
            present(error: "We couldn't restore your purchases. Please try again.")
        }
    }

    /// "SAVE X%" for whichever subscription works out cheapest per week
    /// once every option's real price is normalized to a common period —
    /// or nil when there's nothing to usefully compare. Computed entirely
    /// from the actual fetched prices, never a placeholder figure.
    func badge(for option: PaywallOption) -> String? {
        let comparable = subscriptionOptions.compactMap { candidate -> (PaywallOption, Decimal)? in
            guard let weekly = candidate.normalizedWeeklyPrice else { return nil }
            return (candidate, weekly)
        }
        guard comparable.count > 1,
              let thisWeekly = option.normalizedWeeklyPrice,
              let mostExpensive = comparable.map(\.1).max(),
              mostExpensive > 0,
              thisWeekly < mostExpensive
        else { return nil }

        let ratio = Double(truncating: (thisWeekly / mostExpensive) as NSDecimalNumber)
        let percentOff = Int(((1 - ratio) * 100).rounded())
        guard percentOff >= 5 else { return nil }
        return "Best value · save \(percentOff)%"
    }

    /// The subscription with the lowest normalized weekly price — what
    /// the selection defaults to when there's more than one to rank.
    private func bestValueSubscription() -> PaywallOption? {
        let scored = subscriptionOptions.compactMap { option -> (PaywallOption, Decimal)? in
            guard let weekly = option.normalizedWeeklyPrice else { return nil }
            return (option, weekly)
        }
        guard scored.count > 1 else { return subscriptionOptions.first }
        return scored.min(by: { $0.1 < $1.1 })?.0
    }

    /// Simulates a brief purchase flow for builds where RevenueCat has
    /// not been configured, so the paywall remains testable end-to-end
    /// without a live SDK connection.
    private func mockPurchase(_ option: PaywallOption) async {
        try? await Task.sleep(for: .seconds(1))
        if option.isOneTime {
            MockEntitlementStore.hasAdoptedRam = true
        } else {
            MockEntitlementStore.hasPastureExpansion = true
        }
        await entitlementService?.refresh()
        #if DEBUG
        print("[PasturePaywallView] Mock purchase of \(option.id) completed — RevenueCat is not configured in this build.")
        #endif
    }

    private func present(error message: String) {
        errorMessage = message
        showsError = true
    }

    /// Sample options mirroring the products in `Baranov.storekit` and the
    /// RevenueCat dashboard — for design review and demos without a key.
    private static var sampleOptions: [PaywallOption] {
        [
            PaywallOption(sampleID: RevenueCatConfiguration.ProductID.pastureMonthly, title: "Monthly", periodDescription: "per month", priceString: "$2.99", price: 2.99, approximateDays: 30),
            PaywallOption(sampleID: RevenueCatConfiguration.ProductID.pastureQuarterly, title: "Every 3 Months", periodDescription: "every 3 months", priceString: "$5.99", price: 5.99, approximateDays: 90),
            PaywallOption(sampleID: RevenueCatConfiguration.ProductID.pastureAnnual, title: "Annual", periodDescription: "per year", priceString: "$19.99", price: 19.99, approximateDays: 365, hasIntroductoryOffer: true),
            PaywallOption(sampleID: RevenueCatConfiguration.ProductID.adoptRam, title: "Adopt a Ram", periodDescription: "one-time purchase", priceString: "$2.99", price: 2.99, approximateDays: nil),
        ]
    }
}

#Preview {
    PasturePaywallView()
        .environment(EntitlementService())
}
