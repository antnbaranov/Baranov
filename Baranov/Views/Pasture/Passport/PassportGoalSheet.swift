//
//  PassportGoalSheet.swift
//  Baranov
//
//  "What has to happen?" — the sheet where the person writes a milestone in
//  their own words, or borrows one of the suggestions and edits it. A
//  distance is optional; without one, the person ticks the milestone off
//  themselves when it happens. The finished milestone becomes a card, and
//  the reel is built around it.
//

import SwiftUI

struct PassportGoalSheet: View {
    let ramName: String
    var weather: StampWeather?
    let onAdd: (_ title: String, _ kilometers: Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var usesDistance = false
    @State private var kilometers = 5
    @State private var suggestions: [RamGoalSuggestion] = []
    @State private var tapTick = 0
    @FocusState private var isFocused: Bool

    private var canAdd: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What has to happen?")
                            .font(.headline)
                        TextField("Something \(ramName) should pull off…", text: $title, axis: .vertical)
                            .font(.title3)
                            .lineLimit(3...6)
                            .focused($isFocused)
                            .padding(16)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .onChange(of: title) { _, newValue in
                                if newValue.count > 90 { title = String(newValue.prefix(90)) }
                            }
                        Text("Write it in your own words. When it happens, tap “It happened!” on the card, and the reel tells the story.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Stuck? Roll the dice.")
                                .font(.headline)
                            Spacer()
                            Button {
                                withAnimation(.snappy) {
                                    suggestions = RamGoalSuggestion.ordered(for: weather)
                                }
                            } label: {
                                Label("Shuffle", systemImage: "dice.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(suggestions) { suggestion in
                                    Button {
                                        tapTick += 1
                                        title = suggestion.title
                                        if let km = suggestion.kilometers {
                                            usesDistance = true
                                            kilometers = km
                                        } else {
                                            usesDistance = false
                                        }
                                    } label: {
                                        HStack(alignment: .top, spacing: 10) {
                                            Text(suggestion.title)
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                                .multilineTextAlignment(.leading)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Image(systemName: "plus")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                        }
                                        .padding(14)
                                        .frame(width: 240, alignment: .topLeading)
                                        .frame(maxHeight: .infinity, alignment: .top)
                                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                        }
                        .padding(.horizontal, -20)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $usesDistance.animation(.snappy)) {
                            Text("Finish it with distance")
                                .font(.headline)
                        }
                        .tint(Color.accentColor)
                        if usesDistance {
                            Stepper(value: $kilometers, in: 1...200) {
                                Text("\(ramName) walks \(kilometers) km more")
                                    .font(.subheadline)
                            }
                            .tint(Color.accentColor)
                            Text("It completes itself when the steps add up.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .onAppear {
                if suggestions.isEmpty { suggestions = RamGoalSuggestion.ordered(for: weather) }
            }
            .navigationTitle("New milestone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if #available(iOS 26.0, *) {
                        Button(role: .close) { dismiss() }
                    } else {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Cancel")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onAdd(title, usesDistance ? kilometers : nil)
                    dismiss()
                } label: {
                    Text("Add milestone")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(.primary)
                .disabled(!canAdd)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .sensoryFeedback(.selection, trigger: tapTick)
        }
        .presentationDetents([.large])
    }
}
