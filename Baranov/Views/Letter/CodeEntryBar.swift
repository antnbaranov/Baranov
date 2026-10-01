//
//  CodeEntryBar.swift
//  Baranov
//
//  The one place a code is typed: a small field along the bottom of the
//  docked panel, on both of its pages. There is no separate Enter Code
//  screen any more, and there is only one kind of code to enter.
//
//  A LETTER CODE (12 characters) does everything. If the letter is already
//  on this phone — it arrived by AirDrop or a nearby handoff — the code is
//  tried against every sealed letter here, and a match at the gate offers the
//  wax-seal ritual. Otherwise the phone derives the relay lookup id from the
//  code and follows the letter: it becomes an incoming card, the sender's
//  ram walks it to this person's gate, and it lands in the mailbag there.
//  The same code is kept on the phone, so the seal opens with no second entry.
//
//  Letters sent to this person's Shepherd ID become incoming cards on their
//  own (`LetterInbox`); those need no typing at all.
//
//  There is no floating result card: a followed letter appears as the top
//  card under Incoming (`ExpectedLetterStore` inserts it at index 0), and a
//  letter already at the gate opens the wax-seal ritual straight away. Only
//  a one-line status sits inside the bar. System materials and semantic
//  styles only.
//

import SwiftUI

struct CodeEntryBar: View {
    @Environment(FlockViewModel.self) private var flockViewModel
    @Environment(LocationService.self) private var locationService

    /// The letter relay, when a receiver is configured. `nil` disables lookups.
    var relay: LetterRelayService?
    @Binding var code: String
    /// Bumped by the owner to put the cursor in the field.
    var focusRequest: Int = 0
    var onOpen: (Ram, String) -> Void
    /// The bar wants more room: it was focused, or a result appeared.
    var onNeedsRoom: () -> Void = {}
    /// The field gained or lost the cursor.
    var onFocusChange: (Bool) -> Void = { _ in }

    @State private var relayLookup: RelayLookup = .idle
    @State private var failTick = 0
    @FocusState private var isFocused: Bool

    private enum Outcome: Equatable {
        case none
        case onTheWay(Ram)
        case atGate(Ram)
    }

    private enum RelayLookup {
        case idle
        case looking
        /// A tracked letter: now an incoming card under Incoming.
        case following(senderName: String, arrived: Bool)
        case failed(String)
    }

    private var normalized: String { LetterCode.normalize(code) }

    /// A letter already on this phone that this code opens.
    private var outcome: Outcome {
        guard LetterCode.isUsableKey(normalized) else { return .none }
        for ram in flockViewModel.activeRams where ram.status != .delivered {
            guard let letter = ram.letter, letter.isEncrypted else { continue }
            if (try? LetterCipher.open(letter.sealedBody, receivingCode: normalized, letterID: letter.id)) != nil {
                return ram.status == .arrivedAtGate ? .atGate(ram) : .onTheWay(ram)
            }
        }
        return .none
    }

    /// One quiet line inside the bar; never a separate card.
    private var statusLine: (text: String, symbol: String)? {
        if case .onTheWay(let ram) = outcome {
            return (String(localized: "\(DistanceFormatter.string(forMeters: ram.remainingSteps)) left — still walking.", bundle: .appLanguage, locale: .appLanguage), "figure.walk")
        }
        switch relayLookup {
        case .idle, .looking:
            return nil
        case .failed(let message):
            return (message, "exclamationmark.triangle")
        case .following(let senderName, let arrived):
            return (arrived
                    ? String(localized: "\(senderName)'s letter has arrived", bundle: .appLanguage, locale: .appLanguage)
                    : String(localized: "A letter from \(senderName) is on the way", bundle: .appLanguage, locale: .appLanguage),
                    arrived ? "envelope.fill" : "envelope.badge.clock")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let statusLine {
                Label { Text(LocalizedStringKey(statusLine.text)) } icon: { Image(systemName: statusLine.symbol) }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            field
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onChange(of: focusRequest) { isFocused = true }
        .onChange(of: isFocused) { _, focused in
            onFocusChange(focused)
            if focused { onNeedsRoom() }
        }
        .onChange(of: statusLine?.text) { _, text in if text != nil { onNeedsRoom() } }
        .onChange(of: outcome) { _, new in
            // A letter already on this phone, at the gate: the code is the
            // key, so the ritual starts without a second button.
            if case .atGate(let ram) = new {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                onOpen(ram, normalized)
                code = ""
            }
        }
        .task(id: normalized) { await lookUpLetterCode() }
        .sensoryFeedback(.error, trigger: failTick)
    }

    // MARK: - Field

    /// The same native-style field as the Archive search: leading icon,
    /// the field, a clear button once something is typed.
    private var field: some View {
        NativeFieldRow(symbol: "key.fill") {
            TextField("An ear tag from a friend?", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.done)
                .onChange(of: code) { _, new in
                    let formatted = LetterCode.format(new)
                    if formatted != new { code = formatted }
                }
            if !code.isEmpty {
                Button { code = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
    }

    /// Looks the letter up at the relay once the whole code is typed — unless
    /// it is already on this phone, in which case the local card answers.
    private func lookUpLetterCode() async {
        guard LetterCode.isComplete(normalized), outcome == .none else {
            relayLookup = .idle
            return
        }
        guard let relay else {
            relayLookup = .failed(String(localized: "Ear tags aren't available right now.", bundle: .appLanguage, locale: .appLanguage))
            return
        }
        relayLookup = .looking
        let lookupID = LetterCode.lookupID(for: normalized)
        // Every letter is tracked: the sender's ram walks it here, so a
        // found ear tag becomes an incoming card.
        do {
            let tracking = try await relay.tracking(id: lookupID)
            guard let expected = ExpectedLetter(code: normalized, tracking: tracking) else { throw RelayError.rejected }
            guard !Task.isCancelled else { return }
            ExpectedLetterStore.shared.add(expected)
            relayLookup = .following(senderName: tracking.senderName, arrived: tracking.isDelivered)
        } catch {
            guard !Task.isCancelled else { return }
            relayLookup = .failed((error as? LocalizedError)?.errorDescription ?? String(localized: "Something went wrong.", bundle: .appLanguage, locale: .appLanguage))
            failTick += 1
        }
    }
}

/// An input row in the look of the system search field: a quiet fill, a
/// continuous 10 pt corner, a leading symbol. Shared by the ear tag field
/// and the Archive search so the two read as one control.
struct NativeFieldRow<Content: View>: View {
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            content
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 36)
        .background(Color(uiColor: .tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
