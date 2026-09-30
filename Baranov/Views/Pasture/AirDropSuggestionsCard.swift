//
//  AirDropSuggestionsCard.swift
//  Baranov
//
//  The carriers card beneath the ram selector — the "departures board"
//  for whichever ram is selected. Four things, in the order a shepherd
//  needs them:
//
//  1. **Hand off now** — when the ram is waiting at a coast or border:
//     known carriers already headed the same way, each with a one-tap
//     AirDrop, or a generic hand-off when nobody's lined up.
//  2. **Line one up early** — while the ram is still walking toward a
//     handoff stop, a share-sheet message asking someone to carry it on
//     from there ("Heading east from Halifax? Klaus needs a ride…"), so
//     a carrier can be arranged days before the ram reaches the dock.
//  3. **Friends on Baranov** — Game Center friends as one-tap carriers
//     (opens the directory with their name filled in; GameKit knows who
//     your friends are, not where they're going — you add that).
//  4. **Your upcoming trips** — Calendar chips that register *you* as a
//     carrier to somewhere, so other people's rams can find you.
//
//  Genuinely gray (`.systemGray6`, not a material) so it reads as
//  visually distinct from the cards around it.
//

import SwiftUI

struct AirDropSuggestionsCard: View {
    let ram: Ram?
    let matchedCarriers: [KnownCarrier]
    let tripSuggestions: [TripSuggestion]
    let onAddTripAsCarrier: (TripSuggestion) -> Void

    /// The companion's name, shown in place of a bare "No ram selected"
    /// whenever nothing has been sent yet — the person does have a ram,
    /// it just hasn't set out on anything.
    var companionName: String? = nil

    /// Which trip chips already have a matching entry in the carrier
    /// directory — derived by `PastureView` from the directory itself.
    let addedSuggestionIDs: Set<UUID>

    /// Game Center friends, as candidate carriers. Empty when signed out
    /// or friend access wasn't granted — the row simply doesn't render.
    var friends: [GameCenterFriend] = []
    var onFriendTapped: (GameCenterFriend) -> Void = { _ in }

    /// How many carriers are in the directory, and how to open it.
    var knownCarrierCount: Int = 0
    var onManageTapped: () -> Void = {}

    /// The person's own name, for the "ask someone" message.
    var senderName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            handoffContent

            if let ram, let askMessage = askMessage(for: ram) {
                askSomeoneRow(ram: ram, message: askMessage)
            }

            if !friends.isEmpty {
                Divider()
                friendsRow
            }

            if !tripSuggestions.isEmpty {
                Divider()
                tripSuggestionChips
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Label("Carriers", systemImage: "person.2.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if knownCarrierCount > 0 {
                Button(action: onManageTapped) {
                    HStack(spacing: 4) {
                        Text("\(knownCarrierCount) known")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Manage carriers")
            }
            Button(action: onManageTapped) {
                Label("Add Courier", systemImage: "plus")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(Color.accentColor)
            .accessibilityLabel("Add a courier")
        }
    }

    // MARK: - Hand off now

    @ViewBuilder
    private var handoffContent: some View {
        if let ram, ram.status == .atSea {
            PassageNoticeView(ram: ram)
        } else if let ram, ram.status == .waitingForHandoff {
            if matchedCarriers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    PassageNoticeView(ram: ram)
                    ShareLink(
                        item: RamTransitPackage(ram: ram),
                        preview: SharePreview(
                            "\(ram.name) → \(ram.legDestinationCity)",
                            image: Image(systemName: "pawprint.circle.fill")
                        )
                    ) {
                        Label("Send \(ram.name) with someone", systemImage: "figure.walk.departure")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    PassageNoticeView(ram: ram)

                    Text("Heading the same way")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)

                    ForEach(matchedCarriers) { carrier in
                        carrierRow(carrier, ram: ram)
                    }
                }
            }
        } else if let ram, ram.requiresHandoffAtLegEnd {
            HStack(spacing: 10) {
                Image(systemName: "ferry.fill")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Next stop: \(ram.legDestinationCity)")
                        .font(.subheadline.weight(.medium))
                    Text(matchedCarriers.isEmpty
                         ? String(localized: "\(ram.name) boards a packet there — or goes with anyone crossing sooner.", bundle: .appLanguage, locale: .appLanguage)
                         : (matchedCarriers.count == 1
                            ? String(localized: "1 known carrier is headed toward \(ram.targetCity).", bundle: .appLanguage, locale: .appLanguage)
                            : String(localized: "\(matchedCarriers.count) known carriers are headed toward \(ram.targetCity).", bundle: .appLanguage, locale: .appLanguage)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        } else if ram == nil {
            if let companionName {
                Text("\(companionName) hasn't set out on a journey yet. Add the people you know who travel — their trips become shortcuts for your letters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No ram selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let ram {
            Text("\(ram.name)'s whole route is on land — no carrier needed this time.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func carrierRow(_ carrier: KnownCarrier, ram: Ram) -> some View {
        HStack(spacing: 10) {
            initialsAvatar(carrier.name)
            VStack(alignment: .leading, spacing: 1) {
                Text(carrier.name)
                    .font(.subheadline.weight(.medium))
                Text("Heading to \(carrier.destinationCity)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if ram.status == .waitingForHandoff {
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
        .padding(10)
        .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Ask someone

    /// A message worth sending days ahead: while the ram is still walking
    /// toward a handoff stop, or already waiting at one.
    private func askMessage(for ram: Ram) -> String? {
        guard ram.requiresHandoffAtLegEnd || ram.status == .waitingForHandoff else { return nil }
        let who = senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let intro = who.isEmpty ? String(localized: "Hi —", bundle: .appLanguage, locale: .appLanguage) : String(localized: "Hi, it's \(who) —", bundle: .appLanguage, locale: .appLanguage)
        let when = ram.status == .waitingForHandoff
            ? String(localized: "\(ram.name) is waiting at \(ram.legDestinationCity) right now", bundle: .appLanguage, locale: .appLanguage)
            : String(localized: "\(ram.name) will reach \(ram.legDestinationCity) in about \(DistanceFormatter.string(forMeters: ram.remainingSteps)) of walking", bundle: .appLanguage, locale: .appLanguage)
        return String(localized: "\(intro) are you heading toward \(ram.targetCity) soon? I'm sending a letter the slow way with Baranov: \(when), and it's waiting on a boat to cross. If you're passing through, shake phones with me or AirDrop and it rides with you instead — much faster. https://github.com/antnbaranov/Baranov", bundle: .appLanguage, locale: .appLanguage)
    }

    private func askSomeoneRow(ram: Ram, message: String) -> some View {
        ShareLink(item: message) {
            HStack(spacing: 10) {
                Image(systemName: "message.fill")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ask someone to carry \(ram.name) on")
                        .font(.subheadline.weight(.medium))
                    Text("A ready-written message for anyone travelling toward \(ram.targetCity).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Friends

    private var friendsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "gamecontroller.fill")
                    .font(.caption2)
                Text("Friends on Baranov")
                    .font(.caption2.weight(.semibold))
                    .textCase(.uppercase)
                Spacer()
                Text("tap to add as a carrier")
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(friends) { friend in
                        Button {
                            onFriendTapped(friend)
                        } label: {
                            VStack(spacing: 4) {
                                initialsAvatar(friend.displayName, diameter: 44)
                                Text(friend.displayName)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .frame(width: 64)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(friend.displayName) as a carrier")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func initialsAvatar(_ name: String, diameter: CGFloat = 32) -> some View {
        let initials = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
        return ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
            Text(initials.isEmpty ? "?" : initials)
                .font(.system(size: diameter * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: diameter, height: diameter)
    }

    // MARK: - Trips

    private var tripSuggestionChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Upcoming Trips")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tripSuggestions) { suggestion in
                        tripChip(suggestion)
                    }
                }
            }
        }
    }

    private func tripChip(_ suggestion: TripSuggestion) -> some View {
        let isAdded = addedSuggestionIDs.contains(suggestion.id)

        return Button {
            onAddTripAsCarrier(suggestion)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isAdded ? "checkmark" : "calendar")
                Text(suggestion.displayName)
                    .lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
    }
}

#Preview("Waiting for handoff") {
    AirDropSuggestionsCard(
        ram: FlockViewModel.preview.activeRams[0],
        matchedCarriers: KnownCarrierDirectory.preview.carriers,
        tripSuggestions: CalendarTripSuggestionService.preview.suggestions,
        onAddTripAsCarrier: { _ in },
        addedSuggestionIDs: [],
        friends: [GameCenterFriend(id: "1", displayName: "Marta K"), GameCenterFriend(id: "2", displayName: "Teo")],
        knownCarrierCount: 2,
        senderName: "Anton"
    )
    .padding()
}

#Preview("No ram yet") {
    AirDropSuggestionsCard(
        ram: nil,
        matchedCarriers: [],
        tripSuggestions: CalendarTripSuggestionService.preview.suggestions,
        onAddTripAsCarrier: { _ in },
        companionName: "Klaus",
        addedSuggestionIDs: []
    )
    .padding()
}
