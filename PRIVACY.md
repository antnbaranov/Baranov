# Privacy

_Last updated: September 29, 2026_

Baranov is a slow post. It is built so that the people carrying your letter
cannot read it, and so that we can't either. There are no accounts, no ads,
and no tracking across other apps or websites.

## What stays on your phone

Your name (the one you type at onboarding), your rams, your letters, your
drafts, your journey passport, and the letter codes for letters you wrote
(kept in the iOS Keychain). Also the private key behind your profile code.

Steps come from CoreMotion and HealthKit (including Apple Watch) and are used
to move your rams. Contacts and Calendar are read only on your phone, only to
suggest people and destinations when you address a letter, and are never
uploaded. Dictation uses iOS speech recognition, which is handled by Apple.
Any text written by the on-device model (Apple Intelligence) is generated on
your phone.

## What leaves your phone

**A ram you hand off.** When you hand a ram to someone by AirDrop or a shake, it
goes directly to their phone. The letter inside is ciphertext only
(ChaCha20-Poly1305, see `Services/LetterCipher.swift`). The letter code that
opens it never travels with the ram. You share it with the recipient yourself,
or, if you send to someone's profile code, it is sealed to their phone's
public key first. An **open postcard** is the exception: it is plain text, and
anyone who carries it can read it. Baranov asks you to choose this each time.

**The letter relay.** When a server is configured, every letter you send goes
through the relay so the recipient can follow it and receive it at their gate.
The server stores: the ciphertext, a one-way lookup id derived from the letter
code (never the code), the sender name and recipient name as typed, the ram's
name, the name and coordinates of the journey's starting point, and, if you
address it to a Shepherd ID, the sealed key for that recipient. While the ram
walks, the phone carrying it reports how far it has come and its position
along the route, rounded to about 1 km. When it reaches the gate, the relay
keeps the letter (still sealed) until the recipient's phone collects it, and
the sender is told when it was collected and when it was opened, never where
the recipient is. An **open postcard** is stored as plain text, like it travels.

**Your gate and Shepherd ID.** Your Shepherd ID is registered with the relay as
a public key and a hashed inbox token. Your gate — the town letters to you walk
to, rounded to about 1 km — is stored under it so senders' rams know where to
go; you can move it in Profile. Letters on the relay do not expire
automatically; you can ask for one to be removed (see Contact).

**Push notifications.** If you allow notifications, your phone's Apple push
token is stored with your Shepherd ID so the relay can tell you when a ram is
sent your way, reaches your gate, or when a letter you sent is opened. Turning
notifications off in Settings stops these pushes. Pushes are delivered by Apple
Push Notification service.

**Take it back.** If you ask for a handed-on letter back, the relay stores a
one-way hash of a recall token and the letter id for up to 60 days.

**Sharing your position (off by default).** If you turn on "Share my location
with senders" in Settings, while you carry someone else's ram your phone posts
a position rounded to about 1 km, your carrier name and the ram ids. It is
forgotten when you carry nothing, when you turn the switch off, or after 30
minutes. Senders can look up only ram ids they already hold.

**Anonymous usage stats (on by default, can be turned off).** The app counts
things like steps walked (in batches), letters sent and opened, and whether
the paywall was viewed. Each count is tied to a random ID created on your
phone, never to your name, Apple ID, contacts or exact location, and never
includes letter text. Turn it off any time in Settings; queued stats are then
deleted.

**Course telemetry.** This app is part of the BCIT ACIT3855 distributed
systems coursework. Builds pointed at the course receiver post anonymous hop
and flock-metric events: a per-install ID, a ram ID, step counts, the number
of active rams and letters delivered, and timestamps. No names, no positions
and no letter contents. The same "Share anonymous usage stats" switch in
Settings turns these off.

**Logs you choose to send.** The app keeps a small log on your phone to help fix
bugs. It is sent only if you tap "Send logs to developer", and you review the
email before it goes out.

## Apple and RevenueCat

- **Purchases** are handled by Apple and by RevenueCat. RevenueCat receives an
  anonymous app-user ID, purchase receipts, and a few subscriber attributes
  (your carrier name as you typed it, letters delivered, steps walked, active
  rams) so the dashboard can show usage next to revenue.
  RevenueCat's privacy policy: https://www.revenuecat.com/privacy
- **Maps, routing, Look Around, weather and Game Center** are Apple services.
  Requests for those are governed by Apple's privacy policy.

## Your choices

Revoke Location, Motion, Health, Contacts, Calendar, Microphone or Speech
Recognition any time in iOS Settings. Turn off usage stats and location
sharing in Baranov's Settings. Manage or cancel subscriptions in your Apple
ID settings. Deleting the app removes everything stored on your phone; to
have server-side items removed (a relay letter, a registered profile code),
contact us.

## Children

Baranov is not directed at children under 13, and we do not knowingly
collect their data.

## Changes

If this policy changes we will update the date above and, for material
changes, tell you in the app.

## Contact

antnbaranov@icloud.com, or open an issue on this repository.
