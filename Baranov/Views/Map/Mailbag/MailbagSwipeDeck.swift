//
//  MailbagSwipeDeck.swift
//  Baranov
//
//  The mailbag's letters as a small stack of cards you flip through with
//  a swipe, like a deck: drag the top card left or right and it goes to the
//  back of the stack. Tapping the top card opens its letter. Nothing is
//  dismissed or deleted — the deck only cycles.
//
//  System materials and semantic styles only.
//

import SwiftUI

struct MailbagSwipeDeck: View {
    let rams: [Ram]
    let isOutgoing: (Ram) -> Bool
    let onOpen: (Ram) -> Void

    /// Which ram is on top of the stack.
    @State private var topIndex = 0
    @State private var drag: CGSize = .zero
    @State private var flipTick = 0

    private let flingDistance: CGFloat = 90
    private let visibleDepth = 3

    private var count: Int { rams.count }

    private func ram(atDepth depth: Int) -> Ram? {
        guard count > 0 else { return nil }
        return rams[(topIndex + depth) % count]
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                ForEach(Array((0..<min(visibleDepth, count)).reversed()), id: \.self) { depth in
                    if let ram = ram(atDepth: depth) {
                        card(for: ram, depth: depth)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, CGFloat(min(visibleDepth, count) - 1) * 10)

            if count > 1 {
                Text("\((topIndex % max(count, 1)) + 1) of \(count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .sensoryFeedback(.selection, trigger: flipTick)
        .onChange(of: count) { _, newCount in
            if newCount > 0 { topIndex %= newCount } else { topIndex = 0 }
        }
    }

    @ViewBuilder
    private func card(for ram: Ram, depth: Int) -> some View {
        let content = MailbagRamRow(ram: ram, isOutgoing: isOutgoing(ram))
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .scaleEffect(1 - CGFloat(depth) * 0.05, anchor: .top)
            .offset(y: CGFloat(depth) * 10)

        if depth == 0 {
            content
                .offset(x: drag.width)
                .rotationEffect(.degrees(Double(drag.width) / 18), anchor: .bottom)
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { drag = $0.translation }
                        .onEnded { value in
                            guard count > 1, abs(value.translation.width) > flingDistance else {
                                withAnimation(.snappy) { drag = .zero }
                                return
                            }
                            let direction: CGFloat = value.translation.width > 0 ? 1 : -1
                            withAnimation(.easeIn(duration: 0.18)) {
                                drag = CGSize(width: direction * 420, height: 0)
                            } completion: {
                                topIndex = (topIndex + 1) % count
                                flipTick += 1
                                drag = .zero
                            }
                        }
                )
                .onTapGesture { onOpen(ram) }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the letter. Swipe to see the next.")
                .accessibilityAction(named: "Next Letter") {
                    guard count > 1 else { return }
                    withAnimation(.snappy) { topIndex = (topIndex + 1) % count }
                }
                .zIndex(1)
        } else {
            content.allowsHitTesting(false)
        }
    }
}
