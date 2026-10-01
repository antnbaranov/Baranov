# Privacy Policy

_Last updated: September 30, 2026_

Baranov (“The Slow Ram Post”) is designed around the principles of intentional communication and digital privacy. It is engineered so that neither the couriers carrying your letter nor we as the developers can read your private messages. There are no advertising identifiers, no third-party tracking across apps or websites, and no traditional user accounts.

Baranov is operated by Anton Baranov.

## 1. What Stays on Your Device

The vast majority of your data never leaves your device:

- **Your Profile & Keychain:** Your chosen display name, active rams, letters, drafts, travel log / journey passport, and cryptographic keys (stored securely in the iOS Keychain).
- **Health & Motion Data (HealthKit & CoreMotion):** Step counts and walking activity from your iPhone and Apple Watch are accessed solely on-device to advance your rams along their routes. This data is never uploaded to any remote server or shared with third parties.
- **Contacts & Calendar:** Accessed strictly on-device to suggest recipients and destination events when you address a letter. We never copy, store, or upload your address book.
- **Dictation & On-Device AI:** Voice dictation is processed via Apple’s native speech recognition framework. On-device text assistance is powered entirely locally by Apple Intelligence models on supported devices.

## 2. What Is Transmitted and Stored

When interacting with other users or using networked features, minimal data is transmitted under strict privacy safeguards:

- **Direct Ram Hand-Offs (AirDrop & Local Sharing):** When you pass a ram directly to another device, the message payload is protected with ChaCha20-Poly1305 end-to-end encryption. The decryption key never travels with the courier ram. Only the intended recipient can unlock it. (Exception: If you deliberately choose to send an Open Postcard, the card travels as unencrypted plain text, visible to anyone carrying it).
- **The Letter Relay:** When letters travel over the network, our relay server temporarily facilitates transit. The relay processes:
  - The encrypted ciphertext (or plain text for open postcards).
  - A one-way cryptographic lookup identifier derived from the letter code (never the code itself).
  - Sender and recipient display names as entered.
  - Ram name and approximate journey coordinates rounded to approximately 1 km (coarse location).
  - For Shepherd ID deliveries: the recipient’s public sealing key.
- **Letter Retention & Expiration:** Uncollected letters stored on the relay automatically expire and are permanently purged from the server after 60 days. Once a recipient collects a letter, it is removed from active server transit.
- **Shepherd ID & Gate:** Your Shepherd ID consists of a public key and a hashed inbox token. Your designated “Gate” (the approximate town or region where your letters arrive) is stored with coarse accuracy (~1 km). You can update your Gate or reset your Shepherd ID at any time in Profile Settings.
- **Letter Recalls:** If you recall a sent letter before delivery, a one-way hashed recall token is retained on the relay for up to 60 days to verify cancellation.
- **Carrier Location Sharing (Off by Default):** If you enable “Share location with senders,” your device periodically posts an approximate position rounded to ~1 km along with your courier name while actively carrying another user’s ram. This information is automatically discarded after 30 minutes of inactivity or immediately when toggled off.
- **Push Notifications:** If permitted, your device’s Apple Push Notification service (APNs) token is linked to your Shepherd ID to alert you of incoming rams, deliveries, and letter opens. You can revoke notification permissions at any time in iOS Settings.
- **Anonymous Product Metrics (Opt-Out):** To improve reliability, the app aggregates basic anonymous usage stats (e.g., batches of steps walked, letters sent/opened, paywall impressions). These events are keyed to a random, rotating installation ID, never linked to your identity, Apple ID, or contacts, and never include message content. You can disable anonymous telemetry at any time in Baranov’s Settings.
- **Diagnostic Logs:** Debug logs remain local to your device. They are transmitted only if you explicitly choose to export or send them for troubleshooting, and you can review the contents prior to sending.

## 3. Third-Party Services and Apple Frameworks

We partner exclusively with trusted infrastructure providers necessary for app functionality:

- **In-App Purchases (RevenueCat & Apple StoreKit):** Subscriptions and in-app purchases are processed securely by Apple. We use RevenueCat to validate receipts and manage subscription states. RevenueCat receives an anonymous app user identifier and transaction receipts. For details, refer to [RevenueCat’s Privacy Policy](https://www.revenuecat.com/privacy).
- **Apple Platform Services:** Routing, MapKit visuals, Look Around previews, weather context, and Game Center integrations are provided directly by Apple and governed by [Apple’s Privacy Policy](https://www.apple.com/legal/privacy/).

## 4. Data Control and Deletion Rights

You have complete control over your data:

- **Device Permissions:** You can grant or revoke access to Location, Health, Motion, Contacts, Calendar, Microphone, or Speech Recognition at any time via iOS Settings.
- **Data Deletion:** Deleting the Baranov app removes all local data, drafts, keys, and cached letters from your device.
- **Server Data Purge:** You can reset your Shepherd ID and flush active relay records directly within the app settings. To request manual removal of any orphaned relay entries or registered public keys, contact us at the email below.

## 5. Children’s Privacy

Baranov is not directed toward children under the age of 13. We do not knowingly collect or solicit personal information from children.

## 6. Updates to This Policy

We may update this Privacy Policy from time to time to reflect operational or legal updates. Material changes will be highlighted within the app or noted with a revised date at the top of this page.

## 7. Contact Us

If you have questions, feedback, or data requests regarding this Privacy Policy, please contact:

Anton Baranov

Email: antnbaranov@icloud.com
