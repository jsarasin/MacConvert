import AppKit
import Foundation

@MainActor
enum FinderService {
    static func reveal(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }

        var existingURL = url.deletingLastPathComponent()
        while existingURL.path != "/", !FileManager.default.fileExists(atPath: existingURL.path) {
            existingURL.deleteLastPathComponent()
        }
        NSWorkspace.shared.open(existingURL)
    }
}
