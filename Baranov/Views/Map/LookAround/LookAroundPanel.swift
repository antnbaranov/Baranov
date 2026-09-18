//
//  LookAroundPanel.swift
//  Baranov
//
//  The one Look Around surface that morphs between Apple Maps' three
//  stages — floating preview card, split screen, full screen — and the
//  geometry that drives it.
//
//  Why a single morphing view instead of `matchedGeometryEffect` between
//  a card view and an expanded view: the imagery is a live
//  `MKLookAroundViewController` hosted by `LookAroundViewport`. Two
//  separate SwiftUI views with a matched geometry ID are still two
//  different view identities, so the controller would be torn down and
//  recreated mid-flight and the imagery would flash to black during the
//  spring. Keeping ONE view identity and animating its frame, position,
//  and corner radii gives the same interpolated "card grows into place"
//  motion with the imagery continuously live from the first frame to the
//  last — the same view the person tapped is the one that fills the top
//  of the screen.
//
//  Coordinate space: `LookAroundLayoutMetrics` describes everything in
//  the *host's* coordinate space — the root overlay in `JourneyView`,
//  a `GeometryReader` that RESPECTS the safe area, so its origin is the
//  top-left of the safe region (just under the status bar / Dynamic
//  Island) and any positive offset in it is tappable by construction.
//  The status-bar and home-indicator heights are measured by the host
//  (window frame vs. host frame), never read from `safeAreaInsets`,
//  because an overlay's reported insets are unreliable and a wrong zero
//  there is exactly how the close button once ended up under the notch.
//  The split and full-screen frames extend *past* the host's top by the
//  measured inset so the imagery still runs edge to edge, while the
//  chrome is padded back inside the safe region by that same value.
//

import SwiftUI

/// Everything needed to lay out the panel for a given `LookAroundLayout`.
struct LookAroundLayoutMetrics: Equatable {
    /// Size of the host: the safe region (below the status bar, above the
    /// home indicator).
    var safeSize: CGSize
    /// Measured height of the status bar / Dynamic Island strip above the
    /// host.
    var topInset: CGFloat
    /// Measured height of the home-indicator strip below the host.
    var bottomInset: CGFloat
    /// Y (host space) of the top edge of whatever sits under the map at
    /// the bottom — the docked panel. The preview card's bottom edge is
    /// pinned `previewBottomSpacing` above it.
    var dockTopY: CGFloat

    static let previewSize = CGSize(width: 140, height: 96)
    static let previewCornerRadius: CGFloat = 16
    static let previewInset: CGFloat = 12
    static let previewBottomSpacing: CGFloat = 12

    /// How much of the safe region the split-screen panel takes: about a
    /// third, so the map, the marker and its heading cone stay the
    /// primary surface underneath — the proportion Apple Maps uses for
    /// its own Look Around split.
    static let splitHeightFraction: CGFloat = 1.0 / 3.0
    static let splitBottomCornerRadius: CGFloat = 20

    /// The one spring every stage transition uses.
    static let transitionSpring: Animation = .spring(response: 0.45, dampingFraction: 0.82)

    /// Height of the split panel *below* the status bar.
    var splitHeight: CGFloat {
        (safeSize.height * Self.splitHeightFraction).rounded()
    }

    /// Extra top inset the map needs while split so its *visible* region
    /// (and therefore its camera center) begins below the panel. The
    /// map's safe area already starts under the status bar, so this is
    /// exactly the panel's height within the safe region.
    func mapTopInset(for layout: LookAroundLayout) -> CGFloat {
        layout == .split ? splitHeight : 0
    }

    func frame(for layout: LookAroundLayout) -> CGRect {
        switch layout {
        case .hidden, .preview:
            let size = Self.previewSize
            return CGRect(
                x: safeSize.width - size.width - Self.previewInset,
                y: dockTopY - Self.previewBottomSpacing - size.height,
                width: size.width,
                height: size.height
            )
        case .split:
            return CGRect(x: 0, y: -topInset, width: safeSize.width, height: topInset + splitHeight)
        case .fullscreen:
            return CGRect(
                x: 0,
                y: -topInset,
                width: safeSize.width,
                height: topInset + safeSize.height + bottomInset
            )
        }
    }

    func cornerRadii(for layout: LookAroundLayout) -> RectangleCornerRadii {
        switch layout {
        case .hidden, .preview:
            return RectangleCornerRadii(
                topLeading: Self.previewCornerRadius,
                bottomLeading: Self.previewCornerRadius,
                bottomTrailing: Self.previewCornerRadius,
                topTrailing: Self.previewCornerRadius
            )
        case .split:
            return RectangleCornerRadii(
                topLeading: 0,
                bottomLeading: Self.splitBottomCornerRadius,
                bottomTrailing: Self.splitBottomCornerRadius,
                topTrailing: 0
            )
        case .fullscreen:
            return RectangleCornerRadii(topLeading: 0, bottomLeading: 0, bottomTrailing: 0, topTrailing: 0)
        }
    }
}

struct LookAroundPanel: View {
    let session: LookAroundSession
    let metrics: LookAroundLayoutMetrics

    /// What the imagery is of — "Look Around" plus where (the ram's
    /// current spot, or the person's own).
    var title: String = "Look Around"
    var subtitle: String? = nil

    var onExpand: () -> Void
    var onCollapse: () -> Void
    var onToggleFullscreen: () -> Void

    private var layout: LookAroundLayout { session.layout }

    var body: some View {
        let frame = metrics.frame(for: layout)
        let radii = metrics.cornerRadii(for: layout)
        let clip = UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)

        ZStack {
            LookAroundViewport(
                scene: session.scene,
                isInteractive: layout.isExpanded,
                showsRoadLabels: layout.isExpanded,
                fieldOfViewDegrees: session.fieldOfViewDegrees,
                onRotate: { session.rotate(byDegrees: $0) },
                onFieldOfViewChange: { session.setFieldOfView($0) },
                onSystemFullScreen: { session.noteSystemFullScreen($0) }
            )

            if layout == .preview {
                previewTapTarget
            }

            if layout.isExpanded {
                expandedChrome
            }
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(clip)
        // A soft, neutral shadow lifts the card off the map — only while
        // it's a card; the edge-to-edge stages sit flush.
        .shadow(color: .black.opacity(layout == .preview ? 0.18 : 0), radius: 10, y: 4)
        .position(x: frame.midX, y: frame.midY)
        .animation(LookAroundLayoutMetrics.transitionSpring, value: layout)
        // The preview card rides the docked sheet's top edge; when the
        // sheet changes detent the card glides with it.
        .animation(.easeInOut(duration: 0.25), value: metrics)
        // A light tap when the surface actually changes stage (expand /
        // collapse), not for the preview card merely appearing.
        .sensoryFeedback(.impact(weight: .light), trigger: layout) { old, new in
            old.isExpanded != new.isExpanded
        }
    }

    // MARK: - Preview card

    /// A full-card tap target sitting above the (non-interactive) imagery.
    private var previewTapTarget: some View {
        Button(action: onExpand) {
            Color.clear
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Look Around")
        .accessibilityHint("Expands the street-level view")
    }

    // MARK: - Expanded chrome

    /// A header row — title, where, and the close button — and the
    /// full-screen toggle in the bottom-trailing corner. The panel's
    /// frame starts `topInset` above the host (under the status bar /
    /// Dynamic Island), so the header is padded back down by exactly
    /// that measured amount plus a little air: it always sits below the
    /// island, never under it.
    private var expandedChrome: some View {
        VStack(spacing: 0) {
            // Just the close button up top — the same corner Apple Maps'
            // own Look Around reserves for it alone. The title/subtitle
            // used to share this row and crowd right up against it (worse
            // once the subtitle carried a long recipient/city name); it
            // now lives in the bottom row instead, opposite the Full
            // Screen toggle, with nothing else contesting either corner.
            HStack {
                Spacer(minLength: 0)
                closeButton
            }
            .padding(.top, metrics.topInset + 8)

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 12) {
                if !title.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }

                Spacer(minLength: 12)

                circularBlurButton(
                    systemImage: layout == .fullscreen
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right",
                    label: layout == .fullscreen ? "Exit Full Screen" : "Full Screen",
                    action: onToggleFullscreen
                )
            }
            .padding(.bottom, layout == .fullscreen ? metrics.bottomInset + 12 : 12)
        }
        // A little more breathing room off the screen edges than the
        // close/full-screen glyphs alone needed — with the title capsule
        // now sharing the bottom row, 16pt read as too tight against it.
        .padding(.horizontal, 20)
    }

    /// The standard dismiss glyph — `xmark.circle.fill` — with the circle
    /// itself drawn in material so it reads over any imagery, inside a
    /// 44 pt tap target.
    private var closeButton: some View {
        Button(action: onCollapse) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 30, weight: .regular))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.primary, .ultraThinMaterial)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close Look Around")
    }

    /// The circular ultra-thin-material button Apple Maps uses over
    /// imagery: a 32 pt circle inside a 44 pt tap target (HIG minimum).
    private func circularBlurButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
