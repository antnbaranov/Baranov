<p align="center">
  <img src="Baranov/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="120" alt="Baranov app icon">
</p>

<h1 align="center">Baranov</h1>

<p align="center">
  <b>A slow post. Your letter is carried by a ram that only moves when you walk.</b><br>
  Native iOS · SwiftUI · CoreMotion · MapKit · AirDrop · CryptoKit · RevenueCat<br>
  <i>RevenueCat Shipaton 2026 — Next Gen (student) entry · BCIT ACIT3855 telemetry client</i>
</p>

<p align="center">
  <a href="https://github.com/antnbaranov/Baranov/actions/workflows/ci.yml"><img src="https://github.com/antnbaranov/Baranov/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/iOS-18.6%2B-black" alt="iOS 18.6+">
  <img src="https://img.shields.io/badge/Swift-6%20%C2%B7%20MainActor%20by%20default-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT">
</p>

---

Everything arrives instantly, so nothing arrives *mattering*. Baranov is a reaction to that: you write a letter, seal it in wax, and a virtual carrier ram sets off along the real road route to the recipient's city. **One of your real steps moves it one metre.** When it reaches a coast or a border it can't cross, you hand it to someone heading that way — by AirDrop, or by shaking two phones together — and they walk it on. At the recipient's gate, the letter is opened by holding the seal until it cracks. The whole journey is stamped into a passport.

The letter itself is ciphertext the entire way. Nobody who carries it can read it.

> **Demo video:** _link goes here for the Devpost submission_ · **Build log:** [`docs/build-log/`](docs/build-log/) — every session that built this app, in order.

## What's in it

| | |
|---|---|
| **Walk it there** | `CMPedometer` steps (with HealthKit / Apple Watch steps merged in) advance the ram along a real MapKit driving route, one metre per step. Map follows the ram with a sprite that walks, gallops and rears; Look Around at its current position; a live "next landmark" so you know what it's about to pass. |
| **Hand it across water** | Reaching an ocean/border leg ends in `.waitingForHandoff`. A `.ram` transit package is a `Transferable` you AirDrop; or two people shake their phones (`Hoofbeat` relay over local network, no internet) and the ram jumps across. The receiving phone resolves the next road leg itself. |
| **Sealed for real** | Sealing is a ritual, not a switch: pick a wax, hold the seal until the wax pools, and a signet stamps your monogram into it — then the envelope closes over the message. A sealed letter's body is ChaCha20-Poly1305 ciphertext, keyed from one human-typeable letter code via HKDF, bound to the letter's id. The same code, run through a different one-way derivation, is how the relay finds the letter — so a recipient enters it once, and the seal opens on arrival with nothing more to type. The code never travels with the ram — it lives in the sender's Keychain and is shared out of band, or wrapped to the recipient's profile code so the letter simply appears in their mailbag. a wrong code shakes and leaves the seal intact. Or skip the wax and send an **open postcard**: plain text, readable by whoever carries it, no code at the gate — the sender's choice, made explicit every time. |
| **The gate** | Opening requires being the addressee *and* standing in the destination city (CoreLocation), then a 1.5 s long-press with heavy haptics while the wax cracks. The revealed letter comes with its stamped passport: every place the ram walked past, and who carried each leg. |
| **Shepherds' Board** | Game Center, shown rather than buried: lifetime XP, your rank with the top three around you, and six badges (First Letter, Seal Broken, 10 km, 100 km, Ocean Crossing, Full Pasture (five out at once)) decided locally and reported to Game Center with the system banner. Game Center friends appear in the carriers card as one-tap carriers. |
| **A ram that grows up** | Your companion ram has a name and a birthday; its lifetime ledger (letters delivered, steps, distinct places) survives every journey. Game Center leaderboards for the walker; a "flock pulse" of how many rams are out in the world right now. |
| **Notifications that earn it** | Four moments only: a ram at the gate, a ram at a coast needing a carrier, a ram that just arrived from someone else, and one nudge after a day of no steps (a gentler one after three, then silence). Plus an 8:30 forecast of real distance left while something is walking. Re-planned on every flock change so nothing fires for a state that no longer exists; tapping one opens that ram. |
| **On-device model, used narrowly** | On iOS 26 with Apple Intelligence, `FoundationModels` writes a one-sentence nudge for *this* letter (who, where, how far, what month) — never the letter itself, and the body is never given to it — and, when a letter is opened, turns the passport stamps into two sentences of travelogue. Everything stays on the phone; on iOS 18 the app reads exactly as before. |
| **Offline-first** | The flock is written through to disk on every change (`FlockStore`), so a ram three days into a walk is still three days into it after a relaunch. Every network call — routing, telemetry, RevenueCat — degrades to the last known state, never to a crash or a lost step. |

## Monetization — how RevenueCat is used, and why

**One ram is free, forever.** Writing, walking, handing off, receiving and opening a letter are never behind a paywall, and no letter ever is. The paywall appears only when someone actually bumps into a limit (a second ram, a locked wax colour), never on launch or on a timer.

| Entitlement | What it unlocks | Products | Shape |
|---|---|---|---|
| `pasture_expansion` | 5 rams at once + every wax colour | `com.baranov.sub.monthly` ($2.99), `com.baranov.sub.quarterly` ($5.99/3 mo), `com.baranov.sub.annual` ($19.99, 7-day trial) | subscription |
| `adopted_ram` | a permanent 2nd ram slot | `com.baranov.iap.ram.merino` ($2.99) | non-consumable, one-time |

Two shapes on purpose: some people want to rent a bigger pasture, some just want to own one more ram and never think about it again. `EntitlementService` folds both into a single `allowedRamSlots` that `FlockViewModel` enforces on every admission path (compose, AirDrop, shake).

What the integration actually does:

- **`Purchases` configured with StoreKit 2**, entitlement state observed live via `PurchasesDelegate` (renewals, lapses, Family Sharing, restores on another device all flow in without polling).
- **Package picker built from the live offering** — every price on screen is the App Store's; the "Best value · save 45%" badge is computed from real prices normalised per week, never typed in.
- **Trial-aware CTA** ("Start Free Trial" / "Then $19.99 per year") driven by `introductoryDiscount` on the fetched product.
- **Customer Center** (`RevenueCatUI`) for cancel / refund / plan changes / restore — from Pasture › Settings › Manage Subscription — so none of that is hand-built.
- **Subscriber attributes** (`carrier_name`, `letters_delivered`, `steps_walked`, `active_rams`) synced on every change, so the RevenueCat dashboard shows usage next to revenue — the same numbers the course telemetry reports.
- **A paywall that demonstrates instead of listing**: the pasture scene at the top shows your own ram alone, then the locked pens open and two more walk in (again whenever you pick a plan — the one-time "adopt" option opens exactly one); the wax row seals a real envelope in whatever colour you tap; monthly/annual is one capsule toggle with the price morphing in place; the only stat shown is how far your rams have really walked.
- **Honest degradation**: with no API key the paywall shows clearly-labelled sample pricing and a mock store unlocks locally, so the whole flow is walkable on any Simulator. Nothing fake is ever shown as real.

See [`Baranov/Config/RevenueCatConfiguration.swift`](Baranov/Config/RevenueCatConfiguration.swift) for the identifiers, [`Baranov/Services/EntitlementService.swift`](Baranov/Services/EntitlementService.swift) for the integration, [`Baranov/Views/Paywall/PasturePaywallView.swift`](Baranov/Views/Paywall/PasturePaywallView.swift) for the screen.

## Running it

You need **Xcode 26** and an iPhone on **iOS 18.6+** (a Simulator works for everything except real steps, real AirDrop and real haptics). No paid Apple Developer account is required — free provisioning is enough to run on your own device.

1. Clone, open `Baranov.xcodeproj`, pick your team under *Signing & Capabilities*.
2. Run. The app starts on `MockEntitlementStore` with sample pricing; everything else is live.
3. **To exercise real purchases without App Store Connect**, create a free RevenueCat project, add a *Test Store* app, and paste its `test_…` public SDK key into `RevenueCatConfiguration.apiKey`. Create the two entitlements and three products from the table above and attach them to the `default` offering. The shared `Baranov` scheme already points at [`Config/Baranov.storekit`](Config/Baranov.storekit), which declares the same products for StoreKit testing.
4. **Tests:** `⌘U`, or `xcodebuild test -scheme Baranov -destination 'platform=iOS Simulator,name=iPhone 17'`. CI runs the same on every push.

To try a whole journey on one phone: write a letter to yourself with a nearby destination, walk, and when the ram reaches the gate open Pasture › the ram › *At the Gate* and hold the seal — the letter code is already on the phone that wrote it.

## Architecture

```
Baranov/
├── Models/          Ram, Letter (ciphertext), RouteNode, JourneyStamp, RamTransitPackage (Transferable), RamRig/ (skeleton + clips)
├── ViewModels/      FlockViewModel — the only place rams are mutated; writes through to FlockStore
├── Services/        StepTracker (CoreMotion+HealthKit) · Route (MapKit) · Location · Handoff gateway · Hoofbeat relay (shake)
│                    LetterCipher (CryptoKit) · SealKeyVault (Keychain) · FlockStore · Entitlement (RevenueCat)
│                    Telemetry (ACIT3855) · RamLedger · GameCenter · Calendar/Contact suggestions · Dictation
├── Views/           Journey (map) · Compose · Pasture · Letter (the gate) · Paywall · Onboarding · Settings
├── DesignSystem/    Materials, field styles, distance formatting, sprite frame sets, SealColor, WaxSeal (press / break / envelope)
└── Config/          RevenueCatConfiguration
BaranovTests/        Swift Testing: cipher, letter wire format, flock rules & persistence, paywall arithmetic
Config/              Baranov.storekit
docs/build-log/      one markdown file per build session, oldest first
```

Principles, in the order they were argued about: strict Apple HIG (system materials, semantic colours, SF Symbols, continuous corners, `sensoryFeedback` — no glassmorphism, no gradient borders, no third-party UI); Swift 6 concurrency with `MainActor` default isolation and `@Observable`; offline-first everywhere; zero private API; nothing mocked in the running app.

## Course telemetry (ACIT3855)

`TelemetryService` posts `POST /telemetry/ram-hop` on every step batch applied to a ram and `POST /telemetry/flock-metric` on flock changes, JSON, fire-and-forget with every failure swallowed and logged. The receiver, its OpenAPI spec and the JMeter load test live in the companion `lab1` repository.

## Honest limits

- The letter code is ~59 bits of entropy (12 characters) — enough to keep a letter private from whoever relays it, not a state secret. The relay stores only a one-way lookup id derived from it. Keeping it typeable off one phone screen onto another was the trade.
- Ocean legs need a human on the other side. There is no server, so there is no "someone will pick it up eventually".
- Live Activity / Dynamic Island progress is next on the list (needs a widget extension target).

## License

MIT — see [LICENSE](LICENSE). Privacy: [PRIVACY.md](PRIVACY.md).
