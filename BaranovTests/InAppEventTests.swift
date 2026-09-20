//
//  InAppEventTests.swift
//  BaranovTests
//

import Testing
@testable import Baranov

struct InAppEventTests {

    @Test func newYorkSlugResolution() {
        let event = InAppEvent(slug: "new-york")
        #expect(event.id == "new-york")
        #expect(event.title == "Expedition to New York")
        #expect(event.destinationCity == "New York, NY")
        #expect(event.coordinate?.latitude == 40.7128)
    }

    @Test func fallbackSlugResolution() {
        let emptyEvent = InAppEvent(slug: "")
        #expect(emptyEvent.id == "new-york")

        let customEvent = InAppEvent(slug: "san-francisco")
        #expect(customEvent.id == "san-francisco")
        #expect(customEvent.title == "Expedition: San Francisco")
        #expect(customEvent.destinationCity == "San Francisco")
    }
}
