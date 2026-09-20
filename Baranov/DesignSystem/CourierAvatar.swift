//
//  CourierAvatar.swift
//  Baranov
//
//  The person's own Memoji. Apple has no API to read someone's Memoji,
//  but the system emoji keyboard offers Memoji stickers to any text view
//  that allows rich content. `MemojiCaptureField` is exactly that view:
//  the person switches to the emoji keyboard, taps their Memoji sticker,
//  and the inserted image is captured here and stored locally as a PNG
//  (transparency kept). No photo library, no permission prompt.
//
//  System materials and semantic styles only.
//

import SwiftUI
import UIKit
import Observation

// MARK: - Store

@MainActor
@Observable
final class CourierAvatarStore {
    private(set) var image: UIImage?

    @ObservationIgnored private static var fileURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("courier-memoji.png")
    }

    init() {
        if let url = Self.fileURL, let data = try? Data(contentsOf: url) {
            image = UIImage(data: data)
        }
    }

    /// Downsamples off the main actor, then stores. A failure leaves the
    /// current Memoji untouched.
    func set(from data: Data) async {
        let png = await Task.detached(priority: .userInitiated) { Self.downsampledPNG(from: data) }.value
        guard let png, let decoded = UIImage(data: png) else { return }
        if let url = Self.fileURL { try? png.write(to: url, options: .atomic) }
        image = decoded
    }

    func remove() {
        if let url = Self.fileURL { try? FileManager.default.removeItem(at: url) }
        image = nil
    }

    nonisolated private static func downsampledPNG(from data: Data) -> Data? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).pngData()
    }
}

// MARK: - Display

struct CourierAvatarView: View {
    let image: UIImage?
    let name: String
    var diameter: CGFloat = 112

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap(\.first)
        return parts.isEmpty ? "?" : String(parts).uppercased()
    }

    var body: some View {
        ZStack {
            Circle().fill(.thinMaterial)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(diameter * 0.04)
            } else {
                Text(initials)
                    .font(.system(size: diameter * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .accessibilityLabel(Text(name))
    }
}

// MARK: - Capture

/// Text view that also catches the Memoji sticker the emoji keyboard
/// pastes as an image.
final class MemojiTextView: UITextView {
    var onPastedImage: ((Data) -> Void)?

    /// Opens on the emoji keyboard (the only one this field needs).
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) { return true }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let board = UIPasteboard.general
        if let data = board.data(forPasteboardType: "public.png") ?? board.data(forPasteboardType: "public.heic"),
           !data.isEmpty {
            onPastedImage?(data)
        } else if let data = board.image?.pngData() {
            onPastedImage?(data)
        } else {
            super.paste(sender)
        }
    }
}

/// Accepts a Memoji sticker or any plain emoji from the emoji keyboard and
/// reports it as PNG data (an emoji is drawn large into an image).
struct MemojiCaptureField: UIViewRepresentable {
    var onCapture: (Data) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    func makeUIView(context: Context) -> MemojiTextView {
        let view = MemojiTextView()
        view.allowsEditingTextAttributes = true
        view.supportsAdaptiveImageGlyph = true
        view.backgroundColor = .clear
        view.font = .systemFont(ofSize: 34)
        view.textAlignment = .center
        view.tintColor = .clear
        view.isScrollEnabled = false
        view.delegate = context.coordinator
        view.onPastedImage = { [weak coordinator = context.coordinator, weak view] data in
            if let view { coordinator?.deliver(data, from: view) }
        }
        DispatchQueue.main.async { view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ uiView: MemojiTextView, context: Context) {
        context.coordinator.onCapture = onCapture
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onCapture: (Data) -> Void
        init(onCapture: @escaping (Data) -> Void) { self.onCapture = onCapture }

        func deliver(_ data: Data, from textView: UITextView) {
            textView.attributedText = NSAttributedString()
            onCapture(data)
        }

        /// Emoji and Memoji only: any typed letter, digit or symbol is refused.
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            text.allSatisfy { $0.isEmojiCharacter || $0 == "\u{FFFC}" }
        }

        func textViewDidChange(_ textView: UITextView) {
            let text = textView.attributedText ?? NSAttributedString()
            let full = NSRange(location: 0, length: text.length)
            var found: Data?

            text.enumerateAttribute(.adaptiveImageGlyph, in: full) { value, _, stop in
                if let glyph = value as? NSAdaptiveImageGlyph {
                    found = glyph.imageContent
                    stop.pointee = true
                }
            }
            if found == nil {
                text.enumerateAttribute(.attachment, in: full) { value, _, stop in
                    guard let attachment = value as? NSTextAttachment else { return }
                    if let data = (attachment.image)?.pngData() ?? attachment.fileWrapper?.regularFileContents {
                        found = data
                        stop.pointee = true
                    }
                }
            }
            if found == nil, let emoji = text.string.first(where: { $0.isEmojiCharacter }) {
                found = Self.render(emoji: String(emoji))
            }
            if let found { deliver(found, from: textView) } else if !text.string.isEmpty { textView.attributedText = NSAttributedString() }
        }

        private static func render(emoji: String) -> Data? {
            let side: CGFloat = 512
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
            let image = renderer.image { _ in
                let font = UIFont.systemFont(ofSize: side * 0.78)
                let attributed = NSAttributedString(string: emoji, attributes: [.font: font])
                let size = attributed.size()
                attributed.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
            }
            return image.pngData()
        }
    }
}

private extension Character {
    var isEmojiCharacter: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation || (first.properties.isEmoji && unicodeScalars.count > 1)
    }
}

/// The sheet: choose an emoji or a Memoji, see it, confirm with the checkmark.
struct MemojiPickerSheet: View {
    var onPick: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pending: Data?

    private var preview: UIImage? { pending.flatMap(UIImage.init(data:)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                CourierAvatarView(image: preview, name: "?", diameter: 112)
                    .padding(.top, 24)

                Text("Pick an emoji or your Memoji")
                    .font(.title3.weight(.semibold))

                Text("Tap the field and choose an emoji or a Memoji sticker. Text isn't accepted here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                MemojiCaptureField { data in pending = data }
                    .frame(height: 56)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 32)
                    .accessibilityLabel("Emoji input")

                Spacer(minLength: 0)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let pending { onPick(pending) }
                        dismiss()
                    } label: { Image(systemName: "checkmark") }
                        .disabled(pending == nil)
                        .accessibilityLabel("Done")
                }
            }
        }
        .presentationDetents([.large])
    }
}
