//
//  RamReelExporter.swift
//  Baranov
//
//  Renders `RamReelScene` frame by frame into a 720×1280, 30 fps H.264
//  video in the temporary directory — no screen recording, no permissions,
//  and it works offline. Frames are drawn by `ImageRenderer` on the main
//  actor (SwiftUI requires it), so this can't truly run on a background
//  thread. What it does instead is sleep a few milliseconds after every
//  frame: a real pause, not just a yield, so the run loop gets a whole turn
//  (touches, scrolling, the screen commit) between frames and the rest of
//  the app stays usable while a reel renders. `ReelJobStore` owns the job so
//  it keeps going when the sheet is closed.
//

import AVFoundation
import CoreVideo
import SwiftUI
import UniformTypeIdentifiers

/// The finished file, handed to the share sheet as a real video.
struct RamReelVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .mpeg4Movie) { video in
            SentTransferredFile(video.url)
        }
    }
}

enum RamReelExportError: Error {
    case couldNotStart
    case failed
}

@MainActor
enum RamReelExporter {
    static let framesPerSecond = 30
    private static let pixelSize = CGSize(width: 720, height: 1280)

    static func export(data: RamReelData, progress: @escaping (Double) -> Void) async throws -> URL {
        let safeName = data.ramName.filter { $0.isLetter || $0.isNumber }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Baranov-\(safeName.isEmpty ? "Ram" : safeName)-Reel.mp4")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(pixelSize.width),
            AVVideoHeightKey: Int(pixelSize.height),
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(pixelSize.width),
                kCVPixelBufferHeightKey as String: Int(pixelSize.height),
            ]
        )
        guard writer.canAdd(input) else { throw RamReelExportError.couldNotStart }
        writer.add(input)
        guard writer.startWriting() else { throw RamReelExportError.couldNotStart }
        writer.startSession(atSourceTime: .zero)

        do {
            let totalFrames = Int(RamReelSpec.duration * Double(framesPerSecond))
            for frame in 0..<totalFrames {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(5))
                }

                let time = Double(frame) / Double(framesPerSecond)
                let renderer = ImageRenderer(content: RamReelScene(data: data, time: time))
                renderer.scale = pixelSize.width / RamReelSpec.size.width
                guard let image = renderer.cgImage,
                      let pool = adaptor.pixelBufferPool,
                      let buffer = makeBuffer(from: image, pool: pool),
                      adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(framesPerSecond)))
                else { throw RamReelExportError.failed }

                progress(Double(frame + 1) / Double(totalFrames))
                // A real pause after every frame. `Task.yield()` alone can
                // hand the main actor straight back to this loop without the
                // run loop ever reaching input handling or the screen commit,
                // which is what made the whole app read as frozen. Sleeping
                // guarantees the run loop turns before the next frame renders.
                try await Task.sleep(for: .milliseconds(6))
            }
        } catch {
            writer.cancelWriting()
            throw error
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw RamReelExportError.failed }
        return url
    }

    private static func makeBuffer(from image: CGImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)))
        return buffer
    }
}
