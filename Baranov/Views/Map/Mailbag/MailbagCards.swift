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

    private var content: (text: LocalizedStringKey, tint: Color) {
        switch ram.status {
        case .arrivedAtGate: (isOutgoing ? "Left at the Gate" : "At the Gate", .wax)
        case .delivered: ("Delivered", .wax)
        case .atSea: ("At Sea", .accentColor)
        case .waitingForHandoff: ("At the Port", .accentColor)
        case .handedOff: ("Handed On", .secondary)
        case .grazing: ("Ready to set out", .secondary)
        case .walking: ("On the Way", .accentColor)
        }
    }

    var body: some View {
        Text(content.text)
            .font(.caption.weight(.medium))
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
    /// The two smallest sheets: name, one line of route and a thin bar.
    var isSlim = false

    private var counterpart: String {
        let name = isOutgoing ? ram.letter?.recipientName : ram.letter?.senderName
        return (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var title: String {
        if counterpart.isEmpty { return ram.name }
        return isOutgoing
            ? String(localized: "To \(counterpart)")
            : String(localized: "From \(counterpart)")
    }

    private var originName: String {
        (ram.routeHistory.first?.cityName ?? ram.currentCity).mailbagShortName
    }

    /// Where a leg ends short of the real destination: a port or border
    /// where the ram is handed on rather than walking further.
    private var handoffName: String? {
        ram.requiresHandoffAtLegEnd ? ram.legDestinationCity.mailbagShortName : nil
    }

    private func placeLine(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    var body: some View {
        if isSlim { slimBody } else { fullBody }
    }

    private var slimBody: some View {
        HStack(spacing: 10) {
            RamPortraitView(name: ram.name, diameter: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    MailbagStatusBadge(ram: ram, isOutgoing: isOutgoing)
                }
                Text("\(originName) → \(ram.targetCity.mailbagShortName)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if ram.isEnRoute {
                    ProgressView(value: min(max(ram.progress, 0), 1))
                        .tint(Color.accentColor)
                }
            }
        }
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
                // One place per line — origin, destination and, when the
                // journey is passed on, the handoff — so nothing is cut off.
                placeLine("circle", originName)
                placeLine("mappin.and.ellipse", ram.targetCity.mailbagShortName)
                if let handoffName {
                    placeLine("arrow.triangle.swap", String(localized: "Handoff at \(handoffName)"))
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
                MailbagRamRow(ram: ram, isOutgoing: !canBreakSeal)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
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
            if let message = ram.letter?.shareMessage(carrierName: carrierName) {
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

// MARK: - Published (by code) letter row

/// A letter published through the relay: waiting for its recipient, or claimed.
struct MailbagPublishedRow: View {
    let published: PublishedLetter

    private var displayCode: String {
        published.code.count == 6
            ? "\(published.code.prefix(3))-\(published.code.dropFirst(3))" : published.code
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: published.isClaimed ? "envelope.open.fill" : "envelope.fill")
                .font(.body)
                .foregroundStyle(published.isClaimed ? Color.green : Color.accentColor)
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("For \(published.recipientName)")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(published.isClaimed ? String(localized: "Picked up") : String(localized: "Code \(displayCode)"))
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !published.isClaimed {
                ShareLink(item: String(localized: "Claim my Baranov letter with this code: \(published.code)")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Share Code")
            }
        }
        .padding(.vertical, 2)
    }
}
