//
//  LetterInbox.swift
//  Baranov
//
//  Letters other people addressed to this person's profile code, waiting in
//  the mailbag with nothing to type.
//
//  On the first refresh the phone creates a key pair (`AddressKeychain`) and
//  registers the public half under the profile address. After that, each
//  refresh asks the relay for the letters filed under the address, opens each
//  one's wrapped letter code with the private key (`LetterKeyWrap`), fetches
//  who it's from, and keeps the code in `SealKeyVault` — so when the ram
//  finally reaches the gate the seal already knows its key and there is no
//  second code to enter.
//
//  Offline-first and silent on failure: a refresh that can't reach the relay
//  leaves the list as it was and simply tries again on the next tick.
//

import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class LetterInbox {
    struct Item: Identifiable {
        /// The relay lookup id.
        let id: String
        let preview: RelayLetterPreview
        let receivedAt: Date
    }

    private(set) var items: [Item] = []

    @ObservationIgnored private var isRefreshing = false

    /// Registers the address if needed, then pulls whatever is waiting.
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

        var fresh: [Item] = []
        for envelope in envelopes {
            if let known = items.first(where: { $0.id == envelope.id }) {
                fresh.append(known)
                continue
            }
            guard let code = try? LetterKeyWrap.unwrap(envelope.wrappedKey, lookupID: envelope.id, with: privateKey),
                  let preview = try? await relay.preview(id: envelope.id) else { continue }
            if preview.payload.isEncrypted {
                SealKeyVault.store(code, for: preview.payload.id)
            }
            fresh.append(Item(id: envelope.id, preview: preview, receivedAt: Self.date(from: envelope.createdAt)))
        }
        items = fresh
    }

    /// Drops a letter from the list once its ram is on the way.
    func remove(id: String) {
        items.removeAll { $0.id == id }
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

    private static func date(from iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso) ?? Date()
    }
}
