//
//  SoundEffectPlayer.swift
//  Baranov
//
//  Tactile audio engine for physical organic interactions:
//  - Brass stamp impact into warm viscous wax
//  - Stress fracture micro-cracks while holding the seal
//  - Shattering fracture of brittle hardened wax
//  - Heavy archival cotton paper / parchment rustle on envelope opening
//  - Warm charming ram bleat
//  - Journey dispatch whoosh
//

import AVFoundation
import AudioToolbox

@MainActor
final class SoundEffectPlayer {
    static let shared = SoundEffectPlayer()

    enum Sound: String, CaseIterable, Sendable {
        case waxStamp = "wax_stamp"
        case waxCrack = "wax_crack"
        case waxShatter = "wax_shatter"
        case paperRustle = "paper_rustle"
        case ramBleat = "ram_bleat"
        case ramBleat2 = "ram_bleat_2"
        case ramBleat3 = "ram_bleat_3"
        case dispatchWhoosh = "dispatch_whoosh"
    }

    private let engine = AudioEngine()

    private init() {
        // Session activation and player preparation both touch the audio
        // session, which can block; keep all of it off the main thread.
        Task { await engine.preload() }
    }

    func play(_ sound: Sound, volume: Float = 1.0) {
        Task { await engine.play(sound, volume: volume) }
    }
}

/// Owns every `AVAudioPlayer` and the shared `AVAudioSession`. Being an actor
/// keeps the non-Sendable players isolated and, unlike `@MainActor`, runs the
/// blocking session calls on a background executor.
private actor AudioEngine {
    private var players: [SoundEffectPlayer.Sound: AVAudioPlayer] = [:]
    private var didConfigureSession = false

    func preload() {
        configureSessionIfNeeded()
        for sound in SoundEffectPlayer.Sound.allCases {
            if let url = Self.soundURL(for: sound),
               let player = try? AVAudioPlayer(contentsOf: url) {
                player.prepareToPlay()
                players[sound] = player
            }
        }
    }

    func play(_ sound: SoundEffectPlayer.Sound, volume: Float) {
        configureSessionIfNeeded()

        if let player = players[sound] {
            player.volume = volume
            if player.isPlaying {
                player.currentTime = 0
            }
            player.play()
            return
        }

        if let url = Self.soundURL(for: sound),
           let player = try? AVAudioPlayer(contentsOf: url) {
            player.volume = volume
            player.prepareToPlay()
            player.play()
            players[sound] = player
            return
        }

        // System fallback sound if audio asset is missing
        switch sound {
        case .waxStamp:
            AudioServicesPlaySystemSound(1519) // Strong peek impact
        case .waxCrack, .waxShatter, .ramBleat, .ramBleat2, .ramBleat3:
            AudioServicesPlaySystemSound(1104)
        case .paperRustle, .dispatchWhoosh:
            break
        }
    }

    private static func soundURL(for sound: SoundEffectPlayer.Sound) -> URL? {
        for ext in ["wav", "caf", "m4a", "mp3", "aiff"] {
            if let url = Bundle.main.url(forResource: sound.rawValue, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    private func configureSessionIfNeeded() {
        guard !didConfigureSession else { return }
        didConfigureSession = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}
