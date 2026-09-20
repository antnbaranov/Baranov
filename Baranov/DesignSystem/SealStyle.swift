//
//  SealStyle.swift
//  Baranov
//
//  How the wax seal is used: the full tactile ritual (hold to crack and
//  break it), or a quiet alternative — a gray "Tap the seal!" prompt and a
//  plain tap. Chosen in Settings, read wherever a seal is pressed.
//

import SwiftUI

enum SealStyle: String, CaseIterable, Identifiable, Sendable {
    case wax
    case prompt

    static let storageKey = "com.baranov.sealStyle"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .wax: "Wax Seal"
        case .prompt: "Tap Prompt"
        }
    }
}
