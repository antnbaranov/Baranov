//
//  RamCardView.swift
//  Baranov
//
//  A single ram's card in the Pasture satchel, laid out as distinct
//  blocks stacked top to bottom: its status/name header, an AirDrop
//  block (only while it's actually waiting for a handoff), its current
//  route/progress, and — if it's carrying a letter — a block for that.
//  The AirDrop block surfaces any known carrier already headed to, or
//  within 800 km of, this ram's true destination ahead of a bare "hand
//  off to whoever" button, so a handoff can go to someone actually going
//  the right way when one's on file.
//

import SwiftUI

struct RamCardView: View {
    let ram: Ram
    var isSelected: Bool = false
    var matchedCarriers: [KnownCarrier] = []
    /// Opens this ram's passport (`RamHistoryView`) — the passport's only
    /// entry point now lives on the card itself (the luggage tag pinned
    /// to its top-trailing corner) rather than as a separate button
    /// elsewhere in Pasture. `nil` hides the tag entirely.
    var onPassportTapped: (() -> Void)? = nil
    /// Confirms that this ram really did go with somebody. AirDrop gives no
    /// delivery receipt — `ShareLink` cannot tell us whether the other
    /// phone accepted — so after an AirDrop handoff the person says so
    /// themselves, and the ram stops walking here. `nil` hides the action.
    var onMarkHandedOff: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerBlock

            if ram.status == .waitingForHandoff || ram.status == .atSea {
                PassageNoticeView(ram: ram)
            }

            if ram.status == .waitingForHandoff {
                airDropBlock
            }

            routeBlock

            if ram.letter != nil || !ram.passengerLetters.isEmpty {
                lettersBlock
            }
        }
        .padding(14)
        // Borderless — selection no longer draws an accent-colored ring
        // (a colored stroke reads as a state error more than a state,
        // and clashed the moment the accent color changed). Elevation
        // does the same job instead: a soft, neutral shadow that simply
        // sits a touch deeper when this card is the selected one, same
        // family as every other card in Pasture rather than a one-off
        // border treatment.
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(
            color: .black.opacity(isSelected ? 0.16 : 0.06),
            radius: isSelected ? 10 : 4,
            x: 0,
            y: isSelected ? 4 : 2
        )
    }

    // MARK: - Passport tag

    /// A hanging luggage tag pinned to the card's corner — the satchel's
    /// own way of saying "there's a passport in here." Tapping it opens
    /// the same `RamHistoryView` the old standalone "Passport" button
    /// did; nothing about the destination changed, only where the door
    /// to it lives.
    private func passportTag(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Passport")
                    .font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .rotationEffect(.degrees(6))
        .accessibilityLabel("Open \(ram.name)'s passport")
    }

    // MARK: - Header block

    private var headerBlock: some View {
        HStack(alignment: .top, spacing: 14) {
            RamPortraitView(name: ram.name, diameter: 44)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: ram.status.symbolName)
                        .font(.caption2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                        .padding(3)
                        .background(.regularMaterial, in: Circle())
                        .offset(x: 3, y: 3)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(ram.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    // Used to float as an absolutely-positioned overlay
                    // pinned to the card's top-trailing corner — which
                    // sat directly on top of this very status text
                    // whenever the status was wider than a couple of
                    // letters. Laying it out inline, right here, means
                    // it can never collide with anything: the row just
                    // makes room for it like any other trailing content.
                    if let onPassportTapped {
                        passportTag(action: onPassportTapped)
                    }
                    Text(ram.status.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }

                if ram.status == .arrivedAtGate {
                    Text("Tap to break the seal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    // MARK: - AirDrop block

    private var airDropBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Send it with a person", systemImage: "figure.walk.departure")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if matchedCarriers.isEmpty {
                ShareLink(
                    item: RamTransitPackage(ram: ram),
                    preview: SharePreview(
                        "\(ram.name) → \(ram.legDestinationCity)",
                        image: Image(systemName: "pawprint.circle.fill")
                    )
                ) {
                    Label("Hand Off via AirDrop", systemImage: "airplane.departure")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Heading the same way")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    ForEach(matchedCarriers) { carrier in
                        carrierRow(carrier)
                    }
                }
            }

            if let onMarkHandedOff {
                Button("It went with someone", systemImage: "checkmark.circle") {
                    onMarkHandedOff()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func carrierRow(_ carrier: KnownCarrier) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(carrier.name)
                    .font(.caption.weight(.medium))
                Text("Heading to \(carrier.destinationCity)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ShareLink(
                item: RamTransitPackage(ram: ram),
                preview: SharePreview(
                    "\(ram.name) → \(ram.legDestinationCity)",
                    image: Image(systemName: "pawprint.circle.fill")
                )
            ) {
                Image(systemName: "airplane.departure")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Hand off to \(carrier.name)")
        }
    }

    // MARK: - Route block

    private var routeBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(ram.currentCity) → \(ram.targetCity)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView(value: ram.progress)
                .tint(.primary)

            if ram.remainingSteps > 0 {
                Text("\(DistanceFormatter.string(forMeters: ram.remainingSteps)) remaining")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Letters block

    /// This ram's own letter (if drafted), plus any passengers picked up
    /// along the way — each its own row, all sharing one block.
    private var lettersBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let letter = ram.letter {
                letterRow(letter, isPassenger: false)
            }
            ForEach(ram.passengerLetters) { letter in
                letterRow(letter, isPassenger: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func letterRow(_ letter: Letter, isPassenger: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if letter.isEncrypted {
                    Image(systemName: letter.isSealed ? "lock.fill" : "lock.open.fill")
                        .font(.caption2)
                } else {
                    Image(systemName: "envelope.open")
                        .font(.caption2)
                }
                Text(letterRowLabel(for: letter, isPassenger: isPassenger))
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            // Only this ram's own letter — not a passenger it picked up
            // along the way, which isn't this sender's to hand a code
            // out for.
            if !isPassenger, let shareMessage = letter.shareMessage(carrierName: ram.name) {
                shareCodeButton(shareMessage)
            }
        }
    }

    /// Lets the sender hand the recipient this letter's receiving code
    /// out of band — over iMessage, most naturally — instead of making
    /// them wait for the ram to physically finish its walk before they
    /// know how to open it. `ShareLink` opens the system share sheet
    /// (Messages included), matching the AirDrop hand-off above rather
    /// than introducing a separate, bespoke "compose an iMessage" screen.
    private func shareCodeButton(_ shareMessage: String) -> some View {
        ShareLink(item: shareMessage) {
            Label("Share Receiving Code", systemImage: "message.fill")
                .font(.caption2.weight(.semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }

    private func letterRowLabel(for letter: Letter, isPassenger: Bool) -> String {
        let kind = letter.isEncrypted ? "a sealed letter" : "an open postcard"
        guard isPassenger else {
            return letter.isSealed ? "Carrying \(kind) from \(letter.senderName)" : "Delivered from \(letter.senderName)"
        }
        return letter.isSealed
            ? "Also carrying \(kind) from \(letter.senderName)"
            : "Also carried a letter from \(letter.senderName)"
    }
}

#Preview {
    VStack(spacing: 12) {
        RamCardView(ram: FlockViewModel.preview.activeRams[0], onPassportTapped: {})
        RamCardView(
            ram: FlockViewModel.preview.activeRams[0],
            isSelected: true,
            matchedCarriers: KnownCarrierDirectory.preview.carriers,
            onPassportTapped: {}
        )
    }
    .padding()
}
