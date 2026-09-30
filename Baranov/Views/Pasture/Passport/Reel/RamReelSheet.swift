//
//  RamReelSheet.swift
//  Baranov
//
//  Where the reel plays and is shared. The job itself lives in
//  `ReelJobStore`, so closing this sheet never cancels it: the reel keeps
//  rendering while the person carries on in the app, and the reel card in
//  the passport shows the progress and then a Share button. The scene loops
//  live at the full width of the sheet (tap to pause) once it is ready;
//  while the reel is being written or rendered the scene isn't mounted at
//  all and a placeholder in the reel's own palette takes its place. The
//  narrator can be picked from a menu or rolled at random. Nothing leaves
//  the phone until the person taps Share.
//

import SwiftUI

struct RamReelSheet: View {
    let base: RamReelData

    @Environment(\.dismiss) private var dismiss
    @State private var chosenVoice: RamReelVoice?
    private var job: ReelJobStore { .shared }

    // A pausable clock for the live preview.
    @State private var accumulated: Double = 0
    @State private var resumedAt: Date? = Date()
    @State private var isPaused = false

    private var shown: RamReelData { job.data ?? base }
    private var isWriting: Bool { job.phase == .writing || job.phase == .idle }
    private var isExporting: Bool { job.phase == .rendering }
    private var progress: Double { job.progress }
    private var videoURL: URL? { job.phase == .ready ? job.videoURL : nil }
    private var failed: Bool { job.phase == .failed }
    private var theme: ReelTheme { ReelTheme.all[shown.variant % ReelTheme.all.count] }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                preview
                narratorMenu
                action
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .background {
                ZStack {
                    Color(uiColor: .systemGroupedBackground)
                    theme.sky.opacity(0.35)
                }
                .ignoresSafeArea()
                .animation(.smooth, value: shown.variant)
            }
            .navigationTitle("\(base.ramName)'s reel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if #available(iOS 26.0, *) {
                        Button(role: .close) { dismiss() }
                    } else {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Close")
                    }
                }
            }
            .sensoryFeedback(.success, trigger: job.readyTick)
            .sensoryFeedback(.selection, trigger: isPaused)
            .onAppear {
                job.beginIfNeeded(base: base)
                if job.phase == .ready { restartClock() }
            }
            .onChange(of: job.phase) { _, phase in
                if phase == .ready { restartClock() }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Preview

    private var preview: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / RamReelSpec.size.width
            ZStack {
                if isWriting || isExporting {
                    // The scene isn't mounted at all while it's being
                    // written or rendered — that frozen first frame is what
                    // used to read as a rendering glitch. A shimmering
                    // placeholder in the reel's own palette stands in
                    // instead, so this always reads as "loading", never
                    // "broken".
                    ReelRenderingPlaceholder(theme: theme, isWriting: isWriting)
                        .transition(.opacity)
                } else {
                    TimelineView(.animation(paused: isPaused)) { context in
                        RamReelScene(data: shown, time: playbackTime(at: context.date))
                            .environment(\.locale, .appLanguage)
                            .scaleEffect(scale, anchor: .topLeading)
                            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    }
                    .overlay {
                        if isPaused {
                            Image(systemName: "play.fill")
                                .font(.title)
                                .foregroundStyle(.primary)
                                .frame(width: 64, height: 64)
                                .background(.regularMaterial, in: Circle())
                                .transition(.opacity)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .onTapGesture { togglePause() }
            .animation(.smooth, value: isPaused)
            .animation(.smooth, value: isWriting || isExporting)
        }
        .aspectRatio(RamReelSpec.size.width / RamReelSpec.size.height, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement()
        .accessibilityLabel(Text("Preview of \(base.ramName)'s reel"))
        .accessibilityHint(Text(isPaused ? "Double tap to play" : "Double tap to pause"))
        .accessibilityAddTraits(.isButton)
    }

    private func playbackTime(at date: Date) -> Double {
        let running = resumedAt.map { date.timeIntervalSince($0) } ?? 0
        return (accumulated + running).truncatingRemainder(dividingBy: RamReelSpec.duration)
    }

    private func togglePause() {
        if let resumedAt {
            accumulated += Date().timeIntervalSince(resumedAt)
            self.resumedAt = nil
            isPaused = true
        } else {
            resumedAt = Date()
            isPaused = false
        }
    }

    private func restartClock() {
        accumulated = 0
        resumedAt = Date()
        isPaused = false
    }

    // MARK: Narrator

    private var voiceSelection: Binding<RamReelVoice?> {
        Binding(
            get: { shown.voice },
            set: { newValue in
                guard newValue != shown.voice else { return }
                chosenVoice = newValue
                job.start(base: base, voice: newValue)
            }
        )
    }

    private var narratorMenu: some View {
        Menu {
            Button {
                chosenVoice = nil
                job.start(base: base, voice: nil)
            } label: {
                Label("Surprise me", systemImage: "shuffle")
            }
            Picker("Narrator", selection: voiceSelection) {
                ForEach(RamReelVoice.allCases, id: \.self) { voice in
                    Label(voice.name, systemImage: voice.symbol).tag(Optional(voice))
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: shown.voice?.symbol ?? "waveform")
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
                Text(shown.voice?.name ?? String(localized: "Narrator", bundle: .appLanguage, locale: .appLanguage))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.thinMaterial, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isWriting ? 0.5 : 1)
        .animation(.smooth, value: isWriting)
        .disabled(isWriting)
        .accessibilityHint("Choose who narrates the reel")
    }

    // MARK: Action

    @ViewBuilder private var action: some View {
        if let videoURL {
            Button {
                ActivitySharer.present(items: [videoURL, shown.shareMessage])
            } label: {
                Label("Share reel", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ReelActionStyle())
        } else if failed {
            Button {
                job.start(base: base, voice: chosenVoice)
            } label: {
                Label("Try again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ReelActionStyle())
        } else {
            VStack(spacing: 10) {
                Button {} label: {
                    HStack(spacing: 10) {
                        ProgressView(value: isWriting ? nil : progress)
                            .progressViewStyle(.circular)
                        Text(isWriting
                             ? String(localized: "Finding a narrator…", bundle: .appLanguage, locale: .appLanguage)
                             : String(localized: "Rendering… \(Int(progress * 100))%", bundle: .appLanguage, locale: .appLanguage))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ReelActionStyle())
                .disabled(true)

                Button { dismiss() } label: {
                    Text("Keep using the app")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .accessibilityHint("The reel keeps rendering. Its card in the passport shows when it is ready.")
            }
        }
    }
}

/// Stands in for the live preview while the reel is being written or
/// rendered: a shimmering card in the reel's own palette, rather than a
/// frozen frame of the scene.
private struct ReelRenderingPlaceholder: View {
    let theme: ReelTheme
    let isWriting: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(theme.sky.opacity(0.45))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(isWriting
                         ? String(localized: "Finding a narrator…", bundle: .appLanguage, locale: .appLanguage)
                         : String(localized: "Rendering…", bundle: .appLanguage, locale: .appLanguage))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .shimmering()
    }
}

/// The sheet's one big action: a full-width capsule in the accent colour that
/// gives slightly under the finger and springs back.
private struct ReelActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentColor.opacity(isEnabled ? 1 : 0.4), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.4), value: configuration.isPressed)
    }
}
