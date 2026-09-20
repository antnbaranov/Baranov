//
//  AchievementTests.swift
//  BaranovTests
//
//  The badge rules are pure functions of a progress snapshot — so they
//  are checked here, not on a device with a real leaderboard.
//

import Testing
@testable import Baranov

struct AchievementTests {

    @Test func nothingIsEarnedOnAFreshInstall() {
        let fresh = ShepherdAchievement.Progress(ramsDispatched: 0, lettersDelivered: 0, metresWalked: 0, handoffsMade: 0, mostRamsAtOnce: 0)
        #expect(ShepherdAchievement.earned(fresh).isEmpty)
        #expect(ShepherdAchievement.tenKilometres.fraction(fresh) == 0)
    }

    @Test func distanceBadgesTrackProgress() {
        let halfway = ShepherdAchievement.Progress(ramsDispatched: 1, lettersDelivered: 0, metresWalked: 5_000, handoffsMade: 0, mostRamsAtOnce: 1)
        #expect(ShepherdAchievement.tenKilometres.fraction(halfway) == 0.5)
        #expect(!ShepherdAchievement.tenKilometres.isEarned(halfway))
        #expect(ShepherdAchievement.firstLetter.isEarned(halfway))

        let far = ShepherdAchievement.Progress(ramsDispatched: 6, lettersDelivered: 2, metresWalked: 120_000, handoffsMade: 1, mostRamsAtOnce: 5)
        #expect(Set(ShepherdAchievement.earned(far)) == Set(ShepherdAchievement.allCases))
        #expect(ShepherdAchievement.hundredKilometres.fraction(far) == 1)
    }

    @Test func identifiersAreUniqueAndNamespaced() {
        let ids = ShepherdAchievement.allCases.map(\.rawValue)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0.hasPrefix("com.baranov.achievement.") })
    }
}
