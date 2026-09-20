//
//  RamSwipeDeck.swift
//  Baranov
//
//  How the satchel *shows* many letters: a stack of the real ram cards,
//  one on top, Tinder-style. Drag the top card away in either direction
//  and the next one is revealed; the one you swiped goes to the back.
//  Nothing is chosen or changed by swiping — it only pages through.
//  Buttons under the stack do the same, plus "previous" (VoiceOver,
//  one hand). System materials only.
//

import SwiftUI

struct RamSwipeDeck<Card: View>: View {
    let rams: [Ram]
    @Binding var topId: UUID?
    @ViewBuilder var card: (Ram) -> Card

    @State private var drag: CGSize = .zero
    @State private var pastThreshold = false
    @State private var flipTick = 0

    private let threshold: CGFloat = 110

    /// `rams` rotated so `topId` comes first.
    private var ordered: [Ram] {
        guard let topId, let index = rams.firstIndex(where: { $0.id == topId }) else { return rams }
        return Array(rams[index...] + rams[..<index])
    }

    var body: some View {
        let stack = ordered
        VStack(spacing: 12) {
            if let top = stack.first {
                ZStack {
                    card(top)
                        .id(top.id)
                        .offset(x: drag.width, y: drag.height * 0.2)
                        .rotationEffect(.degrees(Double(drag.width / 25)), anchor: .bottom)
                        .simultaneousGesture(dragGesture)
                        .transition(.identity)
                }
                .padding(.bottom, stack.count > 1 ? 22 : 0)
                .background(alignment: .top) { peekingCards(count: min(stack.count - 1, 2)) }

                if stack.count > 1 {
                    HStack(spacing: 24) {
                        roundButton("arrow.uturn.backward", "Previous letter") { step(forward: false) }
                        Text("\(index(of: top) + 1) / \(rams.count)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                        roundButton("arrow.right", "Next letter") { step(forward: true) }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: pastThreshold)
        .sensoryFeedback(.impact(weight: .light), trigger: flipTick)
    }

    private func index(of ram: Ram) -> Int { rams.firstIndex { $0.id == ram.id } ?? 0 }

    /// The edges of the cards waiting underneath.
    private func peekingCards(count: Int) -> some View {
        ZStack(alignment: .top) {
            ForEach((0..<count).reversed(), id: \.self) { i in
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.thinMaterial)
                    .padding(.horizontal, CGFloat(i + 1) * 12)
                    .padding(.bottom, CGFloat(i + 1) * 0)
                    .offset(y: CGFloat(i + 1) * 9)
            }
        }
        .allowsHitTesting(false)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                drag = value.translation
                let now = abs(value.translation.width) > threshold
                if now != pastThreshold { pastThreshold = now }
            }
            .onEnded { value in
                pastThreshold = false
                if abs(value.translation.width) > threshold {
                    fling(toRight: value.translation.width > 0)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { drag = .zero }
                }
            }
    }

    /// Throw the top card off-screen, then reveal the next.
    private func fling(toRight: Bool) {
        flipTick += 1
        withAnimation(.easeOut(duration: 0.22)) {
            drag = CGSize(width: toRight ? 600 : -600, height: 0)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            advance(forward: true)
            drag = .zero
        }
    }

    private func step(forward: Bool) {
        flipTick += 1
        advance(forward: forward)
    }

    private func advance(forward: Bool) {
        let stack = ordered
        guard stack.count > 1 else { return }
        let next = forward ? stack[1] : stack[stack.count - 1]
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { topId = next.id }
    }

    private func roundButton(_ symbol: String, _ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
