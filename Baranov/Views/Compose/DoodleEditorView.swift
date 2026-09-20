//
//  DoodleEditorView.swift
//  Baranov
//
//  Finger drawing on top of a still picture — a blank sheet, or the
//  drawing/photo already attached to the letter. Deliberately plain
//  SwiftUI `Canvas` + `DragGesture` rather than PencilKit: PKCanvasView
//  remaps ink colours and repaints its own background per trait
//  collection, which is what flashed black/white in dark mode. Here the
//  picture is an ordinary `Image` that never changes; the strokes live
//  in a transparent layer above it, stored in normalised (0…1)
//  coordinates so the exported result is identical at any size.
//  "Done" flattens both into one image at the picture's own pixel size.
//

import SwiftUI
import UIKit

enum DoodleInk: CaseIterable, Identifiable {
    case black, inkBlue, red

    var id: Self { self }

    /// Fixed sRGB values: ink is a physical colour, not a semantic one,
    /// so it must not shift with Light/Dark.
    var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .black: return (0.08, 0.08, 0.08)
        case .inkBlue: return (0.10, 0.22, 0.56)
        case .red: return (0.82, 0.16, 0.14)
        }
    }

    var color: Color { Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b) }
    var cgColor: CGColor { CGColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1) }

    var label: LocalizedStringKey {
        switch self {
        case .black: return "Black"
        case .inkBlue: return "Ink blue"
        case .red: return "Red"
        }
    }
}

struct DoodleStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]          // normalised to the picture's width (x) and height (y)
    var ink: DoodleInk
    var width: CGFloat = 0.008     // fraction of the picture's width

    func path(in size: CGSize) -> Path {
        let pts = points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        if pts.count == 1 {
            path.addLine(to: first) // a tap leaves a dot (round cap)
            return path
        }
        for index in 1..<pts.count {
            let mid = CGPoint(x: (pts[index - 1].x + pts[index].x) / 2, y: (pts[index - 1].y + pts[index].y) / 2)
            path.addQuadCurve(to: mid, control: pts[index - 1])
        }
        path.addLine(to: pts[pts.count - 1])
        return path
    }
}

struct DoodleEditorView: View {
    let image: UIImage
    /// The letter's paper colour — the screen around the sheet matches it
    /// rather than going system black in Dark.
    var backdrop: Color = Color(uiColor: .systemBackground)
    let onDone: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var strokes: [DoodleStroke] = []
    @State private var current: DoodleStroke?
    @State private var ink: DoodleInk = .inkBlue
    @State private var isErasing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(image.size, contentMode: .fit)
                    .overlay { drawingLayer }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxHeight: .infinity)
            }
            .padding(16)
            .background(backdrop.ignoresSafeArea())
            .navigationTitle("Draw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onCancel) { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .principal) { inkPicker }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { isErasing.toggle() } label: {
                        Image(systemName: "eraser").symbolVariant(isErasing ? .fill : .none)
                    }
                    .accessibilityLabel("Eraser")
                    Button {
                        if !strokes.isEmpty { strokes.removeLast() }
                    } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(strokes.isEmpty)
                    .accessibilityLabel("Undo")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(flattened()) }
                        .fontWeight(.semibold)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: Drawing layer

    private var drawingLayer: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                for stroke in strokes + (current.map { [$0] } ?? []) {
                    context.stroke(
                        stroke.path(in: size),
                        with: .color(stroke.ink.color),
                        style: StrokeStyle(lineWidth: stroke.width * size.width, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let size = proxy.size
                        guard size.width > 0, size.height > 0 else { return }
                        let point = CGPoint(
                            x: min(max(value.location.x / size.width, 0), 1),
                            y: min(max(value.location.y / size.height, 0), 1)
                        )
                        if isErasing {
                            erase(near: point, size: size)
                        } else if current == nil {
                            current = DoodleStroke(points: [point], ink: ink)
                        } else {
                            current?.points.append(point)
                        }
                    }
                    .onEnded { _ in
                        if let finished = current { strokes.append(finished) }
                        current = nil
                    }
            )
        }
    }

    /// Whole-stroke eraser: touching a stroke removes it.
    private func erase(near point: CGPoint, size: CGSize) {
        strokes.removeAll { stroke in
            stroke.points.contains { hypot(($0.x - point.x) * size.width, ($0.y - point.y) * size.height) < 22 }
        }
    }

    // MARK: Controls

    /// Three inks, in the navigation bar like Notes' markup — no bottom
    /// tool tray.
    private var inkPicker: some View {
        HStack(spacing: 6) {
            ForEach(DoodleInk.allCases) { swatch in
                Button {
                    ink = swatch
                    isErasing = false
                } label: {
                    Circle()
                        .fill(swatch.color)
                        .frame(width: 22, height: 22)
                        .overlay {
                            if !isErasing && ink == swatch {
                                Circle().strokeBorder(.primary, lineWidth: 2).padding(-4)
                            }
                        }
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.label)
                .accessibilityAddTraits(!isErasing && ink == swatch ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: ink)
        .sensoryFeedback(.selection, trigger: isErasing)
    }

    // MARK: Export

    /// Picture with the strokes flattened onto it, at the picture's own
    /// pixel size. Returns the original instance when nothing was drawn.
    private func flattened() -> UIImage {
        guard !strokes.isEmpty else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = image.size
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            image.draw(in: CGRect(origin: .zero, size: size))
            let cg = renderer.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for stroke in strokes {
                cg.setStrokeColor(stroke.ink.cgColor)
                cg.setLineWidth(stroke.width * size.width)
                cg.addPath(stroke.path(in: size).cgPath)
                cg.strokePath()
            }
        }
    }
}

extension UIImage {
    /// A blank cream sheet to draw on, at the letter attachment's size.
    static func blankPaper(size: CGSize = CGSize(width: 1200, height: 900)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: 0.98, green: 0.96, blue: 0.91, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// A copy at scale 1, longest side capped — keeps a picture small
    /// enough to ride inside a `.ram` package over AirDrop.
    func preparedForLetter(maxSide: CGFloat = 1600) -> UIImage {
        let longest = max(size.width, size.height)
        let factor = longest > maxSide ? maxSide / longest : 1
        let target = CGSize(width: (size.width * factor).rounded(), height: (size.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
