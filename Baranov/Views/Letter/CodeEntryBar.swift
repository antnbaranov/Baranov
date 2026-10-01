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
//  Results appear as one compact card just above the field. System
//  materials and semantic styles only.
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

    private var hasResult: Bool {
        if outcome != .none { return true }
        if case .idle = relayLookup { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 8) {
            resultCard
            field
        }
        .onChange(of: focusRequest) { isFocused = true }
        .onChange(of: isFocused) { _, focused in
            onFocusChange(focused)
            if focused { onNeedsRoom() }
        }
        .onChange(of: hasResult) { _, has in if has { onNeedsRoom() } }
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

    // MARK: - Result

    @ViewBuilder private var resultCard: some View {
        switch outcome {
        case .none:
            claimCard

        case .onTheWay(let ram):
            VStack(alignment: .leading, spacing: 6) {
                header(for: ram)
                ProgressView(value: ram.progress).tint(Color.accentColor)
                Text("\(DistanceFormatter.string(forMeters: ram.remainingSteps)) left — still walking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .card()

        case .atGate(let ram):
            VStack(alignment: .leading, spacing: 8) {
                header(for: ram)
                Button {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    onOpen(ram, normalized)
                    code = ""
                } label: {
                    Label("Break the Seal", systemImage: "seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ShareCodeGlassButtonStyle(tint: Color.wax, expands: true))
            }
            .card()
        }
    }

    @ViewBuilder private var claimCard: some View {
        switch relayLookup {
        case .idle:
            EmptyView()
        case .looking:
            ProgressView("Looking for your letter…")
                .font(.caption)
                .card()
        case .failed(let message):
            note(LocalizedStringKey(message), symbol: "exclamationmark.triangle")
        case .following(let senderName, let arrived):
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    arrived
                        ? String(localized: "\(senderName)'s letter has arrived", bundle: .appLanguage, locale: .appLanguage)
                        : String(localized: "A letter from \(senderName) is on the way", bundle: .appLanguage, locale: .appLanguage),
                    systemImage: arrived ? "envelope.fill" : "envelope.badge.clock"
                )
                .font(.subheadline.weight(.semibold))
                Text(arrived
                     ? "It's coming into your mailbag now. The seal opens with a long press."
                     : "It's under Incoming. It lands in your mailbag when the ram reaches the gate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .card()
        }
    }

    private func note(_ text: LocalizedStringKey, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }

    private func header(for ram: Ram) -> some View {
        HStack(spacing: 10) {
            RamPortraitView(name: ram.name, diameter: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(ram.letter.map { String(localized: "Letter from \($0.senderName)", bundle: .appLanguage, locale: .appLanguage) } ?? ram.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(ram.currentCity) → \(ram.targetCity)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
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

private extension View {
    func card() -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
