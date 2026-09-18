//
//  ContentView.swift
//  Baranov
//
//  App entry point — hands off immediately to the root screen (Journey,
//  with Pasture reached by pushing from its toolbar; see `RootView`).
//  Kept as its own tiny file so `BaranovApp.swift` doesn't need to change.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        RootView()
    }
}

#Preview {
    ContentView()
}
