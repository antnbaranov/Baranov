//
//  RamMarkerView.swift
//  Baranov
//
//  Renders one ram as a directional, animated map marker: a small skeletal
//  rig (see RamSkeleton/RamAnimationClip/RamRigAnimator) drawn with Canvas
//  vector primitives, replacing a static SF Symbol pin with a living
//  character that still functions as an accurate direction indicator.
//
//  Everything here is native SwiftUI (Canvas, TimelineView, GraphicsContext,
//  SF Symbols) — no Rive/.riv asset, no Lottie, no third-party runtime,
//  per the project's HIG/no-third-party-UI-framework rule.
//
//  DIRECTIONAL LOCK — a design call, not a literal transcription:
//  the original brief asks for the rig to rotate to the *exact* bearing a
//  static marker would have used, even while deforming (rearing, etc.).
//  Implemented literally (`.literalFullRotation`), that means a full 360°
//  rotation of a side-view running silhouette — which renders the ram
//  upside-down for any bearing pointing generally "left" on screen (roughly
//  90°...270° from due east). That's correct for a top-down arrow glyph,
//  but broken for a side-view character. The default mode instead mirrors
//  the rig horizontally (never flips vertically) and applies only a small
//  cosmetic tilt, while a separate compass chevron next to it carries the
//  *exact* bearing — so no directional precision is lost, and the ram never
//  renders upside-down. `.literalFullRotation` is kept available for exact
//  spec compliance if that's ever preferred over readability.
//

import Foundation
import SwiftUI

public enum RamMarkerOrientationMode: Equatable, Sendable {
    case literalFullRotation
    case mirrorAndTiltWithChevron
}

public struct RamMarkerView: View {
    public var bearingDegrees: Double
    public var motionState: RamMotionState
    public var orientationMode: RamMarkerOrientationMode
    public var markerSize: CGFloat

    public init(
        bearingDegrees: Double,
        motionState: RamMotionState,
        orientationMode: RamMarkerOrientationMode = .mirrorAndTiltWithChevron,
        markerSize: CGFloat = 44
    ) {
        self.bearingDegrees = bearingDegrees
        self.motionState = motionState
        self.orientationMode = orientationMode
        self.markerSize = markerSize
    }

    @State private var stateEnteredAt = Date()
    @State private var blendFromPose: RamPose = .bind

    private static let legBones: Set<RamBoneID> = [
        .hindLeftUpper, .hindLeftLower, .hindRightUpper, .hindRightLower,
        .foreLeftUpper, .foreLeftLower, .foreRightUpper, .foreRightLower,
    ]

    public var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(stateEnteredAt)
            let targetPose = RamRigAnimator.pose(for: motionState, elapsedInState: elapsed)
            let blendAmount = min(elapsed / RamRigAnimator.stateTransitionDuration, 1)
            let pose = RamRigAnimator.blend(blendFromPose, targetPose, amount: blendAmount)

            ZStack {
                if orientationMode == .mirrorAndTiltWithChevron {
                    compassChevron
                }
                rig(pose: pose)
                    .modifier(DirectionalLock(bearingDegrees: bearingDegrees, mode: orientationMode))
            }
            .frame(width: markerSize, height: markerSize)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .onChange(of: motionState) { oldValue, newValue in
            guard oldValue.category != newValue.category else { return }
            let elapsedInOldState = Date().timeIntervalSince(stateEnteredAt)
            blendFromPose = RamRigAnimator.pose(for: oldValue, elapsedInState: elapsedInOldState)
            stateEnteredAt = Date()
        }
    }

    // MARK: - Rig drawing

    private func rig(pose: RamPose) -> some View {
        let scale = markerSize / 90
        let root = CGPoint(x: markerSize / 2, y: markerSize * 0.62)
        let segments = RamSkeleton.segments(for: pose, rootPosition: root, scale: scale)

        return Canvas { context, _ in
            for segment in segments {
                switch segment.id {
                case .envelope:
                    drawEnvelope(segment, in: &context)
                case .head:
                    drawHead(segment, in: &context)
                default:
                    drawBone(segment, in: &context)
                }
            }
        }
        .frame(width: markerSize, height: markerSize)
    }

    private func drawBone(_ segment: RamBoneSegment, in context: inout GraphicsContext) {
        guard segment.thickness > 0 else { return }
        let color = Self.legBones.contains(segment.id) ? RamMarkerPalette.fleeceShadowLeg : RamMarkerPalette.fleece
        var path = Path()
        path.move(to: segment.start)
        path.addLine(to: segment.end)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: segment.thickness, lineCap: .round))
    }

    private func drawHead(_ segment: RamBoneSegment, in context: inout GraphicsContext) {
        drawBone(segment, in: &context)

        let headCenter = segment.end
        let radius = segment.thickness * 0.85
        let headRect = CGRect(x: headCenter.x - radius, y: headCenter.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: headRect), with: .color(RamMarkerPalette.fleece))

        let baseAngle = Double(atan2(segment.end.y - segment.start.y, segment.end.x - segment.start.x))
        let hornLength = radius * 1.6
        for offsetDegrees in [150.0, -150.0] {
            let angle = baseAngle + offsetDegrees * .pi / 180
            let tip = CGPoint(
                x: headCenter.x + CGFloat(cos(angle)) * hornLength,
                y: headCenter.y + CGFloat(sin(angle)) * hornLength
            )
            var hornPath = Path()
            hornPath.move(to: headCenter)
            hornPath.addQuadCurve(
                to: tip,
                control: CGPoint(x: (headCenter.x + tip.x) / 2, y: headCenter.y - hornLength * 0.3)
            )
            context.stroke(
                hornPath,
                with: .color(RamMarkerPalette.horn),
                style: StrokeStyle(lineWidth: max(radius * 0.35, 1.5), lineCap: .round)
            )
        }
    }

    private func drawEnvelope(_ segment: RamBoneSegment, in context: inout GraphicsContext) {
        let mid = CGPoint(x: (segment.start.x + segment.end.x) / 2, y: (segment.start.y + segment.end.y) / 2)
        let angle = Double(atan2(segment.end.y - segment.start.y, segment.end.x - segment.start.x))
        let size = CGSize(width: max(segment.thickness * 2.6, 6), height: max(segment.thickness * 1.8, 4))

        context.drawLayer { layerContext in
            layerContext.translateBy(x: mid.x, y: mid.y)
            layerContext.rotate(by: .radians(angle))
            let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
            layerContext.fill(Path(roundedRect: rect, cornerRadius: 1.2), with: .color(RamMarkerPalette.envelope))
            let sealRadius = size.height * 0.32
            let sealRect = CGRect(x: -sealRadius, y: -sealRadius, width: sealRadius * 2, height: sealRadius * 2)
            layerContext.fill(Path(ellipseIn: sealRect), with: .color(RamMarkerPalette.wax))
        }
    }

    // MARK: - Directional chevron (exact-bearing wayfinding accessory)

    private var compassChevron: some View {
        Image(systemName: "location.north.fill")
            .font(.system(size: markerSize * 0.26, weight: .semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(bearingDegrees))
            .offset(x: markerSize * 0.34, y: -markerSize * 0.34)
    }

    private var accessibilityDescription: String {
        let compass = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        let safeBearing = bearingDegrees.isFinite ? bearingDegrees : 0
        let index = Int((safeBearing.truncatingRemainder(dividingBy: 360) + 360.0).truncatingRemainder(dividingBy: 360) / 45.0 + 0.5) % 8
        let direction = compass[index]
        switch motionState {
        case .idle:
            return "Ram resting, facing \(direction)"
        case .moving:
            return "Ram traveling \(direction)"
        case .arrived:
            return "Ram arrived, rearing up"
        }
    }
}

/// Applies bearing-based rotation to the rig per `RamMarkerOrientationMode`.
/// Kept as its own `ViewModifier` so the two orientation strategies stay
/// easy to compare/swap without touching `RamMarkerView`'s drawing code.
private struct DirectionalLock: ViewModifier {
    let bearingDegrees: Double
    let mode: RamMarkerOrientationMode

    func body(content: Content) -> some View {
        // Both branches are expressed through the same scale + rotation pair
        // so the two orientation strategies share one modifier chain (an
        // opaque `some View` return can't vary its underlying type per
        // branch) — `.literalFullRotation` simply never mirrors.
        let (scaleX, rotationDegrees) = transform
        content
            .scaleEffect(x: scaleX, y: 1)
            .rotationEffect(.degrees(rotationDegrees))
    }

    private var transform: (scaleX: CGFloat, rotationDegrees: Double) {
        switch mode {
        case .literalFullRotation:
            return (1, bearingDegrees)

        case .mirrorAndTiltWithChevron:
            let normalized = normalizedBearing(bearingDegrees)
            let facingLeft = abs(normalized) > 90
            let rawTilt = facingLeft ? (normalized > 0 ? 180 - normalized : -180 - normalized) : normalized
            let clampedTilt = min(max(rawTilt, -25), 25)
            return (facingLeft ? -1 : 1, clampedTilt)
        }
    }

    /// Wraps any bearing to the -180...180 range.
    private func normalizedBearing(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }
}

#Preview("Ram marker states") {
    struct PreviewHarness: View {
        @State private var state: RamMotionState = .moving(speed: 0.7)
        @State private var bearing: Double = 40

        var body: some View {
            VStack(spacing: 24) {
                RamMarkerView(bearingDegrees: bearing, motionState: state, markerSize: 96)
                    .border(.secondary.opacity(0.2))

                Picker("State", selection: $state) {
                    Text("Idle").tag(RamMotionState.idle)
                    Text("Moving").tag(RamMotionState.moving(speed: 0.7))
                    Text("Arrived").tag(RamMotionState.arrived)
                }
                .pickerStyle(.segmented)

                Slider(value: $bearing, in: 0...360) {
                    Text("Bearing")
                }
                Text("Bearing: \(Int(bearing))°")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    return PreviewHarness()
}
