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
    static let instagram = URL(string: "https://instagram.com/pitchcoach.club")!
    static let tiktok = URL(string: "https://tiktok.com/@pitch.coach")!
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
# Privacy

Baranov is a slow post. It is built so that the people carrying your letter
cannot read it, and so that we can't either. No accounts, no ads, no
tracking across other apps.

**What stays on your phone.** Your name, rams, letters, drafts and passport,
and the letter codes for letters you wrote (in the Keychain). Steps come from
CoreMotion and HealthKit and move your rams. Contacts and Calendar are read
only on your phone, to suggest people and places when you address a letter.

**What leaves your phone.** A ram you hand off (AirDrop or a shake) goes
directly to the other phone. The letter inside is ciphertext only
(ChaCha20-Poly1305), and its code never travels with it. An open postcard is
plain text that anyone carrying it can read; Baranov asks you each time.

**The optional letter relay.** Sending through the relay stores the
ciphertext, a one-way lookup id (never the code), the sender and recipient
names as typed, the ram's name, the journey's starting point, and, when a
recipient claims it, the drop spot they chose. The sender is only told whether
it was claimed, never where. Ask us to remove a letter any time.

**Sharing your position (off by default).** If you turn on "Share my
location with senders", then while you carry someone else's ram your phone
posts a position rounded to about 1 km, your carrier name and the ram ids. It
is forgotten after 30 minutes, when you carry nothing, or when you turn it off.

**Purchases.** Handled by Apple and RevenueCat. RevenueCat receives an
anonymous app-user ID, purchase receipts, and a few attributes (your carrier
name as you typed it, letters delivered, steps walked, active rams).
RevenueCat's privacy policy: https://www.revenuecat.com/privacy

**Anonymous usage stats (on by default).** Counts such as steps walked (in
batches), letters sent and opened, and paywall views, tied to a random ID
created on your phone, never to your name, Apple ID, contacts or exact
location, and never including letter text. Turn it off any time in Settings;
queued stats are then deleted.

**Course telemetry.** This app is part of the BCIT ACIT3855 distributed
systems coursework. Builds pointed at the course receiver post anonymous hop
and flock-metric events (a per-install ID, a ram ID, step counts, timestamps,
the ram's rounded position). No names, no letter contents.

**Apple services.** Maps, routing, Look Around, weather, dictation and Game
Center are Apple services, covered by Apple's privacy policy.

**Logs you choose to send.** Sent only if you tap "Send logs to developer";
you review the email first.

**Your choices.** Revoke Location, Motion, Health, Contacts, Calendar,
Microphone or Speech any time in iOS Settings. Manage subscriptions in your
Apple ID. Delete the app to remove everything on your phone.

Baranov is not directed at children under 13.

Questions or removal requests: antnbaranov@icloud.com.

Full text: github.com/antnbaranov/Baranov (PRIVACY.md).

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
