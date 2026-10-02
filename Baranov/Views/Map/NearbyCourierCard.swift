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
    /// True from the tap on Hand over until the handover has really begun
    /// (or the person declined to allow nearby access). Driven by the host
    /// from real state, not a timer.
    var isConnecting: Bool = false

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

            // Hand over is the main action, so it gets the whole row and
            // can never wrap; Write and Save sit quietly underneath.
            if onHandOver != nil {
                Button { onHandOver?() } label: {
                    Group {
                        if isConnecting {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Connecting…")
                            }
                        } else {
                            Label("Hand over", systemImage: "arrow.left.arrow.right")
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.vertical, 4)
                }
                .buttonStyle(ShareCodeGlassButtonStyle(tint: .accentColor, expands: true))
                .disabled(isConnecting)
            }

            HStack(spacing: 10) {
                if canWriteLetter, let onSendLetter {
                    Button(action: onSendLetter) {
                        Label("Write", systemImage: "envelope")
                            .lineLimit(1)
                    }
                    .buttonStyle(ShareCodeGlassButtonStyle(expands: true))
                    .disabled(isConnecting)
                } else {
                    Spacer(minLength: 0)
                }

                Button {
                    saveTick += 1
                    onToggleSave()
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isSaved ? Color.accentColor : Color.primary)
                        .frame(width: 44, height: 44)
                        .liquidGlass(in: Circle(), fallbackMaterial: .regularMaterial)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSaved ? Text("Remove from saved couriers") : Text("Save courier"))
            }

            if onHandOver != nil {
                Text("Tap to hand over or shake phones together.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 16)
        .swipeToDismiss(isEnabled: !isConnecting, onDismiss: onClose)
        .sensoryFeedback(.selection, trigger: saveTick)
        .sensoryFeedback(.impact(weight: .light), trigger: isConnecting) { _, now in now }
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

/// Shown the first time someone tries to hand over to a person nearby: the same explanation Profile gives,
/// at the moment it matters. Turning it on lets iOS show its Local Network prompt right after; "Not now"
/// starts nothing.
struct NearbyDiscoveryPrompt: View {
    let onTurnOn: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "wave.3.forward")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Find shepherds nearby")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("See couriers close to you right here on the map, and hand a ram over without the internet. iOS will ask to let Baranov find devices on your local network.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Button(action: onNotNow) {
                    Text("Not now").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button(action: onTurnOn) {
                    Text("Turn On").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
        .swipeToDismiss(onDismiss: onNotNow)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// How many couriers are in Bluetooth range right now. Their pins on the map are only roughly placed (nearby
/// discovery knows who is close, not where), so this says it in words and opens the first one.
struct NearbyRangeBadge: View {
    let count: Int
    let onTap: () -> Void
    /// Swiped away; it stays away until a courier it hasn't counted yet comes into range.
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onTap) {
            Label {
                Text("^[\(count) courier](inflect: true) in range")
            } icon: {
                Image(systemName: "person.2.wave.2")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .swipeToDismiss(onDismiss: onDismiss)
        .accessibilityHint("Shows the closest courier")
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
