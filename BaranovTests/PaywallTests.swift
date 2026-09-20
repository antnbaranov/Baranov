//
//  PaywallTests.swift
//  BaranovTests
//
//  The paywall's arithmetic and its promises: the savings badge is
//  computed from real prices, the free tier is exactly one ram, and the
//  two entitlements map onto the slot counts the app advertises.
//

import Foundation
import Testing
@testable import Baranov

@MainActor
struct PaywallTests {

    @Test(.enabled(if: !RevenueCatConfiguration.hasRealAPIKey, "Sample pricing only shows without a RevenueCat key"))
    func savingsBadgeIsComputedFromPrices() async {
        let viewModel = PasturePaywallViewModel()
        await viewModel.loadOffering() // no API key in tests → sample options
        #expect(viewModel.isShowingSamplePricing)

        let annual = viewModel.subscriptionOptions.first { $0.title == "Annual" }
        let monthly = viewModel.subscriptionOptions.first { $0.title == "Monthly" }
        let adopt = viewModel.oneTimeOptions.first
        #expect(annual != nil && monthly != nil && adopt != nil)

        // $19.99/365d vs $2.99/30d ≈ 45% cheaper per week.
        #expect(viewModel.badge(for: annual!) == "Best value · save 45%")
        #expect(viewModel.badge(for: monthly!) == nil)
        #expect(viewModel.badge(for: adopt!) == nil)
        #expect(viewModel.selectedOption?.id == annual?.id)
        #expect(viewModel.orderedOptions.map(\.title) == ["Annual", "Every 3 Months", "Monthly", "Adopt a Ram"])
    }

    @Test(.enabled(if: !RevenueCatConfiguration.hasRealAPIKey, "Mock store only exists without a RevenueCat key"))
    func entitlementsMapOntoSlots() {
        let service = EntitlementService()
        #expect(service.allowedRamSlots == 1)
        #expect(!service.isLive) // no key in tests
    }

    @Test(.enabled(if: !RevenueCatConfiguration.hasRealAPIKey, "Mock store only exists without a RevenueCat key"))
    func mockStoreUnlocksWithoutRevenueCat() async {
        MockEntitlementStore.hasPastureExpansion = false
        MockEntitlementStore.hasAdoptedRam = false
        defer {
            MockEntitlementStore.hasPastureExpansion = false
            MockEntitlementStore.hasAdoptedRam = false
        }

        let service = EntitlementService()
        await service.refresh()
        #expect(service.allowedRamSlots == 1)

        MockEntitlementStore.hasAdoptedRam = true
        await service.refresh()
        #expect(service.allowedRamSlots == 2)

        MockEntitlementStore.hasPastureExpansion = true
        await service.refresh()
        #expect(service.allowedRamSlots == FlockViewModel.pastureCapacity)
    }

    @Test func configurationIdentifiersAreConsistent() {
        #expect(RevenueCatConfiguration.Entitlement.pastureExpansion == "pasture_expansion")
        #expect(RevenueCatConfiguration.Entitlement.adoptedRam == "adopted_ram")
        #expect(!RevenueCatConfiguration.hasRealAPIKey || !RevenueCatConfiguration.apiKey.isEmpty)
    }
}
