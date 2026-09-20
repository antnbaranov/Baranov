//
//  PlaceSearchField.swift
//  Baranov
//
//  A single search field with live, tap-to-select place suggestions —
//  the same look and interaction as the modern iOS Maps search bar: a
//  full pill-shaped field (a `Capsule`, not a lightly-rounded rectangle),
//  with exactly one clear button, and suggestions rendered as their own
//  separate rounded blocks underneath — not one long list with dividers.
//  Used everywhere this app needs a real city: picking a suggestion
//  resolves a real coordinate via MapKit, rather than a freeform-typed
//  name that might fail to geocode later or resolve to the wrong place
//  entirely.
//

import MapKit
import SwiftUI

struct PlaceSearchField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    let onSelect: (String, CLLocationCoordinate2D) -> Void

    /// Fires when the field's own clear button is tapped, in addition to
    /// clearing `text` — callers that treat this field as the single gate
    /// into a larger form (the destination field in `ComposeLetterView`)
    /// use this to collapse back to their initial state, exactly like
    /// clearing Apple Maps' search bar returns you to its default view.
    /// Fields that are just one part of an already-open form (starting
    /// city, handoff city) simply leave this `nil`.
    var onClear: (() -> Void)? = nil

    /// Fires whenever this field's own focus state changes. Callers that
    /// need to react the instant the field is *tapped* — before any text
    /// is typed or a place is picked — use this. `ComposeLetterView`'s
    /// destination field wires this to the same "expand the panel" call
    /// used on selection, because relying solely on the enclosing sheet's
    /// own `presentationDetents` selection to reflect the keyboard's
    /// automatic resize is not reliable: when a small-height sheet is too
    /// short for the keyboard, UIKit grows the sheet itself but does not
    /// always write that back through the `selection` binding, leaving
    /// `isPanelExpanded` stuck `false` while the sheet is visually already
    /// tall — an empty-looking sheet with just this one field in it.
    var onFocusChange: ((Bool) -> Void)? = nil

    @State private var completer = PlaceSearchCompleter()
    @State private var dictationService = DictationService()
    @State private var isResolving = false
    @FocusState private var isFocused: Bool

    /// Seeds live suggestions the moment this field is (re)focused with
    /// text already in it — otherwise a pre-filled field (re-opened via a
    /// "Change" button, say) shows zero suggestions until the person
    /// edits at least one character, since `.onChange(of: text)` never
    /// fires for text that was already there before focus.
    private func seedSuggestionsIfNeeded() {
        guard !text.isEmpty, completer.results.isEmpty else { return }
        completer.queryFragment = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(placeholder, text: $text)
                    .focused($isFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onChange(of: text) { _, newValue in
                        completer.queryFragment = newValue
                    }
                    .onChange(of: isFocused) { _, focused in
                        if focused {
                            seedSuggestionsIfNeeded()
                        }
                        onFocusChange?(focused)
                    }

                if isResolving {
                    ProgressView()
                } else if dictationService.isRecording {
                    Button {
                        dictationService.toggleRecording(appendingTo: text)
                    } label: {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                } else if !text.isEmpty {
                    Button {
                        text = ""
                        completer.clearResults()
                        onClear?()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        dictationService.toggleRecording(appendingTo: text)
                    } label: {
                        Image(systemName: "mic")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dictate")
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(.thinMaterial, in: Capsule())

            if isFocused && !completer.results.isEmpty {
                // Capped and independently scrollable, so the list is
                // always reachable in full even when it's sitting outside
                // any enclosing ScrollView (the destination field, at the
                // top of the compose sheet) and the keyboard is covering
                // most of the remaining screen.
                ScrollView {
                    suggestionBlocks
                }
                // Apple Maps' own suggestion list fills most of the
                // remaining sheet space above the keyboard, not a small
                // fixed strip — 280pt was cutting it off after only 3-4
                // results.
                .frame(maxHeight: 420)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: completer.results.count)
        .onChange(of: dictationService.transcript) { _, newValue in
            guard !newValue.isEmpty else { return }
            text = newValue
        }
    }

    /// Each suggestion as its own separately-cornered card, stacked with
    /// a visible gap between them — the "blocks" look of the modern
    /// Maps/Spotlight suggestion list, rather than one long card sliced
    /// up by thin dividers.
    private var suggestionBlocks: some View {
        VStack(spacing: 8) {
            ForEach(Array(completer.results.enumerated()), id: \.offset) { _, result in
                Button {
                    select(result)
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(.secondary.opacity(0.15))
                                .frame(width: 30, height: 30)
                            Image(systemName: "mappin")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(result.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            if !result.subtitle.isEmpty {
                                Text(result.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .transition(.opacity)
    }

    private func select(_ result: MKLocalSearchCompletion) {
        text = result.title
        isFocused = false
        completer.clearResults()

        Task {
            isResolving = true
            defer { isResolving = false }
            do {
                let coordinate = try await completer.resolve(result)
                onSelect(result.title, coordinate)
            } catch {
                // Leave the typed text as-is. The caller still requires a
                // resolved coordinate before it can proceed, so a failed
                // resolution here simply means the field stays "unpicked"
                // rather than silently accepting an unresolved place name.
            }
        }
    }
}

#Preview {
    @Previewable @State var text = ""
    return PlaceSearchField(placeholder: "Where is this letter going?", text: $text) { title, coordinate in
        print("Selected \(title) at \(coordinate)")
    }
    .padding()
}
