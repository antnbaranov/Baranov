//
//  DictationService.swift
//  Baranov
//
//  Live speech-to-text for any text field in the app — the same inline
//  microphone button Apple Maps' own search bar has. Tap to start
//  talking, the bound field fills in live as you speak, tap again (or
//  finish speaking) to stop. Whatever text was already in the field when
//  recording started is kept, and spoken words are appended after it —
//  the same way the system keyboard's own dictation key behaves, never a
//  silent overwrite of something already typed.
//
//  Both permissions this needs (microphone, speech recognition) are
//  requested lazily, the moment dictation is first tried, never at app
//  launch. A denial of either just leaves dictation silently unavailable
//  — every field it's attached to is always still a perfectly normal
//  text field either way.
//

import AVFoundation
import Foundation
import Observation
import Speech

@Observable
@MainActor
final class DictationService {
    private(set) var isRecording = false
    private(set) var transcript = ""
    private(set) var isAuthorized = true

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var seedText = ""

    func toggleRecording(appendingTo existingText: String) {
        if isRecording {
            stopRecording()
        } else {
            startRecording(appendingTo: existingText)
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        request?.endAudio()
        task?.cancel()

        audioEngine = nil
        request = nil
        task = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startRecording(appendingTo existingText: String) {
        guard !isRecording else { return }
        seedText = existingText.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = seedText

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.isAuthorized = false
                    return
                }
                self.requestSpeechAuthorizationAndBegin()
            }
        }
    }

    private func requestSpeechAuthorizationAndBegin() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized else {
                    self.isAuthorized = false
                    return
                }
                self.beginSession()
            }
        }
    }

    private func beginSession() {
        guard let recognizer, recognizer.isAvailable else { return }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }

        let engine = AVAudioEngine()
        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        // `installTap` raises an ObjC exception — a hard crash — if the
        // input format has no sample rate or channels, which is exactly
        // what a Simulator without a microphone, a Bluetooth route that
        // just dropped, or a denied mic permission produce. Bow out quietly
        // instead; the field stays an ordinary text field.
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            return
        }

        audioEngine = engine
        request = recognitionRequest
        isRecording = true

        task = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let spoken = result.bestTranscription.formattedString
                    self.transcript = self.seedText.isEmpty ? spoken : "\(self.seedText) \(spoken)"
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stopRecording()
                }
            }
        }
    }
}
