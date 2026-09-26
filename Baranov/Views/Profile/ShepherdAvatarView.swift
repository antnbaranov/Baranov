import SwiftUI
import UIKit

/// Circular illustrated avatar with a postal-stamp double ring.
/// Renders a preset asset or a locally stored generated image.
struct ShepherdAvatarView: View {
    let selection: String
    let customFileName: String
    var size: CGFloat = 96
    var showsEditBadge = false
    /// `nil` keeps the round postal-stamp avatar; a value draws a plain
    /// rounded square with that continuous corner radius instead.
    var squareCornerRadius: CGFloat? = nil

    @State private var customImage: UIImage?

    var body: some View {
        if let radius = squareCornerRadius {
            squareBody(radius: radius)
        } else {
            roundBody
        }
    }

    private func squareBody(radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return portrait
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.secondary.opacity(0.25), lineWidth: 0.5))
            .overlay(alignment: .bottomTrailing) {
                if showsEditBadge {
                    Image(systemName: "pencil")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 26, height: 26)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                }
            }
            .task(id: customFileName) {
                customImage = ShepherdAvatarStore.image(named: customFileName)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Shepherd avatar")
    }

    private var roundBody: some View {
        portrait
            .frame(width: size, height: size)
            .clipShape(Circle())
            // Double ring: inner cream stamp edge, outer hairline.
            .overlay(Circle().strokeBorder(Color(red: 0.96, green: 0.92, blue: 0.82), lineWidth: 3))
            .padding(4)
            .background(Circle().fill(Color(red: 0.96, green: 0.92, blue: 0.82).opacity(0.35)))
            .overlay(Circle().strokeBorder(.secondary.opacity(0.35), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            .overlay(alignment: .bottomTrailing) {
                if showsEditBadge {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.secondary.opacity(0.25), lineWidth: 0.5))
                        .offset(x: 2, y: 2)
                }
            }
            .task(id: customFileName) {
                customImage = ShepherdAvatarStore.image(named: customFileName)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Shepherd avatar")
    }

    @ViewBuilder
    private var portrait: some View {
        if selection == ShepherdIdentityKeys.customSelection, let customImage {
            Image(uiImage: customImage).resizable().scaledToFill()
        } else if UIImage(named: selection) != nil {
            Image(selection).resizable().scaledToFill()
        } else {
            // Safe fallback if an asset is missing from the catalog.
            Image(systemName: "figure.walk")
                .font(.system(size: size * 0.45))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.thinMaterial)
        }
    }
}
