//
//  RamColorPickerSheet.swift
//  Baranov
//
//  The color choice for a ram from the second pasture slot on. Shows the
//  ram walking in the highlighted color so the person sees what they are
//  getting; "Use <color>" commits it through `RamColorStore`, which
//  allows one change every 24 hours. While the wait is running the sheet
//  says when the color can be changed again.
//

import SwiftUI

struct RamColorPickerSheet: View {
    let ramName: String

    @Environment(\.dismiss) private var dismiss
    @State private var selection: RamColor
    @State private var confirmTrigger = 0

    init(ramName: String) {
        self.ramName = ramName
        _selection = State(initialValue: RamColorStore.shared.color(for: ramName))
    }

    private var currentColor: RamColor { RamColorStore.shared.color(for: ramName) }

    var body: some View {
        // The wait is read once per render; the sheet is short-lived.
        let nextChange = RamColorStore.shared.nextChangeDate(for: ramName)

        NavigationStack {
            VStack(spacing: 20) {
                RamSpriteLoopView(
                    frameNames: RamSpriteFrameSets.walkFrames(for: selection),
                    frameDuration: .milliseconds(70)
                )
                .frame(width: 168, height: 140)
                .padding(.top, 8)
                .accessibilityHidden(true)

                Text(ramName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 20) {
                    ForEach(RamColor.choices) { color in
                        swatch(for: color)
                    }
                }

                Group {
                    if let nextChange {
                        Text("You can change the color again \(Self.relativeText(for: nextChange)).")
                    } else {
                        Text("You can change a ram's color once every 24 hours.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

                Button {
                    if RamColorStore.shared.choose(selection, for: ramName) {
                        confirmTrigger += 1
                    }
                    dismiss()
                } label: {
                    Text("Use \(selection.displayName)")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
                .compactGlassButton()
                .disabled(nextChange != nil || selection == currentColor)
                .sensoryFeedback(.success, trigger: confirmTrigger)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .navigationTitle("Ram color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseToolbarButton { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// "in 5 hours", in the app's language.
    private static func relativeText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .appLanguage
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func swatch(for color: RamColor) -> some View {
        let isSelected = selection == color
        return Button {
            selection = color
        } label: {
            Circle()
                .fill(color.swatch)
                .frame(width: 40, height: 40)
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary.opacity(isSelected ? 0.9 : 0), lineWidth: 2)
                        .padding(-5)
                }
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityLabel(color.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        RamColorPickerSheet(ramName: "Juniper")
    }
}
