import SwiftUI
import MessageUI

/// System mail sheet with an attachment. Falls back to a plain-text share when Mail is not set up.
struct MailComposer: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let attachmentName: String
    let attachment: Data
    var onFinish: () -> Void

    static var canSendMail: Bool { MFMailComposeViewController.canSendMail() }

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.addAttachmentData(attachment, mimeType: "text/plain", fileName: attachmentName)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true) { [onFinish] in onFinish() }
        }
    }
}
