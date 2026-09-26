//
//  PastureDismiss.swift
//
//  Lets a screen pushed deep inside Pasture close the whole Pasture sheet
//  (which `RootView` owns), e.g. an empty state whose button should take
//  the person back to the map to start a journey.
//

import SwiftUI

struct DismissPastureAction {
    var handler: @MainActor () -> Void = {}

    @MainActor func callAsFunction() { handler() }
}

extension EnvironmentValues {
    @Entry var dismissPasture = DismissPastureAction()
}
