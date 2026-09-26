//
//  ReelJobStore.swift
//  Baranov
//
//  Owns the reel job so it outlives the sheet that started it. Before this,
//  the sheet's own `.task` did the writing and the rendering, so closing the
//  sheet cancelled the reel and the person had to sit and watch it. Now the
//  sheet only observes: closing it leaves the job running, and the reel card
//  in the passport shows its progress and, when it is done, a Share button.
//
//  Rendering frames still has to happen on the main actor (`ImageRenderer`),
//  so the exporter gives the run loop a real turn after every frame (see
//  `RamReelExporter`); that is what keeps the rest of the app usable while a
//  reel renders. Leaving the app pauses it, and it picks up again on return.
//

import Foundation
import Observation

@MainActor
@Observable
final class ReelJobStore {
    static let shared = ReelJobStore()

    enum Phase: Equatable {
        case idle, writing, rendering, ready, failed
    }

    private(set) var phase: Phase = .idle
    /// Bumped by whichever screen already shows this job's own progress
    /// (the passport's reel card), so the floating overlay bar hides
    /// itself rather than showing the same status twice.
    var suppressesOverlay = false
    /// 0…1 while rendering.
    private(set) var progress: Double = 0
    private(set) var ramName: String?
    /// The written reel (narrator lines, theme, map), once the writing step is done.
    private(set) var data: RamReelData?
    private(set) var videoURL: URL?
    /// Bumps when a reel finishes, for a success haptic.
    private(set) var readyTick = 0

    var isRunning: Bool { phase == .writing || phase == .rendering }

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var signature: String?
    @ObservationIgnored private var builtMap: RamReelMap?
    @ObservationIgnored private var builtMapKey: String?

    private init() {}

    /// Attaches to the job already made for this reel, or starts one.
    func beginIfNeeded(base: RamReelData) {
        if signature == Self.signature(for: base), phase != .idle { return }
        start(base: base, voice: nil)
    }

    /// Starts (or restarts) a reel. `voice` is a chosen narrator, or `nil` for a random one.
    func start(base: RamReelData, voice: RamReelVoice?) {
        task?.cancel()
        let sameReel = signature == Self.signature(for: base)
        let avoiding = sameReel ? data?.voice : nil
        if !sameReel { data = nil }
        signature = Self.signature(for: base)
        ramName = base.ramName
        videoURL = nil
        progress = 0
        phase = .writing
        task = Task { [weak self] in
            await self?.run(base: base, chosen: voice, avoiding: avoiding)
        }
    }

    /// Stops the job and forgets it.
    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
        progress = 0
        videoURL = nil
        signature = nil
        ramName = nil
        data = nil
    }

    /// Clears a finished or failed reel so the card goes back to "Make and share".
    func dismissResult() {
        guard !isRunning else { return }
        cancel()
    }

    // MARK: Running

    private func run(base: RamReelData, chosen: RamReelVoice?, avoiding: RamReelVoice?) async {
        let mapKey = "\(base.ramName)|\(base.placeCoordinates.count)"
        if builtMapKey != mapKey {
            builtMap = await RamReelMapBuilder.build(places: base.placeCoordinates)
            builtMapKey = mapKey
        }
        guard !Task.isCancelled else { return }

        var written = await RamReelWriter.write(for: base, avoiding: avoiding, using: chosen)
        written.map = builtMap
        guard !Task.isCancelled else { return }
        data = written
        phase = .rendering

        do {
            let url = try await RamReelExporter.export(data: written) { [weak self] value in
                self?.progress = value
            }
            guard !Task.isCancelled else { return }
            videoURL = url
            phase = .ready
            readyTick += 1
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed
        }
    }

    private static func signature(for base: RamReelData) -> String {
        "\(base.ramName)|\(base.totalMeters)|\(base.places.count)|\(base.goal ?? "")|\(base.goalDone)"
    }
}
