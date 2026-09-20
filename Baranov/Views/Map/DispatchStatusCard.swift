//
//  DispatchStatusCard.swift
//  Baranov
//
//  The docked panel's collapsed form while a letter is out: one compact
//  floating card — the ram's portrait, who is waiting, and how far there
//  is still to walk — with a hairline of progress underneath. It is the
//  glanceable version of `followContent`; a tap opens the panel to the
//  full journey view.
//
//  `.ultraThinMaterial` on a continuous-corner rectangle, semantic text
//  styles, one SF Symbol for the state. No gradients, no glow, no colored
//  shadow: the card floats because the material lets the map through,
//  not because anything is painted around it.
//

import SwiftUI

struct DispatchStatusCard: View {
    let ram: Ram
    /// Who the walk is for — resolved by the parent, which knows the
    /// letter and passenger rules.
    let headline: String
    /// Whether the shepherd is moving right now (steps or GPS), which is
    /// what animates the state glyph.
    var isMoving: Bool = false
    let onTap: () -> Void
    /// Shown as a prominent button once the ram is at the gate.
    var onBreakSeal: (() -> Void)? = nil

    private var stateSymbol: String {
        switch ram.status {
        case .walking: return isMoving ? "figure.walk.motion" : "figure.stand"
        case .grazing: return "leaf"
        case .waitingForHandoff: return ram.voyage == nil ? "ferry" : "clock.badge.checkmark"
        case .atSea: return "sailboat"
        case .handedOff: return "hand.wave"
        case .arrivedAtGate: return "door.left.hand.open"
        case .delivered: return "checkmark.seal"
        }
    }

    private var stateCaption: LocalizedStringKey {
        switch ram.status {
        case .walking: return isMoving ? "Walking" : "Resting"
        case .grazing: return "Ready to set out"
        case .waitingForHandoff:
            guard let voyage = ram.voyage else {
                return "At the quay in \(ram.legDestinationCity)"
            }
            return "Sails \(voyage.departsAt.formatted(.relative(presentation: .named)))"
        case .atSea:
            guard let voyage = ram.voyage else { return "At Sea" }
            return "At sea — \(voyage.arrivalPortName) by \(voyage.arrivesAt.formatted(.relative(presentation: .named)))"
        case .handedOff: return "Carried by someone else"
        case .arrivedAtGate: return "At the gate"
        case .delivered: return "Delivered"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            cardButton
            if ram.status == .arrivedAtGate, let onBreakSeal {
                BreakSealButton(action: onBreakSeal)
            }
        }
    }

    private var cardButton: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    RamPortraitView(name: ram.name, diameter: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        HStack(spacing: 4) {
                            Text(ram.name)
                                .contentTransition(.opacity)
                            Text("·")
                            Text(stateCaption)
                                .contentTransition(.opacity)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .animation(.easeInOut(duration: 0.2), value: ram.status)
                    }

                    Spacer(minLength: 8)

                    if ram.status != .delivered && ram.status != .arrivedAtGate {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(ram.remainingSteps.formatted(.number.grouping(.automatic)))
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .monospacedDigit()
                                .contentTransition(.numericText(value: Double(ram.remainingSteps)))
                                .foregroundStyle(.primary)
                            Text("steps to go")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Image(systemName: stateSymbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse, options: .repeating, isActive: ram.status == .walking && isMoving)
                        .frame(width: 22)
                        .contentTransition(.symbolEffect(.replace))
                }

                ProgressView(value: ram.progress)
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: ram.remainingSteps)
        .animation(.easeInOut(duration: 0.2), value: isMoving)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text(headline)
            + Text(". ")
            + Text(ram.name)
            + Text(", ")
            + Text(stateCaption)
            + Text(", \(ram.remainingSteps) steps to go.")
        )
        .accessibilityHint("Opens the journey")
    }
}

#Preview {
    DispatchStatusCard(ram: FlockViewModel.preview.activeRams[0], headline: "Marta is waiting", isMoving: true) {}
        .padding()
}
