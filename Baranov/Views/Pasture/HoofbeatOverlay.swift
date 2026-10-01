//
//  HoofbeatOverlay.swift
//  Baranov
//
//  The only UI the shake handoff has: a small capsule that drops from the
//  top while `HoofbeatRelay` is doing its work, and slides away on its own
//  once the exchange settles. Deliberately unobtrusive — the gesture is
//  the interaction, this is just the receipt.
//
//  While the satchel is actually changing hands (`.exchanging`), the icon
//  is a small loop of the same galloping-with-envelope sprite the map
//  marker uses (`RamSpriteFrameSets.gallopWithEnvelope`) rather than a
//  generic radio-waves glyph — falls back to that glyph automatically if
//  the sprite art isn't present, same as everywhere else this art is used.
//
//  Native materials and semantic styles only, per the project's HIG rules.
//

import SwiftUI

struct HoofbeatOverlay: View {
    let phase: HoofbeatPhase
    let successTick: Int
    /// Who the person tapped to hand a ram to, while we wait for them to shake back.
    var partnerName: String? = nil
    /// Asked from Profile or the map: waiting for them to tap Accept, not to shake.
    var awaitingAcceptance: Bool = false
    /// The person tapped Accept on someone's request: connecting, not waiting for a shake.
    var answeringRequest: Bool = false
    /// Cancels the current exchange and resets to idle.
    var onDismiss: (() -> Void)? = nil
    /// Re-triggers the hoofbeat after a failure.
    var onRetry: (() -> Void)? = nil
    /// The tap alternative to shaking: "I'm ready, hand over now".
    var onConfirm: (() -> Void)? = nil
    /// The person already tapped it and is waiting for the other phone.
    var isConfirmed: Bool = false
    /// Why a failed handoff failed; picks the advice and whether Settings is offered.
    var failure: HoofbeatFailure = .other
    /// Opens this app's page in Settings (Local Network lives there).
    var onOpenSettings: (() -> Void)? = nil

    private var hasSpriteArt: Bool {
        guard let first = RamSpriteFrameSets.gallopWithEnvelope.first else { return false }
        return RamSpriteFrameSets.assetExists(first)
    }

    /// Phases where the dismiss button is useful — everywhere except idle
    /// (nothing to dismiss) and exchanging (data is in flight, cancelling
    /// mid-stream would corrupt the handoff).
    private var showDismiss: Bool {
        switch phase {
        case .searching, .connecting, .failed, .finished:
            return true
        case .idle, .exchanging:
            return false
        }
    }

    private var showRetry: Bool {
        if case .failed = phase { return true }
        return false
    }

    /// Looking for a shake partner (not waiting on a request's Accept): the
    /// one state where tapping can stand in for the second shake.
    private var showConfirm: Bool {
        guard onConfirm != nil, case .searching = phase else { return false }
        return !awaitingAcceptance && !answeringRequest
    }

    var body: some View {
        Group {
            if phase.isActive {
                if showRetry {
                    failedCard
                } else if showConfirm {
                    waitingCard
                } else {
                    statusPill
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: phase)
        .sensoryFeedback(.success, trigger: successTick)
    }

    private var statusPill: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 22, height: 22)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            if showDismiss, let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .padding(.horizontal, 20)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Two big side-by-side buttons, laid out like the request card's
    /// "Not now" / "Accept" pair: a quiet one on the left, the main one on
    /// the right.
    private func actionRow(
        cancelTitle: LocalizedStringKey = "Cancel",
        primaryTitle: LocalizedStringKey,
        primaryIcon: String? = nil,
        primaryDisabled: Bool = false,
        onCancel: (() -> Void)?,
        onPrimary: (() -> Void)?
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                onCancel?()
            } label: {
                Text(cancelTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                onPrimary?()
            } label: {
                Group {
                    if let primaryIcon {
                        Label(primaryTitle, systemImage: primaryIcon)
                    } else {
                        Text(primaryTitle)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(primaryDisabled)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    /// What to do about the failure, in words.
    private var failureAdvice: LocalizedStringKey {
        switch failure {
        case .localNetworkDenied:
            "Baranov needs Local Network access to find nearby phones. Turn it on in Settings, then try again."
        case .noShake:
            "Nobody answered. Make sure Baranov is open on their phone and that Bluetooth and Wi‑Fi are on, then try again."
        case .notAccepted:
            "They may not have seen the request. Make sure Baranov is open on their phone, then try again."
        case .unreachable:
            "The phones found each other but couldn't connect. Move a little closer and check Bluetooth and Wi‑Fi, then try again."
        case .other:
            "The sender has to send the ram first. Or be the receiver instead: add the sender's ID as a code in the letter sheet."
        }
    }

    /// A failed handoff: what happened, what to do about it, and Cancel /
    /// Try Again (or Open Settings when only Settings can fix it) as big
    /// as the request card's buttons.
    private var failedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                icon
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(failureAdvice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if failure == .localNetworkDenied, let onOpenSettings {
                actionRow(primaryTitle: "Open Settings", primaryIcon: "gearshape",
                          onCancel: onDismiss, onPrimary: onOpenSettings)
                if let onRetry {
                    Button(action: onRetry) {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                }
            } else {
                actionRow(primaryTitle: "Try Again", primaryIcon: "arrow.clockwise",
                          onCancel: onDismiss, onPrimary: onRetry)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Waiting for the other person's shake, with a tap to stand in for it.
    private var waitingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                icon
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(isConfirmed
                         ? LocalizedStringKey("Ready. Waiting for the other phone to tap or shake too.")
                         : LocalizedStringKey("Not shaking? Tap Hand Over Now, and ask them to tap too."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            actionRow(primaryTitle: isConfirmed ? "Waiting…" : "Hand Over Now",
                      primaryIcon: isConfirmed ? nil : "hand.tap",
                      primaryDisabled: isConfirmed,
                      onCancel: onDismiss, onPrimary: onConfirm)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private var icon: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .searching:
            ProgressView()
                .controlSize(.small)
        case .connecting:
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.headline)
                .foregroundStyle(.secondary)
                .symbolEffect(.variableColor.iterative)
        case .exchanging:
            if hasSpriteArt {
                RamSpriteLoopView(frameNames: RamSpriteFrameSets.gallopRunningStride, frameDuration: .milliseconds(60))
            } else {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .symbolEffect(.variableColor.iterative)
            }
        case .finished:
            Image(systemName: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var message: String {
        switch phase {
        case .idle:
            return ""
        case .searching:
            if awaitingAcceptance, let partnerName, !partnerName.isEmpty {
                return String(localized: "Waiting for \(partnerName) to accept…",
                              bundle: .appLanguage, locale: .appLanguage, comment: "Hoofbeat handoff overlay — the person asked a nearby courier to take a ram and is waiting for them to tap Accept on their phone. The argument is the courier's name.")
            }
            if answeringRequest, let partnerName, !partnerName.isEmpty {
                return String(localized: "Connecting with \(partnerName)…",
                              bundle: .appLanguage, locale: .appLanguage, comment: "Hoofbeat handoff overlay — the person tapped Accept on a handover request and their phone is now connecting to the sender's phone. The argument is the sender's name.")
            }
            if let partnerName, !partnerName.isEmpty {
                return String(localized: "Waiting for \(partnerName) to shake…",
                              bundle: .appLanguage, locale: .appLanguage, comment: "Hoofbeat handoff overlay — the person tapped a nearby courier to hand them a ram and is waiting for that courier to shake their phone too. The argument is the courier's name.")
            }
            return String(localized: "Listening for hoofbeats nearby…",
                          bundle: .appLanguage, locale: .appLanguage, comment: "Hoofbeat handoff overlay — status shown while searching for a nearby phone to exchange a letter with in person.")
        case .connecting(let peerName):
            return String(localized: "Meeting \(peerName)…",
                          bundle: .appLanguage, locale: .appLanguage, comment: "Hoofbeat handoff overlay — a nearby phone was found and the in-person exchange is about to begin. The argument is the other person's name.")
        case .exchanging(let peerName):
            return String(localized: "Passing the satchel to \(peerName)…",
                          bundle: .appLanguage, locale: .appLanguage, comment: "Hoofbeat handoff overlay — the letter is being exchanged with the nearby phone, in person. The argument is the other person's name.")
        case .finished(let summary):
            return summary
        case .failed(let reason):
            return reason
        }
    }
}

#Preview("Searching") {
    HoofbeatOverlay(phase: .searching, successTick: 0, onDismiss: {}, onRetry: {})
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
}

#Preview("Waiting for a shake") {
    HoofbeatOverlay(phase: .searching, successTick: 0, partnerName: "Marcel", onDismiss: {}, onConfirm: {})
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
}

#Preview("Exchanging") {
    HoofbeatOverlay(phase: .exchanging(peerName: "Anton"), successTick: 0, onDismiss: {})
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
}

#Preview("Failed") {
    HoofbeatOverlay(phase: .failed(reason: "No one shook back nearby."), successTick: 0, onDismiss: {}, onRetry: {})
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
}

#Preview("Finished") {
    HoofbeatOverlay(phase: .finished(summary: "Klaus went with Anton."), successTick: 1, onDismiss: {})
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
}
