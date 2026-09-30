//
//  LetterInbox.swift
//  Baranov
//
//  Letters other people sent to this person's Shepherd ID.
//
//  On the first refresh the phone creates a key pair (`AddressKeychain`) and
//  registers the public half under its profile address. After that, each
//  refresh asks the relay for letters filed under the address, opens each
//  one's wrapped ear tag with the private key (`LetterKeyWrap`), and hands it
//  to the incoming cards (`ExpectedLetterStore`). The sender's ram walks the
//  letter here; this phone just watches it come and receives it at the gate.
//  The ear tag goes into `SealKeyVault`, so the seal opens with nothing to
//  type.
//
//  Offline-first and silent on failure: a refresh that can't reach the relay
//  simply tries again on the next tick.
//

import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class LetterInbox {
    @ObservationIgnored private var isRefreshing = false

    /// Registers the address if needed, then adopts whatever is on its way.
    func refresh(using relay: LetterRelayService) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let codeStore = CourierCodeStore()
        guard let token = await ensureRegistered(relay: relay, codeStore: codeStore) else { return }
        let address = codeStore.address
        let privateKey = AddressKeychain.loadOrCreatePrivateKey()

        let envelopes: [InboxEnvelope]
        do {
            envelopes = try await relay.inbox(address: address, token: token)
        } catch RelayError.unauthorized {
            // The token doesn't belong to this address any more; start over next tick.
            AddressKeychain.reset()
            return
        } catch {
            return
        }

        // Letters from older builds (the recipient walked them home) are no
        // longer part of the post; only tracked letters are adopted.
        for envelope in envelopes where envelope.tracked == true {
            adoptTracked(envelope, privateKey: privateKey)
        }
    }

    /// Unwraps a tracked letter's ear tag and hands it to the incoming
    /// cards, which follow it at the relay from here on.
    private func adoptTracked(_ envelope: InboxEnvelope, privateKey: Curve25519.KeyAgreement.PrivateKey) {
        guard let rawID = envelope.letterId, let letterID = UUID(uuidString: rawID) else { return }
        let store = ExpectedLetterStore.shared
        if store.letters.contains(where: { $0.letterID == letterID && $0.code != nil }) { return }
        guard let code = try? LetterKeyWrap.unwrap(envelope.wrappedKey, lookupID: envelope.id, with: privateKey) else { return }
        store.add(ExpectedLetter(
            letterID: letterID,
            senderName: envelope.senderName,
            ramName: "",
            city: "",
            expectedBy: nil,
            code: code,
            originName: envelope.originName
        ))
        // The relay pushes this too when it can; this is the fallback.
        let sender = envelope.senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        NotificationManager.shared.announce(
            .dispatched, letterID: letterID,
            title: String(localized: "\(sender.isEmpty ? String(localized: "Someone", bundle: .appLanguage, locale: .appLanguage) : sender) sent a ram your way", bundle: .appLanguage, locale: .appLanguage),
            body: String(localized: "It's on the road. Follow it under Incoming.", bundle: .appLanguage, locale: .appLanguage)
        )
    }

    // MARK: - Registration

    /// The inbox token for this phone, registering the address on first use.
    /// If the relay says the address already belongs to another key pair
    /// (a restored backup, say), the profile gets a fresh address and tries
    /// once more.
    private func ensureRegistered(relay: LetterRelayService, codeStore: CourierCodeStore) async -> String? {
        if let token = AddressKeychain.inboxToken { return token }
        let publicKey = AddressKeychain.loadOrCreatePrivateKey().publicKey
        do {
            let token = try await relay.registerAddress(codeStore.address, publicKey: publicKey)
            AddressKeychain.inboxToken = token
            return token
        } catch RelayError.conflict {
            codeStore.regenerate()
            guard let token = try? await relay.registerAddress(codeStore.address, publicKey: publicKey) else { return nil }
            AddressKeychain.inboxToken = token
            return token
        } catch {
            return nil
        }
    }
}
