//
//  MailbagCards.swift
//  Baranov
//
//  The building blocks of the mailbag drawer on the main map: the section
//  filter, the status text, the ram row (portrait, route, progress), the
//  collapsed bar for the most urgent courier, and the native list rows.
//  A card only ever *opens* something — the letter (`LetterDetailView`,
//  presented by `RootView`) — so it owns no sheets of its own.
//
//  System materials and semantic styles only — no gradients, no glow.
//

import SwiftUI
import UIKit

// MARK: - Section

enum MailbagSection: String, CaseIterable, Identifiable {
    case incoming, outgoing, archive

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .incoming: "Incoming"
        case .outgoing: "Outgoing"
        case .archive: "Archive"
        }
    }
}

// MARK: - Status badge

struct MailbagStatusBadge: View {
    let ram: Ram
    /// The sender's view of a ram at the gate: the letter was *left* there.
    var isOutgoing: Bool = false
    var font: Font = .caption.weight(.medium)

    private var content: (text: LocalizedStringKey, tint: Color) {
        switch ram.status {
        case .arrivedAtGate: (isOutgoing ? "Left at the gate" : "At the gate", .wax)
        case .delivered: ("Delivered", .wax)
        case .atSea: ("At sea", .accentColor)
        case .waitingForHandoff: ("At the port", .accentColor)
        case .handedOff: ("Handed on", .secondary)
        case .grazing: ("Waiting for your first steps", .secondary)
        case .walking: ("On the way", .accentColor)
        }
    }

    var body: some View {
        Text(content.text)
            .font(font)
            .foregroundStyle(content.tint)
            .lineLimit(1)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: ram.status)
    }
}

// MARK: - Route progress

extension Ram {
    /// On the road (or the water): the only time a route bar means anything.
    var isEnRoute: Bool {
        status == .walking || status == .waitingForHandoff || status == .atSea
    }
}

/// A slider-shaped read-only track for one leg: where it started, where
/// the letter is going, and the ram's own marker sliding between them.
/// Shown only while the ram is actually on its way. Not interactive.
struct RouteProgressBar: View {
    let ram: Ram
    var showsPlaces: Bool = false

    private let markerDiameter: CGFloat = 26

    private var progress: CGFloat { CGFloat(min(max(ram.progress, 0), 1)) }
    private var originName: String { ram.routeHistory.first?.cityName ?? ram.currentCity }
    private var goalName: String { ram.requiresHandoffAtLegEnd ? ram.legDestinationCity : ram.targetCity }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let inset = markerDiameter / 2
                let travel = max(0, proxy.size.width - inset * 2)
                let x = inset + travel * progress

                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                        .frame(width: travel, height: 4)
                        .offset(x: inset)
                    Capsule().fill(Color.accentColor)
                        .frame(width: max(0, x - inset), height: 4)
                        .offset(x: inset)

                    endpoint(systemImage: "circle.fill")
                        .position(x: inset, y: markerDiameter / 2)
                    endpoint(systemImage: ram.requiresHandoffAtLegEnd ? "ferry.fill" : "flag.checkered")
                        .position(x: inset + travel, y: markerDiameter / 2)

                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: markerDiameter, height: markerDiameter)
                        .background(Color.accentColor, in: Circle())
                        .position(x: x, y: markerDiameter / 2)
                        .animation(.smooth(duration: 0.6), value: progress)
                }
            }
            .frame(height: markerDiameter)

            if showsPlaces {
                HStack(spacing: 8) {
                    Text(originName).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(goalName).lineLimit(1)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((progress * 100).rounded())) percent of the way from \(originName) to \(goalName)")
    }

    private func endpoint(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 18)
            .background(.thinMaterial, in: Circle())
    }
}

// MARK: - Ram row

/// One courier, the same way everywhere (collapsed drawer and list): its
/// portrait, who the letter is with, one line of route, and — while it is
/// on the road — a plain progress bar with the distance left.
struct MailbagRamRow: View {
    let ram: Ram
    let isOutgoing: Bool
    /// The smallest sheet: who it is to, the destination and a thin progress bar.
    var isSlim = false
    /// The large deck card: bigger portrait and type, the same content.
    var isCard = false

    private var counterpart: String {
        let name = isOutgoing ? ram.letter?.recipientName : ram.letter?.senderName
        return (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var title: String {
        // Someone else's letter I'm only carrying: whose, and for whom.
        if ram.isGuest, let letter = ram.letter {
            let sender = letter.senderName.trimmingCharacters(in: .whitespacesAndNewlines)
            let recipient = letter.recipientName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sender.isEmpty, !recipient.isEmpty {
                return String(localized: "\(sender)'s letter for \(recipient)", bundle: .appLanguage, locale: .appLanguage)
            }
        }
        if counterpart.isEmpty { return ram.name }
        return isOutgoing
            ? String(localized: "To \(counterpart)", bundle: .appLanguage, locale: .appLanguage)
            : String(localized: "From \(counterpart)", bundle: .appLanguage, locale: .appLanguage)
    }

    private var originName: String {
        (ram.routeHistory.first?.cityName ?? ram.currentCity).mailbagShortName
    }

    /// Who is actually carrying the letter right now, by name — the row's
    /// portrait alone didn't say it.
    private var carrierText: String {
        let base: String
        switch ram.status {
        case .grazing, .walking:
            base = String(localized: "Carried by \(ram.name)", bundle: .appLanguage, locale: .appLanguage)
        case .waitingForHandoff:
            base = String(localized: "\(ram.name) is waiting at the port", bundle: .appLanguage, locale: .appLanguage)
        case .atSea:
            base = String(localized: "\(ram.name) is aboard the packet", bundle: .appLanguage, locale: .appLanguage)
        case .handedOff:
            base = String(localized: "Someone else carries it now", bundle: .appLanguage, locale: .appLanguage)
        case .arrivedAtGate, .delivered:
            base = String(localized: "Brought by \(ram.name)", bundle: .appLanguage, locale: .appLanguage)
        }
        let extra = ram.passengerLetters.count
        guard extra > 0, ram.status != .handedOff else { return base }
        return String(localized: "\(base), with \(extra) more letters", bundle: .appLanguage, locale: .appLanguage)
    }

    /// Where a leg ends short of the real destination: a port or border
    /// where the ram is handed on rather than walking further.
    private var handoffName: String? {
        ram.requiresHandoffAtLegEnd ? ram.legDestinationCity.mailbagShortName : nil
    }

    /// The other letters in the same bag, by recipient.
    private var passengerText: String? {
        let names = ram.passengerLetters
            .map { $0.recipientName.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        return String(localized: "Also for \(names.formatted(.list(type: .and)))", bundle: .appLanguage, locale: .appLanguage)
    }

    private func placeLine(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        if isSlim { slimBody } else if isCard { cardBody } else { fullBody }
    }

    /// The smallest sheet names only the receiver — the sender is usually
    /// the person themselves, so "Anton's letter for" said nothing new.
    private var slimTitle: String {
        if ram.isGuest, let letter = ram.letter {
            let recipient = letter.recipientName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !recipient.isEmpty { return recipient }
        }
        if isOutgoing, !counterpart.isEmpty { return counterpart }
        return title
    }

    /// Destination, then the distance left while it is on the road.
    private var slimPlaceLine: String {
        let place = ram.targetCity.mailbagShortName
        guard ram.isEnRoute else { return place }
        let left = String(localized: "\(DistanceFormatter.string(forMeters: ram.remainingSteps)) left", bundle: .appLanguage, locale: .appLanguage)
        return "\(place) · \(left)"
    }

    private var slimBody: some View {
        HStack(spacing: 10) {
            RamPortraitView(name: ram.name, diameter: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(slimTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    MailbagStatusBadge(ram: ram, isOutgoing: isOutgoing)
                }
                // Where it is going, then how far is left; a thin bar below.
                Text(slimPlaceLine)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if ram.isEnRoute {
                    ProgressView(value: min(max(ram.progress, 0), 1))
                        .tint(Color.accentColor)
                        .padding(.top, 2)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// The deck card: a large portrait and title, status underneath, then
    /// the route and progress with room to breathe.
    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                RamPortraitView(name: ram.name, diameter: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    MailbagStatusBadge(ram: ram, isOutgoing: isOutgoing,
                                       font: .subheadline.weight(.medium))
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                placeLine("pawprint.fill", carrierText)
                placeLine("circle", originName)
                placeLine("mappin.and.ellipse", ram.targetCity.mailbagShortName)
                if let handoffName {
                    placeLine("arrow.triangle.swap", String(localized: "Handoff at \(handoffName)", bundle: .appLanguage, locale: .appLanguage))
                }
                if let passengerText {
                    placeLine("envelope.fill", passengerText)
                }
            }

            if ram.isEnRoute {
                HStack(spacing: 10) {
                    ProgressView(value: min(max(ram.progress, 0), 1))
                        .tint(Color.accentColor)
                    Text("\(DistanceFormatter.string(forMeters: ram.remainingSteps)) left")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var fullBody: some View {
        HStack(spacing: 12) {
            RamPortraitView(name: ram.name, diameter: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    MailbagStatusBadge(ram: ram, isOutgoing: isOutgoing)
                }
                // Who carries it, then one place per line — origin,
                // destination and, when the journey is passed on, the
                // handoff — so nothing is cut off.
                placeLine("pawprint.fill", carrierText)
                placeLine("circle", originName)
                placeLine("mappin.and.ellipse", ram.targetCity.mailbagShortName)
                if let handoffName {
                    placeLine("arrow.triangle.swap", String(localized: "Handoff at \(handoffName)", bundle: .appLanguage, locale: .appLanguage))
                }
                if let passengerText {
                    placeLine("envelope.fill", passengerText)
                }

                if ram.isEnRoute {
                    HStack(spacing: 8) {
                        ProgressView(value: min(max(ram.progress, 0), 1))
                            .tint(Color.accentColor)
                        Text("\(DistanceFormatter.string(forMeters: ram.remainingSteps)) left")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    .padding(.top, 2)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Collapsed bar

/// What the drawer shows at its smallest detent: the most urgent courier,
/// with the one action that matters once it has reached the gate.
struct MailbagCollapsedBar: View {
    let ram: Ram
    /// Only true for a letter addressed to this person — a ram carrying
    /// their own letter to someone else has nothing to open.
    let canBreakSeal: Bool
    let onExpand: () -> Void
    let onBreakSeal: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onExpand) {
                MailbagRamRow(ram: ram, isOutgoing: !canBreakSeal, isSlim: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the letter")

            if ram.status == .arrivedAtGate, canBreakSeal {
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
                .tint(.green)
            }
        }
        .animation(.snappy, value: ram.status)
    }
}

/// The collapsed bar when nothing is out: the person's own ram, at rest.
struct MailbagIdleBar: View {
    let name: String

    var body: some View {
        HStack(spacing: 12) {
            RamPortraitView(name: name, diameter: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("Ready for a letter")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - List row

/// A courier as a native list row: tap opens the letter (the bag is in the
/// long-press menu); breaking the seal
/// shows only when it is actually possible; "Cancel Journey" is a swipe
/// action, sharing the code lives in the long-press menu.
struct MailbagCourierRow: View {
    let ram: Ram
    let isOutgoing: Bool
    let carrierName: String
    let onOpenBag: () -> Void
    let onOpenLetter: () -> Void
    var onCancel: (() -> Void)? = nil

    @State private var isCancelConfirmationPresented = false

    private var canCancel: Bool {
        isOutgoing && onCancel != nil
            && (ram.status == .grazing || ram.status == .walking || ram.status == .waitingForHandoff)
    }

    private var canBreakSeal: Bool { !isOutgoing && ram.status == .arrivedAtGate }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpenLetter) {
                MailbagRamRow(ram: ram, isOutgoing: isOutgoing)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the letter")

            if isOutgoing, ram.status != .delivered, let message = ram.letterShareMessage {
                ShareLink(item: message) {
                    if ram.letter?.relayTicket != nil {
                        Label("Share tracking link", systemImage: "square.and.arrow.up")
                    } else {
                        Label("Share code", systemImage: "square.and.arrow.up")
                    }
                }
                .buttonStyle(ShareCodeGlassButtonStyle(expands: true))
            }

            if canBreakSeal {
                Button {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    onOpenLetter()
                } label: {
                    Label("Break the Seal and Read", systemImage: "seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.green)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: onOpenBag) {
                Label("Ram's Bag", systemImage: "bag")
            }
            .tint(.accentColor)
            if canCancel {
                Button(role: .destructive) {
                    isCancelConfirmationPresented = true
                } label: {
                    Label("Cancel Journey", systemImage: "xmark")
                }
            }
        }
        .contextMenu {
            Button(action: onOpenBag) {
                Label("Ram's Bag", systemImage: "bag")
            }
            if let message = ram.letterShareMessage {
                ShareLink(item: message) {
                    Label("Share Code", systemImage: "square.and.arrow.up")
                }
            }
            if canCancel {
                Button(role: .destructive) {
                    isCancelConfirmationPresented = true
                } label: {
                    Label("Cancel Journey", systemImage: "xmark")
                }
            }
        }
        .confirmationDialog("Cancel this journey?", isPresented: $isCancelConfirmationPresented, titleVisibility: .visible) {
            Button("Cancel Journey", role: .destructive) { onCancel?() }
            Button("Keep Walking", role: .cancel) {}
        } message: {
            Text("\(ram.name) will come home and the letter is withdrawn.")
        }
    }
}

extension String {
    /// The part of an address a person would say aloud: everything before
    /// the first comma.
    var mailbagShortName: String {
        let first = split(separator: ",").first.map(String.init) ?? self
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? self : trimmed
    }
}

// MARK: - Held letter row

/// A letter sent by Shepherd ID or ear tag before the recipient's gate was
/// known: its ram sets out on its own once they open the link.
struct MailbagHeldRow: View {
    let record: LetterTracker.Record

    private var ramName: String { record.ramName ?? "" }

    private var shareMessage: String? {
        LetterTracker.shared.heldLetter(for: record.letterID)?.awaitingGateShareMessage(ramName: ramName)
    }

    var body: some View {
        HStack(spacing: 12) {
            RamPortraitView(name: ramName, diameter: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("For \(record.recipientName)")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text("\(ramName) sets out when \(record.recipientName) opens your link.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let shareMessage {
                ShareLink(item: shareMessage) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Share tracking link")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - A letter someone said is coming

/// "A letter from Anton is on its way": known only from the link in the
/// code message, so there is no progress bar — just who, which ram, where
/// and roughly when.
struct ExpectedLetterRow: View {
    let letter: ExpectedLetter

    private var title: String {
        letter.senderName.isEmpty
            ? String(localized: "A letter is on its way to you", bundle: .appLanguage, locale: .appLanguage)
            : String(localized: "A letter from \(letter.senderName) is on its way", bundle: .appLanguage, locale: .appLanguage)
    }

    private var detail: String {
        var parts: [String] = []
        if !letter.ramName.isEmpty {
            parts.append(String(localized: "Carried by \(letter.ramName)", bundle: .appLanguage, locale: .appLanguage))
        }
        if !letter.city.isEmpty {
            parts.append(String(localized: "to \(letter.city.mailbagShortName)", bundle: .appLanguage, locale: .appLanguage))
        }
        if let expectedBy = letter.expectedBy {
            parts.append(String(localized: "around \(expectedBy.formatted(.dateTime.month(.abbreviated).day().locale(.appLanguage)))", bundle: .appLanguage, locale: .appLanguage))
        }
        return parts.joined(separator: " · ")
    }

    /// Where the ram is now, as the post office last heard. `nil` until the
    /// relay has answered (a link-only card shows just the line above).
    private var liveLine: String? {
        if letter.deliveredAt != nil {
            return String(localized: "Arrived. Bringing it into your mailbag…", bundle: .appLanguage, locale: .appLanguage)
        }
        guard letter.relayKnowsIt == true else { return nil }
        if letter.awaitingGate == true || letter.status == "awaitingGate" {
            return GateStore.shared.gate == nil
                ? String(localized: "Ready to set out. Allow location so it knows where your gate is.", bundle: .appLanguage, locale: .appLanguage)
                : String(localized: "Ready to set out for your gate", bundle: .appLanguage, locale: .appLanguage)
        }
        guard let status = letter.relayStatus else { return nil }
        let place = (letter.currentCity ?? "").mailbagShortName
        let walker = letter.senderName.isEmpty
            ? String(localized: "The ram", bundle: .appLanguage, locale: .appLanguage)
            : letter.senderName
        switch status {
        case .waitingForHandoff:
            return place.isEmpty
                ? String(localized: "Waiting at the port", bundle: .appLanguage, locale: .appLanguage)
                : String(localized: "Waiting at the port in \(place)", bundle: .appLanguage, locale: .appLanguage)
        case .atSea:
            return String(localized: "At sea", bundle: .appLanguage, locale: .appLanguage)
        case .grazing where (letter.metersWalked ?? 0) == 0:
            return String(localized: "Just set out", bundle: .appLanguage, locale: .appLanguage)
        default:
            let toGo = DistanceFormatter.string(forMeters: letter.metersToGo ?? 0)
            return String(localized: "\(walker) is walking to your gate · \(toGo) to go", bundle: .appLanguage, locale: .appLanguage)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            if letter.ramName.isEmpty {
                Image(systemName: "envelope.badge.clock")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            } else {
                RamPortraitView(name: letter.ramName, diameter: 44)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let liveLine {
                    Text(liveLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let progress: Double = letter.deliveredAt != nil ? Optional(1.0) : letter.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .padding(.top, 4)
                        .accessibilityLabel("Journey")
                        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
