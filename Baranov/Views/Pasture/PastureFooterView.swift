//
//  PastureFooterView.swift
//  Baranov
//
//  The bottom of Pasture: rate, social links and the legal fine print.
//  The legal links are required by App Review 3.1.2 for the auto-renewing
//  products — they must exist and work, so they are plain fine print, not
//  a card. Privacy opens in-app (readable offline); Terms opens Apple's
//  standard EULA in an in-app Safari sheet.
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
        case .privacy: return String(localized: "Privacy")
        case .terms: return String(localized: "Terms")
        }
    }
}

struct LegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    let document: LegalDocument

    var body: some View {
        switch document {
        case .terms:
            SafariView(url: AppLinks.terms).ignoresSafeArea()
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

    private static let privacyText = """
# Privacy

Baranov is a slow post. It is built so that the people carrying your letter
cannot read it, and so that we can't either.

**What stays on your phone.** Your name (the one you type at onboarding),
your rams, your letters, and the ear tags for letters you wrote. Step
counts come from CoreMotion / HealthKit and are read only to move your rams.
Your location is used only to set where a journey starts and to check that
you're standing at a letter's destination gate.

**What leaves your phone.** A ram, when you hand it off (AirDrop or a shake),
goes directly to the other phone. It contains the letter as ciphertext only
(ChaCha20-Poly1305). The ear tag that opens it never travels with the
ram; you share it with the recipient yourself.

**Purchases.** In-app purchases are handled by Apple and by RevenueCat.
RevenueCat receives an anonymous app-user ID, purchase receipts, and a few
subscriber attributes (your carrier name as you typed it, letters delivered,
steps walked, active rams) so the dashboard can show usage next to revenue.
RevenueCat's privacy policy: https://www.revenuecat.com/privacy

**Anonymous usage stats.** The app counts things like steps walked (in
batches), letters sent and opened, and whether the paywall was viewed. Each
count is tied to a random ID created on your phone, never to your name, Apple
ID, contacts or exact location, and never includes letter text. You can turn
this off any time in Settings, and queued stats are deleted when you do.

**Course telemetry.** This app is part of the BCIT ACIT3855 distributed
systems coursework. Builds pointed at the course receiver post anonymous hop
and flock-metric events (a per-install ID, a ram ID, step counts, timestamps).
No names, no letter contents, no exact location.

**Logs you choose to send.** The app keeps a small log on your phone to help
fix bugs. It is sent only if you tap "Send logs to developer". You review the
email before it goes out. It goes to Anton Baranov (antnbaranov@icloud.com).

**Your choices.** Revoke Location, Motion, Health or Contacts any time in iOS
Settings. Manage subscriptions in your Apple ID. Delete the app to remove all
local data. No accounts, no ads, no tracking across other apps.

Baranov is not directed at children under 13.

Questions: antnbaranov@icloud.com or @antnbaranov.

For RevenueCat Shipaton 2026 · Anton Baranov @antnbaranov

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
