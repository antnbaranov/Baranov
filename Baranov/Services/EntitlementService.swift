//
//  EntitlementService.swift
//  Baranov
//
//  The RevenueCat integration point: owns what this carrier has unlocked
//  and keeps that answer current, live, without polling.
//
//  Two entitlements, two very different shapes of purchase, on purpose:
//
//  - `pasture_expansion` — a subscription. Five rams at once and every
//    wax colour, for as long as it's kept up. Comes back to one ram when
//    it lapses; nothing is ever lost, letters mid-journey keep walking.
//  - `adopted_ram` — a one-time, non-consumable purchase. One extra ram
//    slot, owned outright, for people who'd rather buy a ram than rent a
//    pasture. Stacks with nothing; it's the honest "I just want two".
//
//  `allowedRamSlots` is the single number `RootView` maps onto
//  `FlockViewModel.maxAllowedRams`. The first slot is free, forever.
//
//  Until a real RevenueCat public SDK key replaces the placeholder in
//  `RevenueCatConfiguration`, the SDK is deliberately left unconfigured
//  so no purchase UI can ever hit a live store during development. In
//  that state, entitlement falls back to `MockEntitlementStore`, a local
//  flag the paywall's mock-purchase flow flips, so the whole unlock flow
//  stays testable end-to-end without a live SDK connection. Drop in a
//  real key and everything above starts reflecting actual RevenueCat
//  purchases instead, with no other code changes required.
//

import Foundation
import Observation
import RevenueCat

@Observable
@MainActor
final class EntitlementService: NSObject {

    /// Whether this carrier currently has the Pasture Expansion
    /// subscription — five rams and every wax colour.
    private(set) var hasPastureExpansion: Bool = false

    /// Whether this carrier owns an adopted ram — a permanent second slot.
    private(set) var hasAdoptedRam: Bool = false

    /// Whether the SDK is actually talking to RevenueCat, as opposed to
    /// the local mock store. The paywall uses this to decide whether
    /// "Manage Subscription" (Customer Center) can be offered.
    var isLive: Bool { Purchases.isConfigured }

    /// How many rams this carrier may have in the pasture at once.
    var allowedRamSlots: Int {
        if hasPastureExpansion { return FlockViewModel.pastureCapacity }
        if hasAdoptedRam { return 2 }
        return 1
    }

    override init() {
        super.init()
        configureIfNeeded()
        if Purchases.isConfigured {
            Purchases.shared.delegate = self
        }
    }

    /// Configures the RevenueCat SDK exactly once, and only once a real
    /// API key has been supplied — never with the checked-in placeholder,
    /// and never twice (re-configuring is a RevenueCat misuse warning).
    /// StoreKit 2 is opted into explicitly; it's the modern path and the
    /// one a `.storekit` configuration file in the scheme exercises.
    private func configureIfNeeded() {
        guard !Purchases.isConfigured, RevenueCatConfiguration.hasRealAPIKey else { return }

        #if DEBUG
        Purchases.logLevel = .debug
        #endif

        let configuration = Configuration.Builder(withAPIKey: RevenueCatConfiguration.apiKey)
            .with(storeKitVersion: .storeKit2)
            .build()
        Purchases.configure(with: configuration)
    }

    /// Resolves the current entitlement state. Safe to call as often as
    /// needed (app launch, after a purchase/restore, pull-to-refresh) —
    /// a transient network failure leaves the last known value in place
    /// rather than downgrading the carrier's flock offline. RevenueCat's
    /// own on-device cache means this also answers correctly with no
    /// network at all.
    func refresh() async {
        guard Purchases.isConfigured else {
            hasPastureExpansion = MockEntitlementStore.hasPastureExpansion
            hasAdoptedRam = MockEntitlementStore.hasAdoptedRam
            return
        }

        do {
            let info = try await Purchases.shared.customerInfo()
            apply(info)
        } catch {
            // Offline-first: keep whatever we last knew rather than
            // silently shrinking the pasture on a transient failure.
        }
    }

    #if DEBUG
    /// Debug-only override for Settings' hidden cheat code. Once a real
    /// (or sandbox) RevenueCat API key is configured, `Purchases.isConfigured`
    /// is true and `refresh()` only ever reflects RevenueCat's
    /// `customerInfo()` — it no longer looks at `MockEntitlementStore` at
    /// all, so flipping that flag alone silently did nothing. This sets
    /// the published property directly (and keeps the mock store in sync
    /// for anything else that reads it), bypassing RevenueCat entirely.
    /// Compiled out of every release build.
    func debugSetPastureExpansion(_ value: Bool) {
        MockEntitlementStore.hasPastureExpansion = value
        hasPastureExpansion = value
    }
    #endif

    /// Mirrors what the carrier has actually done in the app onto their
    /// RevenueCat customer record, as subscriber attributes — the same
    /// figures the ACIT3855 flock-metric telemetry reports. Fire-and-
    /// forget; the SDK batches and retries these itself.
    func syncCarrierAttributes(carrierName: String, lettersDelivered: Int, stepsWalked: Int, activeRams: Int) {
        guard Purchases.isConfigured else { return }
        let trimmedName = carrierName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            Purchases.shared.attribution.setDisplayName(trimmedName)
        }
        Purchases.shared.attribution.setAttributes([
            RevenueCatConfiguration.Attribute.carrierName: trimmedName,
            RevenueCatConfiguration.Attribute.lettersDelivered: String(lettersDelivered),
            RevenueCatConfiguration.Attribute.stepsWalked: String(stepsWalked),
            RevenueCatConfiguration.Attribute.activeRams: String(activeRams),
        ])
    }

    private func apply(_ customerInfo: CustomerInfo) {
        let active = customerInfo.entitlements.active
        // The dashboard may attach a product to an entitlement with a different
        // identifier (or none at all, e.g. a Test Store product). Being subscribed
        // is what matters, so an active subscription unlocks the pasture even if
        // its entitlement isn't literally named `pasture_expansion`.
        let namedExpansion = active[RevenueCatConfiguration.Entitlement.pastureExpansion] != nil
        let otherEntitlement = active.keys.contains { $0 != RevenueCatConfiguration.Entitlement.adoptedRam }
        let anySubscription = !customerInfo.activeSubscriptions.isEmpty
        hasPastureExpansion = namedExpansion || otherEntitlement || anySubscription
        hasAdoptedRam = active[RevenueCatConfiguration.Entitlement.adoptedRam] != nil
            || !customerInfo.nonSubscriptions.isEmpty

        #if DEBUG
        print("[Entitlements] active entitlements: \(active.keys.sorted()), activeSubscriptions: \(customerInfo.activeSubscriptions.sorted()), nonSubscriptions: \(customerInfo.nonSubscriptions.map(\.productIdentifier)) → expansion=\(hasPastureExpansion) adopted=\(hasAdoptedRam)")
        #endif
    }
}

// MARK: - PurchasesDelegate

extension EntitlementService: PurchasesDelegate {
    /// Live entitlement updates (a purchase completing on another screen,
    /// a subscription renewing or lapsing, a restore finishing elsewhere,
    /// Family Sharing kicking in). RevenueCat calls this off the main
    /// actor, so — exactly like `StepTrackerService`'s CoreMotion
    /// callback — it re-enters isolation via a weak-captured hop before
    /// touching any state.
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor [weak self] in
            self?.apply(customerInfo)
        }
    }
}

/// Local unlock flags used only while RevenueCat is unconfigured (no real
/// API key yet). Flipped by `PasturePaywallViewModel`'s mock-purchase
/// flow so the paywall's promise — fully navigable, end-to-end testable
/// without a live SDK connection — is actually true, not just documented.
enum MockEntitlementStore {
    private static let expansionKey = "com.baranov.mockPastureExpansionUnlocked"
    private static let adoptedKey = "com.baranov.mockAdoptedRamUnlocked"

    static var hasPastureExpansion: Bool {
        get { UserDefaults.standard.bool(forKey: expansionKey) }
        set { UserDefaults.standard.set(newValue, forKey: expansionKey) }
    }

    static var hasAdoptedRam: Bool {
        get { UserDefaults.standard.bool(forKey: adoptedKey) }
        set { UserDefaults.standard.set(newValue, forKey: adoptedKey) }
    }
}
