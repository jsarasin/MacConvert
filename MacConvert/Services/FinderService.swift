import AppKit
import Foundation

@MainActor
enum FinderService {
    struct JobLocations {
        let original: URL?
        let replacement: URL?

        var isEmpty: Bool { original == nil && replacement == nil }
    }

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

    static func existingLocations(for job: ConversionJob) -> JobLocations {
        let fileManager = FileManager.default
        let archiveFirst = job.state == .archivingOriginal
            || job.state == .removingSource
            || job.state == .successful
            || job.state == .successfulWithWarning
        let replacesSource = job.targetURL?.standardizedFileURL == job.sourceURL.standardizedFileURL
        let sourceIsReplacement = replacesSource
            && (job.state == .validatingDestination || job.state == .successful || job.state == .successfulWithWarning)
        let liveOriginal = sourceIsReplacement ? nil : job.sourceURL
        let originalCandidates: [URL?] = archiveFirst
            ? [job.archiveURL, liveOriginal]
            : [liveOriginal, job.archiveURL]
        let original = originalCandidates
            .compactMap { $0 }
            .first { fileManager.fileExists(atPath: $0.path) }
        let replacement = job.targetURL.flatMap { url in
            (!replacesSource || sourceIsReplacement) && fileManager.fileExists(atPath: url.path) ? url : nil
        }
        return JobLocations(original: original, replacement: replacement)
    }
}
