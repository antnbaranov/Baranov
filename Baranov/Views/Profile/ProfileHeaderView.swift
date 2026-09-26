import SwiftUI

/// Shepherd identity card: avatar left; name and one saying to its right. Place directly above the "Your Code" card.
struct ProfileHeaderView: View {
    @AppStorage(ShepherdIdentityKeys.name) private var name = ""
    @AppStorage(ShepherdIdentityKeys.avatarSelection) private var avatarSelection = ShepherdPreset.wanderer.rawValue
    @AppStorage(ShepherdIdentityKeys.avatarFile) private var avatarFile = ""
    @AppStorage(ShepherdIdentityKeys.motto) private var motto = ShepherdIdentityKeys.defaultMotto

    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.system.rawValue

    @Environment(\.locale) private var locale
    @State private var showPicker = false
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var tapTick = 0
    @AppStorage("com.baranov.quoteOffset") private var quoteOffset = 0
    /// Today's Foundation Models saying (empty until generated / when unavailable).
    @AppStorage("com.baranov.aiQuote") private var aiQuote = ""
    @AppStorage("com.baranov.aiQuoteDay") private var aiQuoteDay = ""
    @State private var isGenerating = false

    private var todayKey: String { Date.now.formatted(.iso8601.year().month().day()) }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Button {
                tapTick += 1
                showPicker = true
            } label: {
                ShepherdAvatarView(selection: avatarSelection, customFileName: avatarFile, size: 104,
                                   showsEditBadge: true, squareCornerRadius: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change shepherd avatar")

            VStack(alignment: .leading, spacing: 8) {
                nameRow
                quoteView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .sensoryFeedback(.impact(weight: .light), trigger: tapTick)
        .sheet(isPresented: $showPicker) {
            ShepherdPickerSheet(selection: $avatarSelection, customFileName: $avatarFile, motto: $motto)
                .preferredColorScheme((AppAppearance(rawValue: appearanceRawValue) ?? .system).colorScheme)
        }
        .alert("Your name", isPresented: $editingName) {
            TextField("Name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { name = trimmed }
            }
        }
        .task {
            // One fresh on-device saying per day; offline / unsupported devices keep the classic ones.
            if aiQuoteDay != todayKey || aiQuote.isEmpty { await refreshAIQuote() }
        }
    }

    private var nameRow: some View {
        HStack(spacing: 6) {
            Text(name.isEmpty ? String(localized: "Courier") : name)
                .font(.system(.title2, design: .serif).weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Button {
                nameDraft = name
                editingName = true
            } label: {
                Image(systemName: "pencil")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Edit name")
        }
    }

    /// One saying per day written by Apple's on-device model; tap for another.
    /// Falls back to the classic proverbs when the model isn't available.
    private var quoteView: some View {
        let fallback = CourierQuotes.quote(offset: quoteOffset)
        let text = aiQuote.isEmpty ? fallback.text : aiQuote
        let source = aiQuote.isEmpty ? fallback.source : String(localized: "Apple Intelligence")
        return Button {
            tapTick += 1
            quoteOffset += 1
            Task { await refreshAIQuote() }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\u{201C}\(text)\u{201D}")
                    .font(.subheadline.italic())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(isGenerating ? 0.4 : 1)
                    .animation(.easeInOut(duration: 0.25), value: isGenerating)
                Text(source)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
        .accessibilityHint("Tap to show another saying")
    }

    private func refreshAIQuote() async {
        isGenerating = true
        defer { isGenerating = false }
        let code = locale.language.languageCode?.identifier ?? "en"
        if let fresh = await ShepherdQuoteService.generate(languageCode: code) {
            aiQuote = fresh
            aiQuoteDay = todayKey
        }
    }
}

#Preview {
    ProfileHeaderView().padding()
}
