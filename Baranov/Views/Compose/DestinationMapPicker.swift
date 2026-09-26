//
//  DestinationMapPicker.swift
//  Baranov
//
//  "Choose on the Map": the alternative to typing a place name in the
//  compose sheet's destination field. A full-screen map with a pin fixed at
//  the centre — pan and zoom the map underneath it, and when it settles the
//  spot is reverse-geocoded into a readable name. Confirming hands back a
//  `DroppedDestination`, which Compose treats exactly like a search result.
//
//  Presented by `RootView` (the one-owner-per-modal rule — the docked panel
//  hides while it is up). System materials and semantic styles only.
//

import MapKit
import SwiftUI

struct DestinationMapPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationService.self) private var locationService

    let onConfirm: (DroppedDestination) -> Void

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var center: CLLocationCoordinate2D?
    @State private var isDragging = false
    @State private var placeName = ""
    @State private var isResolving = false
    @State private var resolveTask: Task<Void, Never>?
    @State private var confirmTick = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $camera) {
                    UserAnnotation()
                }
                .mapStyle(.standard(elevation: .realistic))
                .onMapCameraChange(frequency: .continuous) { context in
                    center = context.camera.centerCoordinate
                    isDragging = true
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    settle(at: context.camera.centerCoordinate)
                }

                DestinationPinReticle(isDragging: isDragging)
            }
            .overlay(alignment: .top) { namePill }
            .safeAreaInset(edge: .bottom) { confirmBar }
            .navigationTitle("Choose on the Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: isDragging) { _, dragging in dragging }
            .sensoryFeedback(.impact(weight: .medium), trigger: confirmTick)
            .task {
                // Start where the sender is, when that is already known.
                if let here = locationService.currentCoordinate {
                    camera = .camera(MapCamera(centerCoordinate: here, distance: 3000, heading: 0, pitch: 0))
                }
            }
            .onDisappear { resolveTask?.cancel() }
        }
    }

    // MARK: - Pieces

    private var namePill: some View {
        HStack(spacing: 6) {
            if isResolving {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "mappin.circle.fill").foregroundStyle(Color.accentColor)
            }
            Text(placeName.isEmpty ? String(localized: "Move the map to place the pin") : placeName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
        .animation(.default, value: placeName)
    }

    private var confirmBar: some View {
        Button {
            guard let center else { return }
            confirmTick += 1
            let pin = DroppedDestination(
                latitude: center.latitude,
                longitude: center.longitude,
                name: placeName.isEmpty ? String(localized: "Dropped Pin") : placeName
            )
            onConfirm(pin)
            dismiss()
        } label: {
            Label("Send Letter Here", systemImage: "mappin.and.ellipse")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(Color.accentColor)
        .disabled(center == nil || isDragging)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// The map came to rest: lower the pin and resolve a name. Works offline
    /// too — `DroppedDestination.resolve` falls back to "Dropped Pin".
    private func settle(at coordinate: CLLocationCoordinate2D) {
        center = coordinate
        isDragging = false
        resolveTask?.cancel()
        isResolving = true
        resolveTask = Task {
            let resolved = await DroppedDestination.resolve(coordinate)
            guard !Task.isCancelled else { return }
            placeName = resolved.name
            isResolving = false
        }
    }
}

/// A pin held at the map's centre; it lifts while the map moves and drops
/// (with a small spring) when it settles.
private struct DestinationPinReticle: View {
    let isDragging: Bool

    var body: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(isDragging ? 0.12 : 0.28))
                .frame(width: isDragging ? 10 : 14, height: isDragging ? 4 : 5)

            // The balloon the system's `Marker` draws: a tinted disc with a
            // white glyph and a short stem, not a bare red symbol.
            VStack(spacing: -3) {
                Image(systemName: "mappin")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.accentColor))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.accentColor)
            }
            .scaleEffect(isDragging ? 1.12 : 1, anchor: .bottom)
            .offset(y: isDragging ? -34 : -22)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isDragging)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
