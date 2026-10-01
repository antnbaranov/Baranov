//
//  PasturePaywallView.swift
//  Baranov
//
//  Native, ethical paywall for "Expand the Pasture".
//
//  What it sells, and what it refuses to: one ram — writing, walking,
//  handing off, receiving, breaking the seal — is free forever and is
//  never gated here or anywhere. The pasture expansion is for people who
//  want to run five rams at once;
//  adopting a ram is the one-time alternative for people who'd rather own
//  a second ram than rent a pasture. The screen only ever appears when
//  someone actually bumps into the limit (a third ram), not
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
import StoreKit
import SwiftUI

/// A modal paywall sheet offering the pasture expansion and ram adoption.
/// Present with `.sheet(isPresented:)` from anywhere in the app.
///
/// Built like the onboarding: every section is a small working
/// demonstration of what the purchase actually changes, not a bullet
/// list. The pasture at the top shows the person's own ram alone, then
/// — a beat after the sheet opens, and again whenever they pick a plan —
/// the locked pens open and more rams walk in. The plan toggle morphs the price
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

    /// The wax the paywall's seal demo is currently showing.
    @State private var demoWax: SealColor = .crimson
    @State private var waxTick = 0

    /// How many pens the pasture scene is currently showing open — starts
    /// at what the person really has, then previews what the selected
    /// plan would give them.
    @State private var previewedSlots = 1
    @State private var hasRunIntro = false

    @State private var legalDocument: LegalDocument?
    @State private var isRedeemSheetPresented = false

    private var companionName: String {
        companionStore.companion?.name ?? String(localized: "Your ram", bundle: .appLanguage, locale: .appLanguage)
    }

    /// Slots the selected option would unlock — what the scene previews.
    private var slotsForSelection: Int {
        guard let option = viewModel.activeOption else { return entitlementService.allowedRamSlots }
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
                    PaywallUnlockShowcase()
                    waxDemo
                    scratchDemo
                    if !entitlementService.hasPastureExpansion {
                        promoCodeCard
                    }
                    walkedSoFar
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 210)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .offerCodeRedemption(isPresented: $isRedeemSheetPresented) { result in
                if case .success = result {
                    Task { await entitlementService.refresh() }
                }
            }
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
            String(localized: "Juniper", bundle: .appLanguage, locale: .appLanguage, comment: "Sample ram name shown in the paywall's pasture preview. A name that would suit a farm animal — keep all 5 preview ram names in the same language/script as each other when translating."),
            String(localized: "Basalt", bundle: .appLanguage, locale: .appLanguage, comment: "Sample ram name shown in the paywall's pasture preview. See note on \"Juniper\": keep all 5 names in one language/script."),
            String(localized: "Thistle", bundle: .appLanguage, locale: .appLanguage, comment: "Sample ram name shown in the paywall's pasture preview. See note on \"Juniper\": keep all 5 names in one language/script."),
            String(localized: "Clove", bundle: .appLanguage, locale: .appLanguage, comment: "Sample ram name shown in the paywall's pasture preview. See note on \"Juniper\": keep all 5 names in one language/script."),
            String(localized: "Ember", bundle: .appLanguage, locale: .appLanguage, comment: "Sample ram name shown in the paywall's pasture preview. See note on \"Juniper\": keep all 5 names in one language/script."),
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
                            name: index == 0 ? companionName : Self.previewRamNames[index % Self.previewRamNames.count],
                            color: RamColor.defaultColor(forSlot: index)
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
        .paywallCard(cornerRadius: 22)
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

            Text("More rams out at once, each with a name of its own.")
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
            unavailablePlans
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

    /// The store didn't answer (offline, or the offering isn't reachable
    /// right now). The two subscriptions still show, so the person knows
    /// what is on offer, with a way to ask the store again. Nothing here is
    /// purchasable until real prices arrive.
    private var unavailablePlans: some View {
        VStack(spacing: 10) {
            ForEach([
                (String(localized: "Annual", bundle: .appLanguage, locale: .appLanguage), String(localized: "/ year", bundle: .appLanguage, locale: .appLanguage)),
                (String(localized: "Monthly", bundle: .appLanguage, locale: .appLanguage), String(localized: "/ month", bundle: .appLanguage, locale: .appLanguage)),
            ], id: \.0) { plan in
                HStack(spacing: 12) {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(Color.secondary.opacity(0.4))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Expand the Pasture · \(plan.0)")
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Pricing unavailable right now")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(plan.1)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .accessibilityElement(children: .combine)
            }

            Button {
                Task { await viewModel.loadOffering() }
            } label: {
                Label("Try again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(ShareCodeGlassButtonStyle(expands: true))

            if let diagnostic = viewModel.loadDiagnostic, PasturePaywallViewModel.showsDiagnostics {
                Text(diagnostic)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
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
                let isOwned = option.isOneTime && entitlementService.hasSecondRam
                PlanRow(
                    option: option,
                    badge: viewModel.badge(for: option),
                    isSelected: !isOwned && viewModel.activeOption?.id == option.id,
                    isOwned: isOwned
                ) {
                    guard !isOwned else { return }
                    withAnimation(.snappy) { viewModel.selectedOption = option }
                }
            }
        }
    }

    // MARK: - Scratch-off demo

    /// The same full-width, standalone treatment the wax row used to get:
    /// one real, working feature front and center, not a card buried in a
    /// strip — this is the actual `ScratchOffRevealView` used on a real
    /// arrival, just placed here with a throwaway secret to try.
    private var scratchDemo: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Scratch-off secrets")
                    .font(.subheadline.weight(.semibold))
                Text("A second line the recipient uncovers by hand. Try it below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScratchOffRevealView(secretText: String(localized: "P.S. I still have your umbrella.", bundle: .appLanguage, locale: .appLanguage))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paywallCard()
    }

    // MARK: - Promo code

    /// Where App Store offer codes and gift-card codes go: Apple's own
    /// redeem sheet, presented directly. It takes the code itself and the
    /// new entitlement then arrives through RevenueCat as usual.
    private var promoCodeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Promo code")
                .font(.subheadline.weight(.semibold))
            Button {
                isRedeemSheetPresented = true
            } label: {
                Label("Redeem", systemImage: "gift")
            }
            .buttonStyle(ShareCodeGlassButtonStyle(expands: true))
            Text("App Store and gift card codes open Apple's own redeem sheet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paywallCard()
    }

    // MARK: - Wax demo

    /// The wax the recipient breaks. A real `WaxSealView` on a small
    /// envelope, with every colour one tap away; the rare finishes shimmer
    /// as the phone tilts, exactly as they do on a real letter.
    private var waxDemo: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .systemGroupedBackground))
                    .frame(width: 104, height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(uiColor: .separator), lineWidth: 0.5)
                    )
                    .overlay {
                        WaxSealView(
                            wax: demoWax,
                            monogram: String(companionName.prefix(1)).uppercased(),
                            diameter: 44
                        )
                        .id(demoWax)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Seal it in \(demoWax.displayName.lowercased())")
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.opacity)
                    Text(demoWax.hasShimmer
                         ? "Catches the light, even before you tilt the phone."
                         : "Crimson is free. The recipient breaks the colour you chose.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SealColor.allCases) { wax in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) { demoWax = wax }
                            waxTick += 1
                        } label: {
                            ZStack {
                                Circle().fill(wax.color).frame(width: 26, height: 26)
                                if demoWax == wax {
                                    Circle().strokeBorder(.primary, lineWidth: 2).frame(width: 34, height: 34)
                                }
                            }
                            .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(wax.displayName) wax")
                        .accessibilityAddTraits(demoWax == wax ? .isSelected : [])
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paywallCard()
        .sensoryFeedback(.selection, trigger: waxTick)
    }

    // MARK: - Already subscribed

    private var alreadyExpanded: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(.primary)
                .symbolRenderingMode(.hierarchical)
            Text("Your pasture is expanded")
                .font(.headline)
            Text("Five rams out at once. Thank you for keeping a slow post alive.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .paywallCard()
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
        guard let option = viewModel.activeOption else { return "Continue" }
        if option.isOneTime { return entitlementService.hasSecondRam ? "Purchased" : "Adopt a Second Ram" }
        // Only a free trial this person can actually get changes the button;
        // `introOffer` is cleared when RevenueCat says they're not eligible.
        return option.introOffer?.isFreeTrial == true ? "Start free trial" : "Expand the Pasture"
    }

    private var ctaSubtitle: LocalizedStringKey? {
        guard let option = viewModel.activeOption,
              let offer = option.introOffer, offer.isFreeTrial else { return nil }
        return "\(offer.duration) free, then \(option.priceString) \(option.periodDescription). Cancel anytime."
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
                .disabled(viewModel.isPurchasing || viewModel.isRestoring || viewModel.activeOption == nil)
                .animation(.snappy, value: ctaTitle)
            }

            Text("One ram is free, forever. No letter is ever behind this screen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !entitlementService.hasPastureExpansion, viewModel.activeOption?.isOneTime == false {
                // Auto-renewal terms next to the button that starts the subscription.
                Text("Subscriptions renew automatically unless cancelled at least 24 hours before the period ends. Manage or cancel in Settings.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

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
                Button("Terms") { legalDocument = .terms }
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
    /// One-time ram already bought: shown as done, not selectable.
    var isOwned: Bool = false
    let onTap: () -> Void

    private var subtitle: LocalizedStringKey {
        if option.isOneTime {
            return "Pay once. A second ram, yours for good."
        }
        if let offer = option.introOffer, offer.isFreeTrial {
            return "\(offer.duration) free, then \(option.priceString) \(option.periodDescription). Cancel anytime."
        }
        return "\(option.priceString) \(option.periodDescription). Cancel anytime."
    }

    private var title: LocalizedStringKey {
        if option.isOneTime {
            return "Adopt a Second Ram"
        } else {
            return "Expand the Pasture · \(option.title)"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: (isSelected || isOwned) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOwned ? Color.secondary : (isSelected ? Color.primary : Color.secondary.opacity(0.4)))

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
                            .background(Color(uiColor: .systemGray5), in: Capsule())
                            .foregroundStyle(.primary)
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    if isOwned {
                        Text("Purchased")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(option.priceString)
                            .font(.headline.monospacedDigit())
                        Text(option.isOneTime ? "once" : option.shortPeriod)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isOwned)
        .accessibilityLabel(isOwned
            ? "\(title), \(String(localized: "Purchased", bundle: .appLanguage, locale: .appLanguage))"
            : "\(title), \(option.priceString) \(option.isOneTime ? String(localized: "once", bundle: .appLanguage, locale: .appLanguage) : option.periodDescription)")
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
    /// Showcase wool color for this pen's ram: the first pen is always
    /// the person's white ram, later pens show the colors on offer.
    var color: RamColor = .white

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
                        frameNames: hasArrived ? RamSpriteFrameSets.idleFrames(for: color) : RamSpriteFrameSets.walkFrames(for: color),
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

            Text(isOpen ? name : (isOwned ? String(localized: "Open", bundle: .appLanguage, locale: .appLanguage) : String(localized: "Locked", bundle: .appLanguage, locale: .appLanguage)))
                .font(.system(size: 10, weight: isOpen ? .semibold : .regular))
                .foregroundStyle(isOpen ? .primary : .tertiary)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isOpen ? "\(name), pen open" : "Locked pen")
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
    /// The product's introductory offer, only while this person is eligible
    /// for it (see `PasturePaywallViewModel.applyIntroEligibility`). The
    /// paywall's trial wording is built from it, never hard-coded.
    var introOffer: IntroOffer?
    let isOneTime: Bool
    let package: Package?
    /// The store product, kept so a plan can still be bought when it came straight
    /// from StoreKit rather than from a RevenueCat offering package.
    let storeProduct: StoreProduct?

    var hasIntroductoryOffer: Bool { introOffer != nil }

    /// A trial or discounted first period, as the store describes it.
    struct IntroOffer {
        /// Free trial (as opposed to a discounted first period).
        let isFreeTrial: Bool
        /// "1 week", "3 days", "1 month" in the app's language.
        let duration: String

        init(isFreeTrial: Bool, duration: String) {
            self.isFreeTrial = isFreeTrial
            self.duration = duration
        }

        init(discount: StoreProductDiscount) {
            isFreeTrial = discount.paymentMode == .freeTrial
            let period = discount.subscriptionPeriod
            let count = period.value * max(1, discount.numberOfPeriods)
            var components = DateComponents()
            switch period.unit {
            case .day: components.day = count
            case .week: components.weekOfMonth = count
            case .month: components.month = count
            case .year: components.year = count
            }
            duration = Self.format(components)
        }

        static func format(_ components: DateComponents) -> String {
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .full
            formatter.maximumUnitCount = 1
            formatter.allowedUnits = [.day, .weekOfMonth, .month, .year]
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = .appLanguage
            formatter.calendar = calendar
            return formatter.string(from: components) ?? ""
        }
    }

    /// "/ year", "/ month" — the price's small suffix in a plan row.
    var shortPeriod: String {
        switch approximateDays {
        case 7: return String(localized: "/ week", bundle: .appLanguage, locale: .appLanguage)
        case 30: return String(localized: "/ month", bundle: .appLanguage, locale: .appLanguage)
        case 365: return String(localized: "/ year", bundle: .appLanguage, locale: .appLanguage)
        default: return periodDescription
        }
    }

    /// Price per week, for comparing subscriptions honestly.
    var normalizedWeeklyPrice: Decimal? {
        guard let approximateDays, approximateDays > 0 else { return nil }
        return price / Decimal(approximateDays) * 7
    }

    init(package: Package) {
        self.init(product: package.storeProduct, id: package.identifier, package: package)
    }

    init(product: StoreProduct, id: String, package: Package?) {
        self.id = id
        // The billing period comes from the store product itself, not from the
        // package type: a package with a custom identifier (or a product id
        // like `monthly`) has type `.custom`, which used to lose its period,
        // its savings badge and its "best value" ranking.
        let days: Double? = product.subscriptionPeriod.map { period in
            switch period.unit {
            case .day: Double(period.value)
            case .week: Double(period.value * 7)
            case .month: Double(period.value * 30)
            case .year: Double(period.value * 365)
            }
        }
        switch days {
        case nil:
            title = String(localized: "Adopt a Second Ram", bundle: .appLanguage, locale: .appLanguage); periodDescription = String(localized: "one-time purchase", bundle: .appLanguage, locale: .appLanguage); approximateDays = nil
        case 7:
            title = String(localized: "Weekly", bundle: .appLanguage, locale: .appLanguage); periodDescription = String(localized: "per week", bundle: .appLanguage, locale: .appLanguage); approximateDays = 7
        case 30:
            title = String(localized: "Monthly", bundle: .appLanguage, locale: .appLanguage); periodDescription = String(localized: "per month", bundle: .appLanguage, locale: .appLanguage); approximateDays = 30
        case 60:
            title = String(localized: "Every 2 Months", bundle: .appLanguage, locale: .appLanguage); periodDescription = String(localized: "every 2 months", bundle: .appLanguage, locale: .appLanguage); approximateDays = 60
        case 90:
            title = String(localized: "Every 3 Months", bundle: .appLanguage, locale: .appLanguage); periodDescription = String(localized: "every 3 months", bundle: .appLanguage, locale: .appLanguage); approximateDays = 90
        case 180:
            title = String(localized: "Every 6 Months", bundle: .appLanguage, locale: .appLanguage); periodDescription = String(localized: "every 6 months", bundle: .appLanguage, locale: .appLanguage); approximateDays = 180
        case 365:
            title = String(localized: "Annual", bundle: .appLanguage, locale: .appLanguage); periodDescription = String(localized: "per year", bundle: .appLanguage, locale: .appLanguage); approximateDays = 365
        default:
            title = product.localizedTitle.isEmpty ? String(localized: "Custom", bundle: .appLanguage, locale: .appLanguage) : product.localizedTitle
            periodDescription = ""; approximateDays = days
        }
        priceString = product.localizedPriceString
        price = product.price
        introOffer = product.introductoryDiscount.map(IntroOffer.init(discount:))
        isOneTime = product.subscriptionPeriod == nil
        self.package = package
        storeProduct = product
    }

    /// A sample option for builds with no RevenueCat key.
    init(sampleID: String, title: String, periodDescription: String, priceString: String, price: Decimal, approximateDays: Double?, hasIntroductoryOffer: Bool = false) {
        id = sampleID
        self.title = title
        self.periodDescription = periodDescription
        self.priceString = priceString
        self.price = price
        self.approximateDays = approximateDays
        introOffer = hasIntroductoryOffer
            ? IntroOffer(isFreeTrial: true, duration: IntroOffer.format(DateComponents(weekOfMonth: 1)))
            : nil
        isOneTime = approximateDays == nil
        package = nil
        storeProduct = nil
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

    /// What the button acts on. If the ram is already owned it can't be the
    /// target, so fall back to the best subscription: the primary button
    /// stays live for Annual/Monthly no matter what was bought before.
    var activeOption: PaywallOption? {
        if let selectedOption, !(selectedOption.isOneTime && entitlementService?.hasSecondRam == true) {
            return selectedOption
        }
        return bestValueSubscription() ?? subscriptionOptions.first ?? selectedOption
    }

    private(set) var isLoadingOffering = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var isShowingSamplePricing = false
    /// Why the last offering load came back empty (debug builds show it under "Try again").
    private(set) var loadDiagnostic: String?

    /// Debug and TestFlight builds only; App Store users never see raw diagnostics.
    static var showsDiagnostics: Bool {
        #if DEBUG
        true
        #else
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

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

        var loaded: [PaywallOption] = []
        var diagnostic = ""

        // 1. The RevenueCat offering (the normal path).
        do {
            let offerings = try await Purchases.shared.offerings()
            // Prefer the current offering; fall back to any offering that actually has packages.
            if let current = offerings.current.flatMap({ $0.availablePackages.isEmpty ? nil : $0 })
                ?? offerings.all.values.first(where: { !$0.availablePackages.isEmpty }) {
                // Show exactly the products Baranov sells. A leftover product in the
                // offering stays hidden; if none of ours are in it, show what it has.
                let known = current.availablePackages.filter {
                    RevenueCatConfiguration.ProductID.all.contains($0.storeProduct.productIdentifier)
                }
                loaded = (known.isEmpty ? current.availablePackages : known).map(PaywallOption.init(package:))
                #if DEBUG
                for package in current.availablePackages {
                    print("[Paywall] offering '\(current.identifier)' package \(package.identifier) → \(package.storeProduct.productIdentifier) \(package.storeProduct.localizedPriceString)")
                }
                #endif
            } else {
                diagnostic = "Offering has no packages (current=\(offerings.current?.identifier ?? "nil"), offerings=\(offerings.all.keys.sorted()))."
            }
        } catch {
            diagnostic = "offerings() failed: \(error.localizedDescription)."
            #if DEBUG
            print("[Paywall] offerings() failed: \(error)")
            #endif
        }

        // 2. Fallback: ask the store for Baranov's three products directly, so a
        // missing or cached-empty offering can't leave the paywall blank.
        if loaded.isEmpty {
            let products = await Purchases.shared.products(Array(RevenueCatConfiguration.ProductID.all))
            loaded = products.map { PaywallOption(product: $0, id: $0.productIdentifier, package: nil) }
            if loaded.isEmpty {
                diagnostic += " The store returned none of \(RevenueCatConfiguration.ProductID.all.sorted())."
            }
            #if DEBUG
            print("[Paywall] direct product fetch → \(products.map(\.productIdentifier))")
            #endif
        }

        guard !loaded.isEmpty else {
            loadDiagnostic = diagnostic
            #if DEBUG
            print("[Paywall] \(diagnostic)")
            #endif
            return
        }
        loadDiagnostic = nil
        options = await Self.applyIntroEligibility(to: loaded)
        selectedOption = bestValueSubscription() ?? options.first
    }

    /// Keeps an intro offer on an option only when StoreKit, through
    /// RevenueCat, says this Apple Account can still redeem it. Someone who
    /// already used their trial must never see "free" on a button that
    /// charges them straight away. Unknown counts as not eligible: the
    /// plain price is always true.
    private static func applyIntroEligibility(to options: [PaywallOption]) async -> [PaywallOption] {
        let ids = options.compactMap { $0.introOffer == nil ? nil : $0.storeProduct?.productIdentifier }
        guard !ids.isEmpty else { return options }
        let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: ids)
        return options.map { option in
            guard option.introOffer != nil, let id = option.storeProduct?.productIdentifier else { return option }
            var checked = option
            if eligibility[id]?.status != .eligible { checked.introOffer = nil }
            return checked
        }
    }

    func purchase() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        guard let selectedOption = activeOption else {
            present(error: String(localized: "This offer isn't available right now. Please try again later.", bundle: .appLanguage, locale: .appLanguage))
            return
        }

        // Non-consumable: never sell the second ram twice.
        if selectedOption.isOneTime, entitlementService?.hasSecondRam == true { return }

        guard Purchases.isConfigured else {
            await mockPurchase(selectedOption)
            return
        }
        guard selectedOption.package != nil || selectedOption.storeProduct != nil else {
            present(error: String(localized: "This offer isn't available right now. Please try again later.", bundle: .appLanguage, locale: .appLanguage))
            return
        }

        do {
            let result: PurchaseResultData
            if let package = selectedOption.package {
                result = try await Purchases.shared.purchase(package: package)
            } else if let product = selectedOption.storeProduct {
                result = try await Purchases.shared.purchase(product: product)
            } else {
                return
            }
            if result.userCancelled { return }
            let info = result.customerInfo
            if info.entitlements.active.isEmpty && info.activeSubscriptions.isEmpty && info.nonSubscriptions.isEmpty {
                present(error: String(localized: "Your purchase couldn't be completed. Please try again.", bundle: .appLanguage, locale: .appLanguage))
            } else {
                // `EntitlementService`'s delegate callback will catch this
                // too, but refreshing explicitly means the pasture unlocks
                // immediately rather than waiting on it.
                await entitlementService?.refresh()
                if selectedOption.isOneTime, entitlementService?.hasSecondRam == true {
                    self.selectedOption = bestValueSubscription() ?? self.selectedOption
                }
            }
        } catch {
            #if DEBUG
            print("[Paywall] purchase failed: \(error)")
            #endif
            present(error: String(localized: "Your purchase couldn't be completed. Please try again.", bundle: .appLanguage, locale: .appLanguage))
        }
    }

    func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        guard Purchases.isConfigured else {
            present(error: String(localized: "Purchases aren't configured in this build.", bundle: .appLanguage, locale: .appLanguage))
            return
        }

        do {
            _ = try await Purchases.shared.restorePurchases()
            await entitlementService?.refresh()
        } catch {
            present(error: String(localized: "We couldn't restore your purchases. Please try again.", bundle: .appLanguage, locale: .appLanguage))
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
        return String(localized: "Best value · save \(percentOff)%", bundle: .appLanguage, locale: .appLanguage)
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
            MockEntitlementStore.hasSecondRam = true
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
            PaywallOption(sampleID: RevenueCatConfiguration.ProductID.pastureMonthly, title: String(localized: "Monthly", bundle: .appLanguage, locale: .appLanguage), periodDescription: String(localized: "per month", bundle: .appLanguage, locale: .appLanguage), priceString: "$1.99", price: 1.99, approximateDays: 30),
            PaywallOption(sampleID: RevenueCatConfiguration.ProductID.pastureAnnual, title: String(localized: "Annual", bundle: .appLanguage, locale: .appLanguage), periodDescription: String(localized: "per year", bundle: .appLanguage, locale: .appLanguage), priceString: "$14.99", price: 14.99, approximateDays: 365, hasIntroductoryOffer: true),
            PaywallOption(sampleID: RevenueCatConfiguration.ProductID.adoptRam, title: String(localized: "Adopt a Second Ram", bundle: .appLanguage, locale: .appLanguage), periodDescription: String(localized: "one-time purchase", bundle: .appLanguage, locale: .appLanguage), priceString: "$4.99", price: 4.99, approximateDays: nil),
        ]
    }
}

#Preview {
    PasturePaywallView()
        .environment(EntitlementService())
}
