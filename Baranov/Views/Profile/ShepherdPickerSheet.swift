import SwiftUI
import ImagePlayground

struct ShepherdPickerSheet: View {
    @Binding var selection: String
    @Binding var customFileName: String
    @Binding var motto: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground

    // Nothing is written to the bindings until ✓ is tapped; ✕ discards.
    @State private var draftSelection: String
    @State private var draftCustomFile: String
    @State private var draftMotto: String
    @State private var didConfirm = false
    @State private var showPlayground = false
    @State private var pickTick = 0
    @State private var detent: PresentationDetent = .medium

    init(selection: Binding<String>, customFileName: Binding<String>, motto: Binding<String>) {
        _selection = selection
        _customFileName = customFileName
        _motto = motto
        _draftSelection = State(initialValue: selection.wrappedValue)
        _draftCustomFile = State(initialValue: customFileName.wrappedValue)
        _draftMotto = State(initialValue: motto.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ShepherdAvatarView(selection: draftSelection, customFileName: draftCustomFile,
                                       size: 120, squareCornerRadius: 26)
                        .frame(maxWidth: .infinity)
                    if supportsImagePlayground { playgroundBanner }
                    guildSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .imagePlaygroundSheet(
                isPresented: $showPlayground,
                concept: "portrait of a friendly shepherd with a sheep"
            ) { url in
                guard let name = try? ShepherdAvatarStore.save(from: url) else { return }
                if draftCustomFile != customFileName { ShepherdAvatarStore.remove(draftCustomFile) }
                draftCustomFile = name
                draftSelection = ShepherdIdentityKeys.customSelection
                pickTick += 1
            }
            .navigationTitle("Shepherd avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { cancel() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { confirm() } label: { Image(systemName: "checkmark") }
                        .fontWeight(.semibold)
                        .accessibilityLabel("Done")
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: pickTick)
        .onDisappear { if !didConfirm { discardGenerated() } }
    }

    /// Image Playground is a full-screen system controller; presenting it
    /// while this sheet is still resizing between detents is what froze the
    /// screen. Settle on the large detent first, then present.
    private func openPlayground() {
        guard !showPlayground else { return }
        if detent != .large {
            withAnimation(.snappy) { detent = .large }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            showPlayground = true
        }
    }

    private var playgroundBanner: some View {
        Button(action: openPlayground) {
            HStack(spacing: 12) {
                Image(systemName: "apple.image.playground")
                    .font(.title2)
                    .symbolRenderingMode(.multicolor)
                Text("Create an avatar with Apple Intelligence")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var guildSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Guild keepers")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(ShepherdPreset.allCases) { preset in
                        presetCard(preset)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
        }
    }

    private func presetCard(_ preset: ShepherdPreset) -> some View {
        let isActive = draftSelection == preset.rawValue
        return Button { choose(preset) } label: {
            VStack(spacing: 8) {
                ShepherdAvatarView(selection: preset.rawValue, customFileName: "", size: 80, squareCornerRadius: 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .opacity(isActive ? 1 : 0)
                    )
                Text(preset.title)
                    .font(.footnote.weight(isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 96)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.3), value: isActive)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func choose(_ preset: ShepherdPreset) {
        draftSelection = preset.rawValue
        // Suggest the preset's motto, but never overwrite a motto the user wrote themselves.
        let isUserAuthored = !draftMotto.isEmpty && !ShepherdPreset.allCases.contains { $0.defaultMotto == draftMotto }
        if !isUserAuthored { draftMotto = preset.defaultMotto }
        pickTick += 1
    }

    private func confirm() {
        didConfirm = true
        selection = draftSelection
        customFileName = draftCustomFile
        motto = draftMotto
        if !draftCustomFile.isEmpty { ShepherdAvatarStore.prune(keeping: draftCustomFile) }
        dismiss()
    }

    private func cancel() {
        discardGenerated()
        dismiss()
    }

    /// Removes an image generated in this session that was never applied.
    private func discardGenerated() {
        if draftCustomFile != customFileName { ShepherdAvatarStore.remove(draftCustomFile) }
    }
}
