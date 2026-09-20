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

    enum Sound: String, CaseIterable {
        case waxStamp = "wax_stamp"
        case waxCrack = "wax_crack"
        case waxShatter = "wax_shatter"
        case paperRustle = "paper_rustle"
        case ramBleat = "ram_bleat"
        case dispatchWhoosh = "dispatch_whoosh"
    }

    private var players: [Sound: AVAudioPlayer] = [:]
    private var didConfigureSession = false

    private init() {
        preloadSounds()
    }

    private func preloadSounds() {
        for sound in Sound.allCases {
            if let url = soundURL(for: sound) {
                if let player = try? AVAudioPlayer(contentsOf: url) {
                    player.prepareToPlay()
                    players[sound] = player
                }
            }
        }
    }

    private func soundURL(for sound: Sound) -> URL? {
        for ext in ["wav", "caf", "m4a", "mp3", "aiff"] {
            if let url = Bundle.main.url(forResource: sound.rawValue, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    func play(_ sound: Sound, volume: Float = 1.0) {
        configureSessionIfNeeded()

        if let player = players[sound] {
            player.volume = volume
            if player.isPlaying {
                player.currentTime = 0
            }
            player.play()
            return
        }

        if let url = soundURL(for: sound),
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
        case .waxCrack, .waxShatter:
            AudioServicesPlaySystemSound(1104)
        case .ramBleat:
            AudioServicesPlaySystemSound(1104)
        case .paperRustle, .dispatchWhoosh:
            break
        }
    }

    private func configureSessionIfNeeded() {
        guard !didConfigureSession else { return }
        didConfigureSession = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}
