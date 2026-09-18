//
//  LetterArrivalView.swift
//  Baranov
//
//  The arrival ritual, now gated: reaching `.arrivedAtGate` only means a
//  ram from *some* pasture reached this letter's destination — it doesn't
//  by itself prove the person holding this device is the actual recipient
//  (a shared/handed-off device, a same-named city elsewhere, etc.). So
//  before the seal can even be touched, this view checks the two things
//  the recipient would know instinctively: is this addressed to *me*
//  (`letter.recipientName` vs. the stored carrier display name), and *am
//  I actually at the gate* (`ram.targetCity` vs. the device's resolved
//  current city)? Only once both match does the wax-seal long-press even
//  become interactive.
//
//  Breaking the seal is the payoff of the whole walk, so it's staged:
//  the recipient holds the wax and cracks spread across it with soft
//  haptic ticks; on release with the right code the seal shatters into
//  shards (`WaxSealBreakView`), the envelope's flap swings open
//  (`SealedEnvelopeView`), and the letter rises out. An open postcard
//  (`Letter.isEncrypted == false`) skips the code entirely — there is no
//  wax to break, the recipient just lifts it out of the envelope.
//

import SwiftUI
import UIKit

struct LetterArrivalView: View {
    let ram: Ram

    @Environment(\.dismiss) private var dismiss
    @Environment(FlockViewModel.self) private var flockViewModel

    @AppStorage("com.baranov.carrierDisplayName") private var storedDisplayName = ""
    @Environment(LocationService.self) private var locationService

    @State private var sealProgress: Double = 0
    @State private var isPressing = false
    @State private var isBreaking = false
    @State private var isEnvelopeOpen = false
    @State private var isRevealed = false
    @State private var sensoryTrigger = false
    @State private var crackTick = 0
    @State private var crackTask: Task<Void, Never>?

    /// The receiving code the recipient types in — the letter's actual
    /// decryption key (see `LetterCipher`). Pre-filled only if this very
    /// device already holds it (it wrote the letter, or opened it before).
    @State private var enteredCode = ""
    @State private var wrongCodeTick = 0
    @State private var wrongCodeMessage: String?
    @FocusState private var isCodeFieldFocused: Bool

    /// The flock's live copy of this ram — `ram` is the value handed in
    /// when the sheet opened, and breaking the seal mutates the flock,
    /// not that copy.
    private var liveRam: Ram {
        flockViewModel.activeRams.first { $0.id == ram.id } ?? ram
    }

    private var letter: Letter? { liveRam.letter }

    /// "The road, told": the passport stamps as two or three sentences,
    /// from the on-device model when the phone has one. Loads after the
    /// seal breaks; absent, the stamp list stands on its own.
    @State private var muse = LetterMuseService()
    @State private var roadNarration: String?

    private var hasCompleteCode: Bool {
        LetterCipher.normalize(enteredCode).count == 8
    }

    /// A postcard needs no code; a sealed letter needs the whole one.
    private var isEncrypted: Bool { letter?.isEncrypted ?? true }

    private var canBreak: Bool { !isEncrypted || hasCompleteCode }

    /// Whether the stored carrier name matches who this letter is for.
    /// Case/whitespace-insensitive — same normalization the AirDrop
    /// carrier-directory matching already uses elsewhere in the project.
    private var recipientNameMatches: Bool {
        guard let letter else { return false }
        return letter.recipientName.normalizedForMatching == storedDisplayName.normalizedForMatching
            && !storedDisplayName.trimmed.isEmpty
    }

    /// Whether the device's resolved current city matches this ram's
    /// final destination. `nil` while location hasn't resolved yet.
    private var cityMatches: Bool? {
        guard let currentCityName = locationService.currentCityName else { return nil }
        return currentCityName.normalizedForMatching == ram.targetCity.normalizedForMatching
    }

    private var isVerifiedRecipient: Bool {
        recipientNameMatches && cityMatches == true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if isRevealed {
                        if let letter {
                            revealedLetter(letter)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            ContentUnavailableView("Letter Missing", systemImage: "envelope.badge.exclamationmark")
                        }
                    } else if letter == nil {
                        ContentUnavailableView("Letter Missing", systemImage: "envelope.badge.exclamationmark")
                    } else if cityMatches == nil {
                        verifyingRecipient
                    } else if isVerifiedRecipient {
                        sealedEnvelope
                    } else {
                        notForYou
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(.regularMaterial)
            .navigationTitle(ram.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                locationService.resolveCurrentLocation()
                if enteredCode.isEmpty, let known = letter?.receivingCode {
                    enteredCode = known
                }
            }
        }
    }

    // MARK: - Verifying state

    private var verifyingRecipient: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Checking you're at the gate…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }

    // MARK: - Wrong recipient / wrong city state

    private var notForYou: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

            Text("Not Your Letter to Open")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                mismatchRow(
                    isMatch: recipientNameMatches,
                    label: recipientNameMatches
                        ? "Addressed to you"
                        : "Addressed to \(letter?.recipientName ?? "someone else")"
                )
                mismatchRow(
                    isMatch: cityMatches == true,
                    label: cityMatches == true
                        ? "You're at the right gate"
                        : "This gate is in \(ram.targetCity)"
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("The seal can only be broken by the recipient, standing at the destination city.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }

    private func mismatchRow(isMatch: Bool, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isMatch ? .green : .red)
            Text(label)
                .font(.subheadline)
        }
    }

    // MARK: - Sealed state

    private var sealedEnvelope: some View {
        VStack(spacing: 20) {
            if isEncrypted {
                codeEntry
            } else {
                postcardNote
            }

            Text(holdInstruction)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(canBreak ? .primary : .secondary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: canBreak)

            ZStack(alignment: .top) {
                SealedEnvelopeView(
                    wax: sealWax,
                    monogram: monogram,
                    addressee: letter?.recipientName ?? "",
                    isOpen: isEnvelopeOpen,
                    width: 260,
                    showsSeal: false
                )

                holdTarget
                    .offset(y: SealedEnvelopeView.sealCenterY(width: 260) - 42)
                    .opacity(isEnvelopeOpen ? 0 : 1)
            }
            .frame(height: 200)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: crackTick)
            .sensoryFeedback(.impact(weight: .heavy), trigger: sensoryTrigger)
            .sensoryFeedback(.error, trigger: wrongCodeTick)

            if let letter, letter.isEncrypted {
                Text("Seal № \(letter.sealFingerprint) · sealed by \(letter.senderName)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            if let wrongCodeMessage {
                Label(wrongCodeMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }
        }
        .onDisappear { crackTask?.cancel() }
    }

    private var holdInstruction: String {
        if !isEncrypted { return "Hold to lift the postcard out" }
        return hasCompleteCode ? "Hold the seal to break it" : "Enter your receiving code to unlock the seal"
    }

    private var monogram: String { (letter?.senderName ?? "").sealMonogram }

    /// What the recipient holds: the wax seal (cracking as they hold,
    /// shattering on success) or, for a postcard, the open-envelope
    /// glyph in the same spot.
    private var holdTarget: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: sealProgress)
                .stroke(sealWax.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 84, height: 84)
                .rotationEffect(.degrees(-90))
                .opacity(isBreaking ? 0 : 1)

            if isEncrypted {
                WaxSealBreakView(
                    wax: sealWax,
                    monogram: monogram,
                    diameter: 72,
                    crackProgress: sealProgress,
                    isShattering: isBreaking
                )
            } else {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 72, height: 72)
                    .overlay(Circle().strokeBorder(.secondary.opacity(0.3), lineWidth: 1))
                    .overlay {
                        Image(systemName: "envelope.open.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .opacity(isBreaking ? 0 : 1)
            }
        }
        .frame(width: 84, height: 84)
        .scaleEffect(isPressing ? 0.94 : 1)
        .opacity(canBreak ? 1 : 0.55)
        .animation(.easeOut(duration: 0.15), value: isPressing)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: 1.5, maximumDistance: 40) {
            breakSeal()
        } onPressingChanged: { pressing in
            guard canBreak, !isBreaking else { return }
            isPressing = pressing
            if pressing {
                withAnimation(.linear(duration: 1.5)) { sealProgress = 1 }
                startCrackTicks()
            } else {
                crackTask?.cancel()
                if sealProgress < 1 {
                    withAnimation(.easeOut(duration: 0.2)) { sealProgress = 0 }
                }
            }
        }
        .accessibilityLabel(isEncrypted ? "Wax seal" : "Postcard")
        .accessibilityHint(canBreak ? "Touch and hold to open the letter" : "Enter the receiving code first")
        .accessibilityAddTraits(.isButton)
    }

    /// Soft ticks as the cracks spread — one per crack.
    private func startCrackTicks() {
        crackTask?.cancel()
        crackTask = Task {
            for _ in 0..<5 {
                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled else { return }
                crackTick += 1
            }
        }
    }

    private var postcardNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "envelope.open")
                .foregroundStyle(.secondary)
            Text("This one travelled open, as a postcard — no seal, no code. Just lift it out.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// The whole point of the gate: the letter is ciphertext until this
    /// moment, and the ram never carried the key. A wrong code shakes,
    /// buzzes, and leaves the seal intact. Success runs the reveal in
    /// three beats — shatter, flap, letter — each waiting for the last.
    private func breakSeal() {
        crackTask?.cancel()
        guard canBreak else {
            isCodeFieldFocused = true
            return
        }
        do {
            try flockViewModel.openDeliveredLetter(ramId: ram.id, receivingCode: enteredCode)
            sensoryTrigger.toggle()
            withAnimation { wrongCodeMessage = nil }
            isPressing = false
            isBreaking = true
            Task {
                try? await Task.sleep(for: .milliseconds(isEncrypted ? 450 : 150))
                isEnvelopeOpen = true
                try? await Task.sleep(for: .milliseconds(650))
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    isRevealed = true
                }
            }
        } catch {
            wrongCodeTick += 1
            isPressing = false
            withAnimation(.easeOut(duration: 0.2)) {
                sealProgress = 0
                wrongCodeMessage = "That code doesn't fit this seal. Check the message from \(letter?.senderName ?? "the sender")."
            }
        }
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Receiving Code")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .foregroundStyle(.secondary)
                TextField("XXXX-XXXX", text: $enteredCode)
                    .font(.title3.weight(.semibold).monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .submitLabel(.done)
                    .focused($isCodeFieldFocused)
                    .onChange(of: enteredCode) { _, _ in
                        if wrongCodeMessage != nil {
                            withAnimation { wrongCodeMessage = nil }
                        }
                    }
                if hasCompleteCode {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .animation(.snappy, value: hasCompleteCode)

            Text("The ram carried only ciphertext. The sender shared this code with you separately — it's the key.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sealWax: SealColor { letter?.sealColor ?? .crimson }

    // MARK: - Revealed state

    private func revealedLetter(_ letter: Letter) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("From \(letter.senderName)")
                    .font(.headline)
                Text("To \(letter.recipientName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(letter.messageBody)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Journey Passport")
                    .font(.headline)

                if let roadNarration {
                    Text(roadNarration)
                        .font(.system(.subheadline, design: .serif).italic())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                    Divider()
                } else if muse.isThinking {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Reading the stamps…")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if liveRam.routeHistory.isEmpty {
                    Text("No waypoints were logged for this journey.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(liveRam.routeHistory) { node in
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(node.cityName)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(node.stepsContributed) steps · \(node.carrierName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .task {
                guard roadNarration == nil else { return }
                if let story = await muse.narrate(ram: liveRam, stamps: liveRam.stamps) {
                    withAnimation(.easeInOut(duration: 0.3)) { roadNarration = story }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Case/diacritic-insensitive, trimmed form used for comparing a
    /// stored display name or city string against another one — mirrors
    /// the normalization `KnownCarrierDirectory`'s exact-city matching
    /// already relies on elsewhere in the project.
    var normalizedForMatching: String {
        trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

#Preview {
    LetterArrivalView(ram: FlockViewModel.preview.activeRams[0])
        .environment(FlockViewModel.preview)
        .environment(LocationService())
}
