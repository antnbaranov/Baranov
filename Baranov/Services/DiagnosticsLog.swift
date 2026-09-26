import Foundation
import OSLog
import UIKit

/// Local, privacy-preserving diagnostics. Nothing leaves the device unless the
/// person taps "Send logs to developer" and sends the resulting email themselves.
actor DiagnosticsLog {
    static let shared = DiagnosticsLog()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Baranov", category: "app")
    private let maxLines = 1_000
    private var lines: [String] = []
    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("diagnostics.log")
        if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
            lines = Array(text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init).suffix(1_000))
        }
    }

    /// Fire-and-forget from any context. Never throws, never blocks the UI.
    nonisolated func log(_ message: String, category: String = "app") {
        Task { await append(message, category: category) }
    }

    private func append(_ message: String, category: String) {
        logger.info("[\(category, privacy: .public)] \(message, privacy: .private)")
        let stamp = ISO8601DateFormatter().string(from: Date())
        lines.append("\(stamp) [\(category)] \(message)")
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        try? lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func clear() {
        lines.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Text report: device summary followed by the recent log lines.
    func exportReport() async -> String {
        let header = await Self.deviceSummary()
        return header + "\n\n--- log ---\n" + (lines.isEmpty ? "(empty)" : lines.joined(separator: "\n"))
    }

    @MainActor
    private static func deviceSummary() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current
        return """
        Baranov \(version) (\(build))
        iOS \(device.systemVersion), \(device.model)
        Locale: \(Locale.current.identifier)
        Generated: \(ISO8601DateFormatter().string(from: Date()))
        """
    }
}
