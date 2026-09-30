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
import UIKit

struct MailbagSwipeDeck: View {
    let rams: [Ram]
    let isOutgoing: (Ram) -> Bool
    let carrierName: String
    let onOpen: (Ram) -> Void
    let onOpenBag: (Ram) -> Void
    var onCancel: ((Ram) -> Void)? = nil

    /// Which ram is on top of the stack.
    @State private var topIndex = 0
    @State private var drag: CGSize = .zero
    @State private var flipTick = 0
    @State private var ramToCancel: Ram?

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
        .confirmationDialog("Cancel this journey?",
                            isPresented: Binding(get: { ramToCancel != nil },
                                                 set: { if !$0 { ramToCancel = nil } }),
                            titleVisibility: .visible) {
            Button("Cancel Journey", role: .destructive) {
                if let ram = ramToCancel { onCancel?(ram) }
                ramToCancel = nil
            }
            Button("Keep Walking", role: .cancel) { ramToCancel = nil }
        } message: {
            Text("\(ramToCancel?.name ?? "") will come home and the letter is withdrawn.")
        }
        .onChange(of: count) { _, newCount in
            if newCount > 0 { topIndex %= newCount } else { topIndex = 0 }
        }
    }

    private func canCancel(_ ram: Ram) -> Bool {
        isOutgoing(ram) && onCancel != nil
            && (ram.status == .grazing || ram.status == .walking || ram.status == .waitingForHandoff)
    }

    private func canBreakSeal(_ ram: Ram) -> Bool {
        !isOutgoing(ram) && ram.status == .arrivedAtGate
    }

    /// The sender hands the recipient the receiving code (or tracking
    /// link) themselves: a visible button, not just the long-press menu.
    @ViewBuilder
    private func senderShareButton(for ram: Ram) -> some View {
        if isOutgoing(ram), ram.status != .delivered, let message = ram.letterShareMessage {
            ShareLink(item: message) {
                if ram.letter?.relayTicket != nil {
                    Label("Share tracking link", systemImage: "square.and.arrow.up")
                } else {
                    Label("Share code", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(ShareCodeGlassButtonStyle(expands: true))
        }
    }

    @ViewBuilder
    private func card(for ram: Ram, depth: Int) -> some View {
        let content = VStack(alignment: .leading, spacing: 16) {
            MailbagRamRow(ram: ram, isOutgoing: isOutgoing(ram), isCard: true)
            if depth == 0 { senderShareButton(for: ram) }
            if depth == 0, canBreakSeal(ram) {
                Button {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    onOpen(ram)
                } label: {
                    Label("Break the Seal and Read", systemImage: "seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(.green)
            }
        }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .scaleEffect(1 - CGFloat(depth) * 0.06, anchor: .top)
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
                .contextMenu {
                    Button { onOpenBag(ram) } label: { Label("Ram's Bag", systemImage: "bag") }
                    if let message = ram.letterShareMessage {
                        ShareLink(item: message) { Label("Share Code", systemImage: "square.and.arrow.up") }
                    }
                    if canCancel(ram) {
                        Button(role: .destructive) { ramToCancel = ram } label: {
                            Label("Cancel Journey", systemImage: "xmark")
                        }
                    }
                }
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
