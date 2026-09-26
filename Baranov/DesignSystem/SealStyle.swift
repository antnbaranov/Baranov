//
//  SealStyle.swift
//  Baranov
//
//  How the wax seal is used. The tactile ritual (press and hold) is the
//  only experience — it is the emotional core of the app, so there is no
//  setting to water it down. The one exception is not a preference but an
//  accessibility need: with VoiceOver or Switch Control running, a hold
//  gesture isn't reachable, so the seal becomes a plain tap.
//

import SwiftUI

enum SealStyle: String, CaseIterable, Identifiable, Sendable {
    case wax
    case prompt

    static let storageKey = "com.baranov.sealStyle"

    var id: String { rawValue }

    static func resolved(voiceOver: Bool, switchControl: Bool) -> SealStyle {
        (voiceOver || switchControl) ? .prompt : .wax
    }

    var title: LocalizedStringKey {
        switch self {
        case .wax: "Wax Seal"
        case .prompt: "Tap Prompt"
        }
    }
}
