//
//  PanelPageControl.swift
//  Baranov
//
//  The dot pagination under Journey's docked panel — the same idiom as
//  the dots in `OnboardingView` (a `UIPageControl`, in spirit), so the
//  panel's two pages read as pages rather than as two unrelated sheets.
//  Each dot is its own 44 pt tap target so switching is a tap as well as
//  a swipe, and the whole thing is one adjustable accessibility element
//  ("Page 1 of 2, Delivery"), swiped up or down with VoiceOver.
//

import SwiftUI

struct PanelPageControl<Page: Hashable>: View {
    struct Item: Identifiable {
        let page: Page
        let title: String
        var id: Page { page }
    }

    let items: [Item]
    @Binding var selection: Page

    @State private var selectionTick = 0

    private var selectedIndex: Int {
        items.firstIndex { $0.page == selection } ?? 0
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let isSelected = item.page == selection
                Button {
                    guard !isSelected else { return }
                    withAnimation(.snappy) { selection = item.page }
                    selectionTick += 1
                } label: {
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: isSelected ? 22 : 8, height: 8)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
        }
        .animation(.snappy, value: selection)
        .sensoryFeedback(.selection, trigger: selectionTick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(selectedIndex + 1) of \(items.count), \(items[safe: selectedIndex]?.title ?? "")")
        .accessibilityAdjustableAction { direction in
            let next: Int
            switch direction {
            case .increment: next = min(items.count - 1, selectedIndex + 1)
            case .decrement: next = max(0, selectedIndex - 1)
            @unknown default: return
            }
            guard next != selectedIndex, let item = items[safe: next] else { return }
            withAnimation(.snappy) { selection = item.page }
            selectionTick += 1
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
