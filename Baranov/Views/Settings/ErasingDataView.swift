//
//  ErasingDataView.swift
//  Baranov
//
//  What the whole window shows while "Delete all data & reset" runs
//  (`AppDataEraser`). It replaces `RootView` on purpose: every screen, store
//  and task that was running is gone before the first file is removed.
//

import SwiftUI

struct ErasingDataView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Deleting your data…")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("This only takes a moment.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ErasingDataView()
}
