//
//  CourierSuggestionCard.swift
//  Baranov
//
//  Shown while a courier is in range and the moment is worth a tap:
//  "Maria is heading to Berlin — hand her Klaus?", or, at the gate,
//  "Marta is here — deliver her letter?". Tapping the action sends the same
//  handover request as tapping the courier in Profile.
//
//  Native materials and semantic styles only, per the project's HIG rules.
//

import SwiftUI

struct CourierSuggestionCard: View {
    let suggestion: CourierSuggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    @State private var appeared = false
    private var title: String {
        switch suggestion.kind {
        case .goingYourWay:
            return String(localized: "\(suggestion.courier.name) is heading to \(suggestion.place)",
                          bundle: .appLanguage, locale: .appLanguage, comment: "Courier suggestion title. First argument: courier's name, second: their trip city.")
        case .deliver:
            return String(localized: "\(suggestion.courier.name) is here",
                          bundle: .appLanguage, locale: .appLanguage, comment: "Courier suggestion title — the letter's recipient is in range. The argument is their name.")
        }
    }

    private var detail: String {
        switch suggestion.kind {
        case .goingYourWay:
            return String(localized: "Hand them \(suggestion.ramName)? The letter goes their way.",
                          bundle: .appLanguage, locale: .appLanguage, comment: "Courier suggestion detail. The argument is the ram's name.")
        case .deliver:
            return String(localized: "\(suggestion.ramName) has their letter. Deliver it now, in person.",
                          bundle: .appLanguage, locale: .appLanguage, comment: "Courier suggestion detail at the gate. The argument is the ram's name.")
        }
    }

    private var actionTitle: String {
        switch suggestion.kind {
        case .goingYourWay: String(localized: "Hand over", bundle: .appLanguage, locale: .appLanguage)
        case .deliver: String(localized: "Deliver", bundle: .appLanguage, locale: .appLanguage)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: suggestion.kind == .deliver ? "envelope.open.fill" : "figure.walk.motion")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: 10) {
                Button(action: onDismiss) {
                    Text("Not now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onAccept) {
                    Text(actionTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
        .swipeToDismiss(onDismiss: onDismiss)
        .sensoryFeedback(.impact(weight: .light), trigger: appeared)
        .onAppear { appeared = true }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
