//
//  HandoverRequestCard.swift
//  Baranov
//
//  What a courier sees when someone nearby taps them and chooses Hand over:
//  who is asking, which ram, and Accept / Not now. Accepting arms this
//  phone's hoofbeat relay with the request's token, so the two phones pair
//  without a shake.
//
//  Native materials and semantic styles only, per the project's HIG rules.
//

import SwiftUI

struct HandoverRequestCard: View {
    let request: HandoverRequest
    /// Whether the letter is going this person's way; `nil` hides the hint.
    var goingMyWay: Bool? = nil
    let onAccept: () -> Void
    let onDecline: () -> Void

    @State private var appeared = false

    private var title: String {
        if request.isDelivery == true {
            return String(localized: "\(request.fromName) has a letter for you",
                          bundle: .appLanguage, locale: .appLanguage, comment: "Handover request card title when the letter is being delivered to its recipient. The argument is the carrier's name.")
        }
        if let ram = request.ramName, !ram.isEmpty {
            return String(localized: "\(request.fromName) wants to hand you \(ram)",
                          bundle: .appLanguage, locale: .appLanguage, comment: "Handover request card title. First argument is the sender's name, second is the ram's name.")
        }
        return String(localized: "\(request.fromName) wants to meet for a handoff",
                      bundle: .appLanguage, locale: .appLanguage, comment: "Handover request card title when the sender has no ram to give. The argument is the sender's name.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "hand.wave.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let city = request.destinationCity, !city.isEmpty {
                        Text("Bound for \(city)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let goingMyWay {
                        Label(goingMyWay
                              ? String(localized: "Going your way", bundle: .appLanguage, locale: .appLanguage)
                              : String(localized: "Not the way your ram is going", bundle: .appLanguage, locale: .appLanguage),
                              systemImage: goingMyWay ? "arrow.up.forward.circle.fill" : "arrow.triangle.branch")
                            .font(.subheadline)
                            .foregroundStyle(goingMyWay ? Color.green : Color.secondary)
                    }
                    Text("Keep your phones close while it passes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: 10) {
                Button(action: onDecline) {
                    Text("Not now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onAccept) {
                    Text("Accept")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
        .swipeToDismiss(onDismiss: onDecline)
        .sensoryFeedback(.impact(weight: .medium), trigger: appeared)
        .onAppear { appeared = true }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

#Preview {
    HandoverRequestCard(
        request: HandoverRequest(token: "A1B2C3", fromName: "Anton", ramName: "Klaus"),
        onAccept: {},
        onDecline: {}
    )
    .padding(.vertical)
}
