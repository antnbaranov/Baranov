//
//  PastureFooterView.swift
//  Baranov
//
//  The bottom of Pasture: rate, social links and the legal fine print.
//  The legal links are required by App Review 3.1.2 for the auto-renewing
//  products — they must exist and work, so they are plain fine print, not
//  a card. Privacy and Terms both open in-app (readable offline); Terms
//  ends with a link to Apple's standard license agreement.
//

import SafariServices
import SwiftUI

enum AppLinks {
    /// Baranov's App Store page. Until the app is live the page won't open,
    /// which is harmless: the link only ever travels as text or opens in
    /// the App Store app.
    static let appStore = URL(string: "https://apps.apple.com/us/app/baranov-slow-mail-penpal/id6813932060")!
    static let writeReview = URL(string: "https://apps.apple.com/us/app/baranov-slow-mail-penpal/id6813932060?action=write-review")!
    static let instagram = URL(string: "https://instagram.com/slowrampost")!
    static let tiktok = URL(string: "https://tiktok.com/@slowrampost")!
    /// Apple's standard license agreement, linked from the end of our own terms.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

struct IdentifiableURL: Identifiable {
    let url: URL
    var id: URL { url }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

enum LegalDocument: String, Identifiable {
    case privacy, terms
    var id: String { rawValue }
    var title: String {
        switch self {
        case .privacy: return String(localized: "Privacy", bundle: .appLanguage, locale: .appLanguage)
        case .terms: return String(localized: "Terms", bundle: .appLanguage, locale: .appLanguage)
        }
    }
}

struct LegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let document: LegalDocument

    var body: some View {
        switch document {
        case .terms:
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(Self.termsBlocks.enumerated()), id: \.offset) { _, block in
                            block.view
                        }
                        Button("Apple's standard license agreement") { openURL(AppLinks.terms) }
                            .font(.subheadline)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle(document.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
            .presentationDetents([.large])
        case .privacy:
            NavigationStack {
                ScrollView {
                    Text((try? AttributedString(markdown: Self.privacyText, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(Self.privacyText))
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle(document.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
            .presentationDetents([.large])
        }
    }

    /// One heading, paragraph or bullet of the terms.
    private enum TermsBlock {
        case heading(String)
        case paragraph(String)
        case bullet(String)

        @ViewBuilder var view: some View {
            switch self {
            case .heading(let text):
                Text(text).font(.headline).padding(.top, 4)
            case .paragraph(let text):
                Text(LegalDocumentView.inline(text)).font(.subheadline).foregroundStyle(.secondary)
            case .bullet(let text):
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(.tertiary)
                    Text(LegalDocumentView.inline(text)).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    /// Splits the terms text into headings, paragraphs and bullets so it
    /// reads like the rest of the app instead of raw markdown.
    private static let termsBlocks: [TermsBlock] = {
        var blocks: [TermsBlock] = []
        var paragraph: [String] = []
        var bullet: [String]?
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))); paragraph = [] }
            if let b = bullet { blocks.append(.bullet(b.joined(separator: " "))); bullet = nil }
        }
        for raw in termsText.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush() }
            else if line.hasPrefix("## ") { flush(); blocks.append(.heading(String(line.dropFirst(3)))) }
            else if line.hasPrefix("- ") { flush(); bullet = [String(line.dropFirst(2))] }
            else if bullet != nil { bullet?.append(line) }
            else { paragraph.append(line) }
        }
        flush()
        return blocks
    }()

    private static let termsText = """
Last updated September 29, 2026

These terms apply to Baranov, made by Anton Baranov. By using the app you
agree to them. If you don't agree, please don't use it.

## The app

Baranov is a slow-post app: letters are carried by virtual rams that move as
you walk, and are handed between phones. It is provided as is, and features
may change or be removed.

## Your letters

- You keep ownership of what you write. You are responsible for it.
- Letters are encrypted with a letter code. If that code is lost, nobody,
including us, can recover the letter. Sending the code to the recipient is
up to you.
- An open postcard is not encrypted, and anyone carrying it can read it.
- Don't use the app to send unlawful, harassing, threatening, hateful or
sexually explicit content, or to spam or impersonate others. The optional
relay may refuse or remove letters, and block abuse, at our discretion.
Because letters are encrypted, we generally cannot see their contents.

## Location and safety

The app uses your steps and, if you allow it, your location. Don't use it
while driving or in a way that distracts you from your surroundings. Journey
distances and city routes are approximate. Don't walk anywhere unsafe to
"move a ram".

## Subscriptions and purchases

"Expand the Pasture" is an optional auto-renewing subscription that unlocks
up to five rams at once and premium wax and paper. A one-time purchase,
"adopt a ram", is also available. Prices are shown in the app before you buy.

- Payment is charged to your Apple ID at confirmation of purchase.
- Subscriptions renew automatically unless cancelled at least 24 hours before
the end of the current period. Your account is charged for renewal within 24
hours before the period ends.
- Manage or cancel any time in your Apple ID account settings. Deleting the
app does not cancel a subscription.
- Refunds are handled by Apple under its own policies.
- The free ram is free and stays free.

## Availability and liability

The optional relay and telemetry servers are run on a best-effort basis and
may be slow, unavailable or reset without notice. To the extent the law
allows, the app is provided without warranties, and we are not liable for
lost letters, missed deliveries, or indirect damages. Nothing here limits
rights you have under the law where you live that cannot be excluded.

## Privacy

How data is handled is described in the Privacy policy, also in this app.

## Apple

Apple's standard license agreement also applies to the app. It is linked
below.

## Changes and contact

We may update these terms; the date above will change. Continued use after an
update means you accept it. Questions: antnbaranov@icloud.com.
"""

    private static let privacyText = """
# Privacy Policy

Last updated: September 30, 2026

Baranov (“The Slow Ram Post”) is designed around the principles of intentional communication and digital privacy. It is engineered so that neither the couriers carrying your letter nor we as the developers can read your private messages. There are no advertising identifiers, no third-party tracking across apps or websites, and no traditional user accounts.

Baranov is operated by Anton Baranov.

**1. What Stays on Your Device**

The vast majority of your data never leaves your device:

• **Your Profile & Keychain:** Your chosen display name, active rams, letters, drafts, travel log / journey passport, and cryptographic keys (stored securely in the iOS Keychain).
• **Health & Motion Data (HealthKit & CoreMotion):** Step counts and walking activity from your iPhone and Apple Watch are accessed solely on-device to advance your rams along their routes. This data is never uploaded to any remote server or shared with third parties.
• **Contacts & Calendar:** Accessed strictly on-device to suggest recipients and destination events when you address a letter. We never copy, store, or upload your address book.
• **Dictation & On-Device AI:** Voice dictation is processed via Apple’s native speech recognition framework. On-device text assistance is powered entirely locally by Apple Intelligence models on supported devices.

**2. What Is Transmitted and Stored**

When interacting with other users or using networked features, minimal data is transmitted under strict privacy safeguards:

• **Direct Ram Hand-Offs (AirDrop & Local Sharing):** When you pass a ram directly to another device, the message payload is protected with ChaCha20-Poly1305 end-to-end encryption. The decryption key never travels with the courier ram. Only the intended recipient can unlock it. (Exception: If you deliberately choose to send an Open Postcard, the card travels as unencrypted plain text, visible to anyone carrying it).
• **The Letter Relay:** When letters travel over the network, our relay server temporarily facilitates transit. The relay processes:
      – The encrypted ciphertext (or plain text for open postcards).
      – A one-way cryptographic lookup identifier derived from the letter code (never the code itself).
      – Sender and recipient display names as entered.
      – Ram name and approximate journey coordinates rounded to approximately 1 km (coarse location).
      – For Shepherd ID deliveries: the recipient’s public sealing key.
• **Letter Retention & Expiration:** Uncollected letters stored on the relay automatically expire and are permanently purged from the server after 60 days. Once a recipient collects a letter, it is removed from active server transit.
• **Shepherd ID & Gate:** Your Shepherd ID consists of a public key and a hashed inbox token. Your designated “Gate” (the approximate town or region where your letters arrive) is stored with coarse accuracy (~1 km). You can update your Gate or reset your Shepherd ID at any time in Profile Settings.
• **Letter Recalls:** If you recall a sent letter before delivery, a one-way hashed recall token is retained on the relay for up to 60 days to verify cancellation.
• **Carrier Location Sharing (Off by Default):** If you enable “Share location with senders,” your device periodically posts an approximate position rounded to ~1 km along with your courier name while actively carrying another user’s ram. This information is automatically discarded after 30 minutes of inactivity or immediately when toggled off.
• **Push Notifications:** If permitted, your device’s Apple Push Notification service (APNs) token is linked to your Shepherd ID to alert you of incoming rams, deliveries, and letter opens. You can revoke notification permissions at any time in iOS Settings.
• **Anonymous Product Metrics (Opt-Out):** To improve reliability, the app aggregates basic anonymous usage stats (e.g., batches of steps walked, letters sent/opened, paywall impressions). These events are keyed to a random, rotating installation ID, never linked to your identity, Apple ID, or contacts, and never include message content. You can disable anonymous telemetry at any time in Baranov’s Settings.
• **Diagnostic Logs:** Debug logs remain local to your device. They are transmitted only if you explicitly choose to export or send them for troubleshooting, and you can review the contents prior to sending.

**3. Third-Party Services and Apple Frameworks**

We partner exclusively with trusted infrastructure providers necessary for app functionality:

• **In-App Purchases (RevenueCat & Apple StoreKit):** Subscriptions and in-app purchases are processed securely by Apple. We use RevenueCat to validate receipts and manage subscription states. RevenueCat receives an anonymous app user identifier and transaction receipts. For details, refer to [RevenueCat’s Privacy Policy](https://www.revenuecat.com/privacy).
• **Apple Platform Services:** Routing, MapKit visuals, Look Around previews, weather context, and Game Center integrations are provided directly by Apple and governed by [Apple’s Privacy Policy](https://www.apple.com/legal/privacy/).

**4. Data Control and Deletion Rights**

You have complete control over your data:

• **Device Permissions:** You can grant or revoke access to Location, Health, Motion, Contacts, Calendar, Microphone, or Speech Recognition at any time via iOS Settings.
• **Data Deletion:** Deleting the Baranov app removes all local data, drafts, keys, and cached letters from your device.
• **Server Data Purge:** You can reset your Shepherd ID and flush active relay records directly within the app settings. To request manual removal of any orphaned relay entries or registered public keys, contact us at the email below.

**5. Children’s Privacy**

Baranov is not directed toward children under the age of 13. We do not knowingly collect or solicit personal information from children.

**6. Updates to This Policy**

We may update this Privacy Policy from time to time to reflect operational or legal updates. Material changes will be highlighted within the app or noted with a revised date at the top of this page.

**7. Contact Us**

If you have questions, feedback, or data requests regarding this Privacy Policy, please contact:

Anton Baranov

Email: antnbaranov@icloud.com

"""}

/// The bottom of Pasture as native list rows — the same row as the
/// Satchel row above (icon, title, chevron), no custom chips or corners.
struct PastureFooterView: View {
    @Environment(\.openURL) private var openURL
    // Owned by PastureView: a sheet attached inside a List row/section is torn
    // down whenever the list refreshes (steps, ram updates), which made the
    // policy close by itself.
    @Binding var socialURL: IdentifiableURL?
    @Binding var legalDocument: LegalDocument?

    var body: some View {
        Group {
            Section {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }

                // A direct App Store deep link always opens the review
                // screen; `requestReview()` is silently throttled by iOS.
                linkRow(Label("Rate on the App Store", systemImage: "star.bubble")) {
                    openURL(AppLinks.writeReview)
                }
                linkRow(Label("Instagram", systemImage: "camera")) { socialURL = IdentifiableURL(url: AppLinks.instagram) }
                linkRow(Label("TikTok", systemImage: "music.note")) { socialURL = IdentifiableURL(url: AppLinks.tiktok) }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Baranov — a slow post, carried on foot.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        legalLink(.privacy)
                        Text("·").foregroundStyle(.tertiary)
                        legalLink(.terms)
                    }
                    .font(.caption)

                    Text("For RevenueCat Shipaton 2026")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                    Text("Anton Baranov @antnbaranov")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
            }
        }
    }

    private func linkRow(_ label: Label<Text, Image>, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                label
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }

    private func legalLink(_ doc: LegalDocument) -> some View {
        Button { legalDocument = doc } label: { Text(doc.title).underline() }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
    }
}
