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
//    pasture_expansion      5 rams at once + every wax       com.baranov.sub.monthly   ($2.99)
//                           colour                           com.baranov.sub.quarterly ($5.99 / 3 months)
//                                                            com.baranov.sub.annual    ($19.99, 7-day trial)
//    adopted_ram            a permanent 2nd ram slot         com.baranov.iap.ram.merino ($2.99, one-time)
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
    static let apiKey = "test_JZRPZKzpSBlSCvjemKwkupccdcJ"

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
        static let pastureMonthly = "com.baranov.sub.monthly"
        static let pastureQuarterly = "com.baranov.sub.quarterly"
        static let pastureAnnual = "com.baranov.sub.annual"
        static let adoptRam = "com.baranov.iap.ram.merino"
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
