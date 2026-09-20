//
//  WatchBleatPlayer.swift
//  BaranovWatch
//
//  Plays the authentic ram bleat on the Apple Watch speaker.
//

import AVFoundation
import WatchKit

@MainActor
final class WatchBleatPlayer {
    static let shared = WatchBleatPlayer()

    private var player: AVAudioPlayer?
    private var didConfigure = false

    private init() {
        preload()
    }

    private func preload() {
        if let url = Bundle.main.url(forResource: "ram_bleat", withExtension: "wav") {
            if let p = try? AVAudioPlayer(contentsOf: url) {
                p.prepareToPlay()
                self.player = p
            }
        }
    }

    func play() {
        configureSession()
        WKInterfaceDevice.current().play(.click)

        if let player {
            if player.isPlaying { player.currentTime = 0 }
            player.play()
            return
        }

        if let url = Bundle.main.url(forResource: "ram_bleat", withExtension: "wav"),
           let p = try? AVAudioPlayer(contentsOf: url) {
            p.prepareToPlay()
            p.play()
            self.player = p
        }
    }

    private func configureSession() {
        guard !didConfigure else { return }
        didConfigure = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}
