import SwiftUI

enum SupportContact {
    static let developerEmail = "antnbaranov@icloud.com"
}

/// "Send logs to developer". Present it from a screen's top level (never from inside a
/// List row or Section), so the sheet survives list refreshes.
struct SendLogsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var report: String?

    var body: some View {
        Group {
            if let report {
                if MailComposer.canSendMail {
                    MailComposer(recipient: SupportContact.developerEmail,
                                 subject: "Baranov logs",
                                 body: "Hi Anton, here are my Baranov logs.\n\n(Tell me what happened, if you like.)",
                                 attachmentName: "baranov-logs.txt",
                                 attachment: Data(report.utf8)) {
                        Analytics.shared.track(.logsSent)
                        dismiss()
                    }
                    .ignoresSafeArea()
                } else {
                    NavigationStack {
                        ContentUnavailableView {
                            Label("Mail isn't set up", systemImage: "envelope.badge")
                        } description: {
                            Text("Share the logs another way and send them to \(SupportContact.developerEmail).")
                        } actions: {
                            ShareLink(item: report, subject: Text("Baranov logs")) { Text("Share logs") }
                                .buttonStyle(.borderedProminent)
                        }
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                    }
                    .presentationDetents([.medium])
                }
            } else {
                ProgressView().task { report = await DiagnosticsLog.shared.exportReport() }
            }
        }
    }
}
