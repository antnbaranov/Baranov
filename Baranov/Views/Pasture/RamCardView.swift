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

import MapKit
import SwiftUI

struct RamCardView: View {
    let ram: Ram
    var isSelected: Bool = false
    var matchedCarriers: [KnownCarrier] = []
    /// Opens the letter-arrival ritual. Only surfaced while the ram is
    /// `.arrivedAtGate`, as the card's primary call to action. `nil`
    /// hides the button (the whole card stays tappable from the parent).
    var onBreakSeal: (() -> Void)? = nil
    /// Confirms that this ram really did go with somebody. AirDrop gives no
    /// delivery receipt — `ShareLink` cannot tell us whether the other
    /// phone accepted — so after an AirDrop handoff the person says so
    /// themselves, and the ram stops walking here. `nil` hides the action.
    var onMarkHandedOff: (() -> Void)? = nil
    /// Shows the "is this letter for you?" check inline, inside the card,
    /// instead of pushing a separate screen.
    var gateExpanded: Bool = false
    /// Called from the inline check once the recipient is verified.
    var onGateVerified: (() -> Void)? = nil

    /// Animated display progress for the route ProgressView — animates
    /// from 0 on first appear, then tracks `ram.progress` live.
    @State private var displayProgress: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            routeHero

            VStack(alignment: .leading, spacing: 16) {
                headerBlock

                if gateExpanded, let onGateVerified {
                    LetterGateNoticeView(ram: ram, onVerified: onGateVerified)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                journeyTrack

                statsRow

                if ram.status == .waitingForHandoff || ram.status == .atSea {
                    PassageNoticeView(ram: ram)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if ram.status == .waitingForHandoff {
                    airDropBlock
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if ram.letter != nil || !ram.passengerLetters.isEmpty {
                    lettersBlock
                        .transition(.opacity)
                }
            }
            .padding(18)
        }
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.8).delay(0.15)) {
                displayProgress = ram.progress
            }
        }
        .onChange(of: ram.progress) { _, newValue in
            withAnimation(.easeOut(duration: 0.5)) {
                displayProgress = newValue
            }
        }
    }

    // MARK: - Route hero

    /// The journey drawn as a small live map: the dotted trail, where it
    /// began, where this leg ends, and the ram itself right now. Not
    /// interactive — it is a picture of the route, not a second map screen.
    private var routeHero: some View {
        let coords = ram.routeCoordinates.map(\.clLocationCoordinate)
        return Map(initialPosition: .rect(Self.mapRect(fitting: coords + [ram.currentCoordinate].compactMap { $0 })), interactionModes: []) {
            if coords.count > 1 {
                MapPolyline(coordinates: coords)
                    .stroke(RamMarkerPalette.routeTrail, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 8]))
            }
            if let start = coords.first {
                Annotation("", coordinate: start) {
                    Circle()
                        .fill(.background)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(.primary, lineWidth: 3))
                }
            }
            if let end = coords.last, coords.count > 1 {
                Annotation("", coordinate: end) {
                    Image(systemName: "flag.checkered")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 30)
                        .background(.regularMaterial, in: Circle())
                }
            }
            if let here = ram.currentCoordinate {
                Annotation("", coordinate: here) {
                    Image(systemName: "pawprint.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.accentColor, in: Circle())
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .frame(height: 150)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var statusIcon: String {
        switch ram.status {
        case .delivered: return "checkmark.seal.fill"
        case .arrivedAtGate: return "envelope.badge.fill"
        case .atSea: return "water.waves"
        case .waitingForHandoff: return "hand.raised.fill"
        default: return "figure.walk"
        }
    }

    private static func mapRect(fitting coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        guard !coordinates.isEmpty else { return .world }
        var rect = MKMapRect.null
        for c in coordinates {
            let point = MKMapPoint(c)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        let pad = max(rect.width, rect.height) * 0.35 + 4_000
        return rect.insetBy(dx: -pad, dy: -pad)
    }

    // MARK: - Header

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// Who it's for, who it's from, and where it stands — plain type,
    /// one calm call to action when the letter has arrived.
    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ram.letter.map { "To \($0.recipientName)" } ?? ram.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    if let letter = ram.letter {
                        Text("From \(letter.senderName) · \(ram.name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Label(ram.status.displayName, systemImage: statusIcon)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if ram.status == .arrivedAtGate, let onBreakSeal {
                Button {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    onBreakSeal()
                } label: {
                    Label("Break the Seal", systemImage: "seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .accessibilityHint("Opens the letter")
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
                .accessibilityHint("Opens the share sheet so you can AirDrop \(ram.name) to someone traveling toward \(ram.targetCity)")
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
        .frame(maxWidth: .infinity, alignment: .leading)
        
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

    /// Apple Maps-style route: a filled dot for where it started, a pin
    /// for where it's going, and a short track between them that fills
    /// as the ram walks.
    private var journeyTrack: some View {
        let progress = min(max(displayProgress, 0), 1)
        return VStack(alignment: .leading, spacing: 0) {
            placeRow(symbol: "circle.fill", tint: .secondary, size: 9, caption: "From", city: ram.currentCity)

            HStack(spacing: 12) {
                ZStack(alignment: .top) {
                    Capsule().fill(.quaternary).frame(width: 3, height: 30)
                    Capsule().fill(Color.accentColor).frame(width: 3, height: 30 * progress)
                }
                .frame(width: 20)
                Text("\(Int(progress * 100))%")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .padding(.vertical, 2)

            placeRow(symbol: "mappin.circle.fill", tint: .red, size: 20, caption: "To", city: ram.targetCity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel({
            var label = "Route: \(ram.currentCity) to \(ram.targetCity). \(Int(ram.progress * 100)) percent complete"
            if ram.remainingSteps > 0 {
                label += ", \(DistanceFormatter.string(forMeters: ram.remainingSteps)) remaining"
            } else {
                label += ", arrived"
            }
            return label
        }())
    }

    private func placeRow(symbol: String, tint: Color, size: CGFloat, caption: LocalizedStringKey, city: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(caption).font(.caption).foregroundStyle(.secondary)
                Text(city).font(.headline).lineLimit(1)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            stat(DistanceFormatter.string(forMeters: ram.journeyStepsSoFar), "walked")
            Divider().frame(height: 28)
            stat(ram.remainingSteps > 0 ? DistanceFormatter.string(forMeters: ram.remainingSteps) : "0", "to go")
        }
    }

    private func stat(_ value: String, _ caption: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        
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
            Label("Share Ear Tag", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(ShareCodeGlassButtonStyle(tint: PastureTheme.green, expands: true))
        .simultaneousGesture(TapGesture().onEnded { impact(.light) })
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
        RamCardView(ram: FlockViewModel.preview.activeRams[0])
        RamCardView(
            ram: FlockViewModel.preview.activeRams[0],
            isSelected: true,
            matchedCarriers: KnownCarrierDirectory.preview.carriers,
            onBreakSeal: {}
        )
    }
    .padding()
}
