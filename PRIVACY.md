# Privacy

Baranov is a slow post. It is built so that the people carrying your letter
cannot read it, and so that we can't either.

**What stays on your phone.** Your name (the one you type at onboarding),
your rams, your letters, the letter codes for letters you wrote, and the private key behind your profile code. Step
counts come from CoreMotion / HealthKit and are read only to move your rams;
they are never uploaded. Your location is used only to set where a journey
starts and to check that you're standing at a letter's destination gate.

**What leaves your phone.** A ram, when you hand it off — by AirDrop or by
a shake — goes directly to the other phone. It contains the letter as
ciphertext only (ChaCha20-Poly1305; see `Services/LetterCipher.swift`). The
letter code that opens it never travels with the ram; you share it with
the recipient yourself, however you like, or — if you send to someone's
profile code — it is sealed to their phone's public key first. The optional
letter relay stores only that ciphertext and a one-way lookup id, never the code.

**Purchases.** In-app purchases are handled by Apple and by RevenueCat.
RevenueCat receives an anonymous app-user ID, purchase receipts, and a few
subscriber attributes we set (your carrier name as you typed it, letters
delivered, steps walked, active rams) so that the dashboard can show usage
next to revenue. RevenueCat's privacy policy: https://www.revenuecat.com/privacy

**Course telemetry.** Builds pointed at the BCIT ACIT3855 telemetry receiver
post anonymous hop and flock-metric events (a per-install UUID, a ram UUID,
step counts, timestamps). No names, no letter contents, no location.

**No accounts, no analytics SDKs, no ads.**

Questions: open an issue on this repository.
