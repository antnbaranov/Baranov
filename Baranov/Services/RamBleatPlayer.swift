//
//  RamBleatPlayer.swift
//  Baranov
//
//  Plays a ram's "Mee!" when its portrait is tapped/petted in the
//  selector — a small moment of life on an otherwise static card. Looks
//  for a real bleat recording named "ram_bleat" in the app bundle first
//  (any common audio extension, so whichever format gets dropped in just
//  works); until one is added, falls back to a plain system sound so the
//  interaction still gives feedback rather than doing nothing. Same
//  "wire it now, drop the real asset in later" pattern this project
//  already uses for ram portrait art and the RevenueCat API key.
//
//  AVFoundation/AudioToolbox only — no third-party audio.
//

import AVFoundation
import AudioToolbox

@MainActor
final class RamBleatPlayer {
    static let shared = RamBleatPlayer()

    private var player: AVAudioPlayer?
    private var didConfigureSession = false

    private init() {}

    /// Plays the bleat: the bundled "ram_bleat" recording if one exists,
    /// otherwise a brief system fallback sound. Never throws outward and
    /// never crashes on a missing or corrupt asset — worst case, nothing
    /// audible happens, which is no worse than not calling this at all.
    func play() {
        configureSessionIfNeeded()

        if let url = Self.bundledBleatURL {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                player.play()
                self.player = player
                return
            } catch {
                // Falls through to the system sound below.
            }
        }

        AudioServicesPlaySystemSound(1104)
    }

    private static var bundledBleatURL: URL? {
        for ext in ["caf", "m4a", "mp3", "wav", "aiff"] {
            if let url = Bundle.main.url(forResource: "ram_bleat", withExtension: ext) {
                return url
            }
        }
        return nil
    }

    /// `.ambient` so this never interrupts music/other audio already
    /// playing, and `.mixWithOthers` so it layers instead of ducking
    /// anything — this is a small sound effect, not a media playback
    /// session. Configured lazily, once, on first play rather than at
    /// app launch.
    private func configureSessionIfNeeded() {
        guard !didConfigureSession else { return }
        didConfigureSession = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}
