//
//  NamesEditorView.swift
//  Baranov
//
//  The three names a letter can be addressed to: real name, nickname, pen
//  name. Opened from the pencil next to the name in Profile. The rules
//  (three edits in total, a 24-hour lock after a letter arrives) live in
//  `NameProfile`; this screen only shows them.
//

import SwiftUI

struct NamesEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var profile = NameProfile.shared
    @State private var primary = NameProfile.primaryName
    @State private var extras: [String] = NameProfile.shared.aliases
    @State private var message: String?
    @State private var savedTick = 0

    private var lockMessage: String {
        String(localized: "Name changes are locked for 24 hours after receiving a letter to prevent delivery spoofing.", bundle: .appLanguage, locale: .appLanguage)
    }

    private var labels: [String] {
        [
            String(localized: "Name", bundle: .appLanguage, locale: .appLanguage),
            String(localized: "Nickname", bundle: .appLanguage, locale: .appLanguage),
            String(localized: "Pen name", bundle: .appLanguage, locale: .appLanguage),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        field(label: labels[0], text: $primary, isFirst: true)
                        Divider().padding(.leading, 16)
                        field(label: labels[1], text: $extras[0], isFirst: false)
                        Divider().padding(.leading, 16)
                        field(label: labels[2], text: $extras[1], isFirst: false)
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    footer

                    Button(action: save) {
                        Text("Save").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ShareCodeGlassButtonStyle(tint: .accentColor, expands: true))
                    .disabled(profile.isLocked)
                    .opacity(profile.isLocked ? 0.5 : 1)
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Your names")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            .sensoryFeedback(.success, trigger: savedTick)
        }
    }

    private func field(label: String, text: Binding<String>, isFirst: Bool) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            TextField(isFirst ? label : String(localized: "Optional", bundle: .appLanguage, locale: .appLanguage), text: text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .disabled(profile.isLocked)
        }
        .font(.body)
        .frame(minHeight: 52)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if profile.isLocked {
                Label(lockMessage, systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            } else {
                Text("A letter addressed to any of these names is yours to open. Changing or removing a name uses one of your \(NameProfile.maxEdits) changes; filling an empty slot is free. \(profile.editsLeft) left.")
                    .foregroundStyle(.secondary)
            }
            if let message {
                Text(message).foregroundStyle(.red)
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func save() {
        switch profile.apply(primary: primary, extras: extras) {
        case .saved:
            savedTick += 1
            dismiss()
        case .unchanged:
            dismiss()
        case .locked:
            message = lockMessage
        case .limitReached:
            message = String(localized: "You've used all your name changes.", bundle: .appLanguage, locale: .appLanguage)
        case .duplicate:
            message = String(localized: "Each name has to be different.", bundle: .appLanguage, locale: .appLanguage)
        }
    }
}

#Preview {
    NamesEditorView()
}
