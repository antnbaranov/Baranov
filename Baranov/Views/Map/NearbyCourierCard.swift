//
//  NearbyCourierCard.swift
//  Baranov
//
//  What happens when you tap a courier who is standing nearby — on the main
//  map or in Profile: see who they are, save them, or hand them a ram.
//
//  Deliberately an in-hierarchy card rather than a sheet, alert or
//  confirmation dialog. The map already owns an always-on docked sheet, and
//  a second modal presentation from the same view silently does nothing
//  (the same trap Look Around fell into), so this is plain view composition
//  that the host shows in an overlay. System materials and semantic styles
//  only.
//

import SwiftUI

struct NearbyCourierCard: View {
    let courier: NearbyCourier
    let isSaved: Bool
    let onToggleSave: () -> Void
    /// Starts a handoff with this courier. Works with or without a ram to give: with nothing to offer
    /// the phone simply receives.
    let onHandOver: (() -> Void)?
    /// Starts a letter with this courier's trip destination already filled in. `nil` when they
    /// haven't shared where they're headed.
    var onSendLetter: (() -> Void)? = nil
    let onClose: () -> Void

    @State private var saveTick = 0

    private var subtitle: LocalizedStringKey {
        courier.tripCity.isEmpty ? "Open to carry" : "Heading to \(courier.tripCity)"
    }

    private var canWriteLetter: Bool {
        onSendLetter != nil && courier.tripLatitude != nil && courier.tripLongitude != nil
            && !courier.tripCity.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                CourierAvatarView(image: nil, name: courier.name, diameter: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(courier.name).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            HStack(spacing: 10) {
                if let onHandOver {
                    Button(action: onHandOver) {
                        Label("Hand over", systemImage: "hand.wave")
                    }
                    .buttonStyle(ShareCodeGlassButtonStyle(tint: .accentColor, expands: true))
                }

                if canWriteLetter, let onSendLetter {
                    Button(action: onSendLetter) {
                        Label("Write", systemImage: "envelope")
                    }
                    .buttonStyle(ShareCodeGlassButtonStyle(expands: true))
                }

                Button {
                    saveTick += 1
                    onToggleSave()
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isSaved ? Color.accentColor : Color.primary)
                        .frame(width: 48, height: 48)
                        .liquidGlass(in: Circle(), fallbackMaterial: .regularMaterial)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSaved ? Text("Remove from saved couriers") : Text("Save courier"))
            }

            if onHandOver != nil {
                Text("Ask \(courier.name) to shake too.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 16)
        .sensoryFeedback(.selection, trigger: saveTick)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// A courier marker that is actually tappable, with a full-size hit target.
struct NearbyCourierMarker: View {
    let courier: NearbyCourier
    let diameter: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            CourierAvatarView(image: nil, name: courier.name, diameter: diameter)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(courier.name))
        .accessibilityHint(Text("Shows save and hand over options"))
    }
}
