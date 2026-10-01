//
//  RevenueCatConfiguration.swift
//  Baranov
//
//  Everything the app knows about its RevenueCat project, in one place,
//  so the dashboard and the code can be checked against each other at a
//  glance. The identifiers below must match the RevenueCat dashboard
//  exactly (Entitlements → identifiers; Products → App Store product
//  IDs; Offerings → the `default` offering's packages).
//
//  The API key is the *public* SDK key — it is safe to commit (it can
//  only ever identify this app to RevenueCat, never act on the account),
//  which is why an open-source Next Gen entry can ship with it in place.
//  A RevenueCat "Test Store" key (`test_…`) works here too, and lets the
//  whole purchase flow run on a Simulator or a device with no App Store
//  Connect setup at all.
//
//  How the pieces relate:
//
//    Entitlement            Unlocks                          Granted by
//    ─────────────────────  ───────────────────────────────  ─────────────────────────────
//    pasture_expansion      5 rams at once + every wax       monthly                 (subscription)
//                           colour                           baranov.pasture.annual  (subscription, 7-day trial)
//    adopted_ram            a permanent 2nd ram slot         baranov.ram.adopt       (one-time)
//
//  Pricing rationale (a starting point, not data — watch the numbers):
//  the expansion is worth about a coffee a month to someone who writes to
//  five people, and the annual should be a clear "just take it" at under
//  half the monthly rate. Adopting a ram has to sit below the annual so
//  it isn't a trap, but above zero so it reads as owning something.
//
//  Sending and receiving with one ram is free, forever, and is never
//  gated — see `PasturePaywallView` for how that promise is kept visible.
//

import Foundation

enum RevenueCatConfiguration {
    /// Public SDK key from Project Settings → API Keys.
    /// Public Apple SDK key. Used in every build, debug included, so the paywall
    /// reads the same offering (`monthly`, `baranov.pasture.annual`,
    /// `baranov.ram.adopt`) that ships. A Test Store key (`test_…`) is a separate
    /// RevenueCat app with its own product catalogue: against the dashboard's
    /// App Store packages it returns an empty offering, so the paywall showed
    /// "Pricing unavailable". Debug runs buy through Xcode's StoreKit file or sandbox.
    static let apiKey = "appl_ghrRKeJOvhHTFeYYXaTtWUqRcXg"

    static var hasRealAPIKey: Bool {
        !apiKey.isEmpty && apiKey != "REVENUECAT_API_KEY_PLACEHOLDER"
    }

    enum Entitlement {
        /// Subscription: five concurrent rams and every wax colour.
        static let pastureExpansion = "pasture_expansion"
        /// Non-consumable: one extra ram slot, owned outright.
        static let adoptedRam = "adopted_ram"
    }

    enum ProductID {
        // The real App Store Connect / RevenueCat product IDs. Do not rename.
        static let pastureMonthly = "monthly"
        static let pastureAnnual = "baranov.pasture.annual"
        static let adoptRam = "baranov.ram.adopt"

        /// Everything the paywall is allowed to sell.
        static let all: Set<String> = [pastureMonthly, pastureAnnual, adoptRam]
    }

    /// Custom subscriber attributes synced to RevenueCat so the dashboard
    /// can segment by how much of the app someone actually uses — and so
    /// the same numbers the ACIT3855 flock-metric telemetry reports show
    /// up next to the revenue they relate to.
    enum Attribute {
        static let carrierName = "carrier_name"
        static let lettersDelivered = "letters_delivered"
        static let stepsWalked = "steps_walked"
        static let activeRams = "active_rams"
    }
}
