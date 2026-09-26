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
//  code, shows who the letter is from, and lets the recipient choose where
//  the ram arrives (`ClaimRelayLetterView`, in a sheet). The same code is then
//  kept on the phone, so the seal opens with no second entry.
//
//  Letters other people addressed to this person's profile code show up above
//  the field on their own (`LetterInbox`); those need no typing at all.
//
//  Results appear as one compact card just above the field. System
//  materials and semantic styles only.
//

import SwiftUI

struct CodeEntryBar: View {
    @Environment(FlockViewModel.self) private var flockViewModel
    @Environment(LocationService.self) private var locationService
    @Environment(LetterInbox.self) private var inbox

    /// The letter relay, when a receiver is configured. `nil` disables lookups.
    var relay: LetterRelayService?
    @Binding var code: String
    /// Bumped by the owner to put the cursor in the field.
    var focusRequest: Int = 0
    var onOpen: (Ram, String) -> Void
    /// The bar wants more room: it was focused, or a result appeared.
    var onNeedsRoom: () -> Void = {}

    @State private var relayLookup: RelayLookup = .idle
    @State private var claimTarget: ClaimTarget?
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
        case found(RelayLetterPreview)
        case failed(String)
    }

    /// A letter about to have its arrival spot chosen.
    private struct ClaimTarget: Identifiable {
        /// The relay lookup id.
        let id: String
        /// What the person typed, kept so it opens the seal later. `nil` for a
        /// mailbag letter, whose code the phone already holds.
        let code: String?
        let preview: RelayLetterPreview
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

    private var showsInbox: Bool { normalized.isEmpty && !inbox.items.isEmpty }

    private var hasResult: Bool {
        if outcome != .none || showsInbox { return true }
        if case .idle = relayLookup { return false }
        return true
    }

    var body: some View {
        VStack(spacing: 8) {
            resultCard
            field
        }
        .onChange(of: focusRequest) { isFocused = true }
        .onChange(of: isFocused) { _, focused in if focused { onNeedsRoom() } }
        .onChange(of: hasResult) { _, has in if has { onNeedsRoom() } }
        .task(id: normalized) { await lookUpLetterCode() }
        .sensoryFeedback(.error, trigger: failTick)
        .sheet(item: $claimTarget) { target in
            if let relay {
                NavigationStack {
                    ClaimRelayLetterView(relayID: target.id, code: target.code, preview: target.preview, relay: relay) {
                        inbox.remove(id: target.id)
                        claimTarget = nil
                        code = ""
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            if #available(iOS 26.0, *) {
                                Button(role: .close) { claimTarget = nil }
                            } else {
                                Button { claimTarget = nil } label: { Image(systemName: "xmark") }
                                    .accessibilityLabel("Close")
                            }
                        }
                    }
                }
                .environment(flockViewModel)
                .environment(locationService)
            }
        }
    }

    // MARK: - Field

    private var field: some View {
        TextField("An ear tag from a friend?", text: $code)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .focused($isFocused)
            .submitLabel(.done)
            .onChange(of: code) { _, new in
                let formatted = LetterCode.format(new)
                if formatted != new { code = formatted }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(.thinMaterial, in: Capsule())
    }

    // MARK: - Result

    @ViewBuilder private var resultCard: some View {
        switch outcome {
        case .none:
            if showsInbox {
                inboxCards
            } else {
                claimCard
            }

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
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(Color.wax)
            }
            .card()
        }
    }

    /// Letters addressed to this person's profile code: no typing needed.
    private var inboxCards: some View {
        VStack(spacing: 8) {
            ForEach(inbox.items.prefix(3)) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Label("Letter from \(item.preview.senderName) (\(item.preview.originName))", systemImage: "envelope.fill")
                        .font(.subheadline.weight(.semibold))
                    Button {
                        claimTarget = ClaimTarget(id: item.id, code: nil, preview: item.preview)
                    } label: {
                        Label("Choose Where It Arrives", systemImage: "mappin.and.ellipse")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Color.wax)
                }
                .card()
            }
            if inbox.items.count > 3 {
                Text("\(inbox.items.count - 3) more waiting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
        case .found(let preview):
            VStack(alignment: .leading, spacing: 8) {
                Label("Letter from \(preview.senderName) (\(preview.originName))", systemImage: "envelope.fill")
                    .font(.subheadline.weight(.semibold))
                Button {
                    claimTarget = ClaimTarget(id: LetterCode.lookupID(for: normalized), code: normalized, preview: preview)
                } label: {
                    Label("Choose Where It Arrives", systemImage: "mappin.and.ellipse")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(Color.wax)
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
                Text(ram.letter.map { "Letter from \($0.senderName)" } ?? ram.name)
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
            relayLookup = .failed(String(localized: "Ear tags aren't available right now."))
            return
        }
        relayLookup = .looking
        do {
            let preview = try await relay.preview(id: LetterCode.lookupID(for: normalized))
            guard !Task.isCancelled else { return }
            relayLookup = .found(preview)
        } catch {
            guard !Task.isCancelled else { return }
            relayLookup = .failed((error as? LocalizedError)?.errorDescription ?? String(localized: "Something went wrong."))
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
