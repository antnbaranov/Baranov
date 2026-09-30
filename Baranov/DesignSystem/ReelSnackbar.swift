//
//  ReelSnackbar.swift
//  Baranov
//
//  A small floating status for the reel job: while a reel renders it shows
//  the progress, when it is done it offers Share, and if it fails it says
//  so. It watches `ReelJobStore` on its own, so attaching it to a screen
//  never makes that screen redraw as progress ticks by. It is shown by
//  `ReelOverlayWindow`, a window above the app, so no sheet can cover it.
//

import SwiftUI

struct ReelSnackbar: View {
    private var job: ReelJobStore { .shared }
    @State private var hiddenTick = -1

    private var isVisible: Bool {
        // The passport's own reel card already shows this exact job's
        // progress and share button — don't show it twice.
        guard !job.suppressesOverlay else { return false }
        switch job.phase {
        case .writing, .rendering, .failed: return true
        case .ready: return hiddenTick != job.readyTick
        case .idle: return false
        }
    }

    var body: some View {
        Group {
            if isVisible {
                bar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: isVisible)
        .sensoryFeedback(.success, trigger: job.readyTick)
        .task(id: job.readyTick) {
            // Ready stays for a while, then tucks itself away.
            guard job.phase == .ready else { return }
            let tick = job.readyTick
            try? await Task.sleep(for: .seconds(10))
            if job.readyTick == tick { hiddenTick = tick }
        }
    }

    /// Laid out like Apple Music's mini player: artwork, a title with a
    /// quiet subtitle, and one control on the trailing edge.
    private var bar: some View {
        HStack(spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 4) {
                (job.ramName.map { Text("\($0)'s reel") } ?? Text("Your reel"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                switch job.phase {
                case .ready:
                    Text("Ready to share")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed:
                    Text("Did not finish")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                default:
                    ProgressView(value: job.phase == .rendering ? job.progress : nil)
                        .progressViewStyle(.linear)
                    Text(job.phase == .rendering
                         ? String(localized: "Rendering in the background · \(Int(job.progress * 100))%", bundle: .appLanguage, locale: .appLanguage)
                         : String(localized: "Getting started…", bundle: .appLanguage, locale: .appLanguage))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            trailing
        }
        .padding(10)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous),
                     interactive: false, fallbackMaterial: .regularMaterial)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.thinMaterial)
            .frame(width: 48, height: 48)
            .overlay {
                switch job.phase {
                case .ready:
                    Image(systemName: "checkmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.tint)
                case .failed:
                    Image(systemName: "exclamationmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                default:
                    // The "now playing" bars: they only move while it works.
                    Image(systemName: "waveform")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var trailing: some View {
        switch job.phase {
        case .ready:
            if let url = job.videoURL {
                Button {
                    let message = job.data?.shareMessage
                        ?? String(localized: "Made with Baranov, letters that walk: \(AppLinks.appStore.absoluteString)", bundle: .appLanguage, locale: .appLanguage)
                    ActivitySharer.present(items: [url, message])
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share reel")
            }
            closeButton { hiddenTick = job.readyTick }
        case .failed:
            closeButton { job.dismissResult() }
        default:
            EmptyView()
        }
    }

    private func closeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
    }
}

extension View {
    /// Floats the reel job's status at the bottom of this screen.
    func reelSnackbar() -> some View {
        overlay(alignment: .bottom) { ReelSnackbar() }
    }
}
