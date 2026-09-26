//
//  ScratchOffRevealView.swift
//  Baranov
//
//  Scratch-Off Secret (paid): a short second line, hidden behind a foil
//  layer the recipient physically scratches clear with a finger — a
//  reveal within the arrival reveal, shown under the letter's own body
//  once the seal is already broken.
//
//  Canvas-drawn foil, erased with `.blendMode(.destinationOut)` under a
//  `DragGesture` — the same reason `DoodleEditorView` draws with `Canvas`
//  instead of PencilKit (a `PKCanvasView` flashed black/white in dark
//  mode there); a scratch card is even less of a PencilKit use case.
//
//  Haptics use `sensoryFeedback`, like everywhere else in the app,
//  rather than a hand-rolled `CHHapticEngine` — a light tick per newly
//  uncovered patch of foil, then one confirming `.success` when the
//  whole thing gives way. `CHHapticEngine` would allow finer control
//  over the tick's sharpness, but brings its own lifecycle to manage
//  (start/stop, a reset handler for an interrupted audio session) for a
//  gain that wouldn't read as different on screen.
//

import SwiftUI

struct ScratchOffRevealView: View {
    let secretText: String

    /// Coarse erase-progress grid. Counting *cells* uncovered (not raw
    /// touch points) is what makes `revealThreshold` mean something
    /// stable regardless of finger speed or scratch pattern.
    private static let columns = 14
    private static let rows = 6
    private static let revealThreshold = 0.55

    @State private var erasedCells: Set<Int> = []
    @State private var isRevealed = false
    @State private var lastCellCount = 0

    private var erasedFraction: Double {
        Double(erasedCells.count) / Double(Self.columns * Self.rows)
    }

    var body: some View {
        ZStack {
            secretContent
            if !isRevealed {
                foilLayer
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.secondary.opacity(0.25), lineWidth: 1)
        )
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: erasedCells.count)
        .sensoryFeedback(.success, trigger: isRevealed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isRevealed ? Text(secretText) : Text("A scratch-off secret, still covered"))
        .accessibilityHint(isRevealed ? "" : "Double tap to reveal")
        .accessibilityAddTraits(isRevealed ? [] : .isButton)
        .accessibilityAction {
            guard !isRevealed else { return }
            withAnimation(.easeOut(duration: 0.4)) { isRevealed = true }
        }
    }

    private var secretContent: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text(secretText)
                .font(.system(.subheadline, design: .serif).italic())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var foilLayer: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .style(Color(uiColor: .systemGray2)))
                context.blendMode = .destinationOut
                let cellSize = CGSize(width: size.width / CGFloat(Self.columns), height: size.height / CGFloat(Self.rows))
                for index in erasedCells {
                    let col = index % Self.columns
                    let row = index / Self.columns
                    let rect = CGRect(
                        x: CGFloat(col) * cellSize.width - 4,
                        y: CGFloat(row) * cellSize.height - 4,
                        width: cellSize.width + 8,
                        height: cellSize.height + 8
                    )
                    context.fill(Path(ellipseIn: rect), with: .style(.white))
                }
            }
            .overlay {
                if erasedCells.isEmpty {
                    Label("Scratch to reveal", systemImage: "hand.draw")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in scratch(at: value.location, in: proxy.size) }
            )
        }
    }

    private func scratch(at point: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let col = Int(point.x / (size.width / CGFloat(Self.columns)))
        let row = Int(point.y / (size.height / CGFloat(Self.rows)))
        guard col >= 0, col < Self.columns, row >= 0, row < Self.rows else { return }
        erasedCells.insert(row * Self.columns + col)

        guard !isRevealed, erasedFraction >= Self.revealThreshold else { return }
        withAnimation(.easeOut(duration: 0.5)) { isRevealed = true }
    }
}

#Preview {
    ScratchOffRevealView(secretText: "P.S. — the ram's real name is a secret too.")
        .padding()
}
