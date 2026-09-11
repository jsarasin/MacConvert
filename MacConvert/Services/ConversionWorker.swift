import Foundation
import Darwin

struct ConversionLocations: Codable, Hashable, Sendable {
    let temporaryRoot: URL
    let archiveRoot: URL?
    let outputMode: OutputDestinationMode
    let outputRoot: URL
}

struct ConversionUpdate: Sendable {
    let state: JobState
    let detail: String
    let progress: Double?
    var sourceFileSizeBytes: Int64? = nil
    var targetURL: URL? = nil
    var archiveURL: URL? = nil
    var technicalLog: String? = nil
}

struct ConversionResult: Sendable {
    let targetURL: URL
    let archiveURL: URL?
    let warnings: [String]
    let technicalLog: String
}

enum ConversionWorkerError: LocalizedError {
    case failed(String)
    case recoveryRequired(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message), .recoveryRequired(let message): message
        }
    }
}

private struct ProbeSummary: Sendable {
    let duration: Double?
    let videoCodecs: [String]
    let audioCodecs: [String]
    let isAnimated: Bool
    let omittedStreamWarnings: [String]
}

actor ConversionWorker {
    private let executables: FFmpegExecutables
    private let runner: FFmpegRunner
    private let fileManager = FileManager.default

    init(executables: FFmpegExecutables) {
        self.executables = executables
        self.runner = FFmpegRunner(executables: executables)
    }

    func process(
        job: ConversionJob,
        locations: ConversionLocations,
        onUpdate: @escaping @MainActor @Sendable (ConversionUpdate) -> Void
    ) async throws -> ConversionResult {
        let source = job.sourceURL.standardizedFileURL
        var warnings: [String] = []
        var logLines: [String] = []
        var ownedURLs: [URL] = []
        var publishedURL: URL?
        var archivedURL: URL?
        var sourceWasRemoved = false

        do {
            try Task.checkCancellation()
            await onUpdate(.init(state: .inspecting, detail: "Checking source file", progress: nil))
            let sourceFileSize = try preflightSource(source)
            await onUpdate(.init(
                state: .inspecting,
                detail: "Checking source file",
                progress: nil,
                sourceFileSizeBytes: sourceFileSize
            ))

            await onUpdate(.init(state: .inspecting, detail: "Inspecting with ffprobe", progress: nil))
            let input = try await probe(source, mediaKind: job.mediaKind, countFrames: job.mediaKind == .picture)
            warnings.append(contentsOf: input.omittedStreamWarnings)

            if job.mediaKind == .picture, input.isAnimated, !job.profile.pictureFormat.supportsAnimation {
                throw ConversionWorkerError.failed("Selected output format does not support animation")
            }

            let outputExtension = try targetExtension(job: job, isAnimated: input.isAnimated)
            let targetDirectory = locations.outputMode == .besideSource
                ? source.deletingLastPathComponent()
                : locations.outputRoot
            try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            guard fileManager.isWritableFile(atPath: targetDirectory.path) else {
                throw ConversionWorkerError.failed("The output folder is not writable")
            }

            let targetName = source.deletingPathExtension().lastPathComponent + "." + outputExtension
            guard targetName.utf8.count <= 255 else {
                throw ConversionWorkerError.failed("The target filename is too long and needs to be renamed")
            }
            let target = targetDirectory.appendingPathComponent(targetName)
            let replacesSource = target.standardizedFileURL == source
                && job.sameFormatPolicy == .replaceSource
                && job.profile.quality(for: job.mediaKind) != .preserveQuality
            guard !fileManager.fileExists(atPath: target.path) || replacesSource else {
                throw ConversionWorkerError.failed("A file named \(targetName) already exists at the destination")
            }
            await onUpdate(.init(state: .inspecting, detail: "Source is ready", progress: nil, targetURL: target))

            try fileManager.createDirectory(at: locations.temporaryRoot, withIntermediateDirectories: true)
            guard fileManager.isWritableFile(atPath: locations.temporaryRoot.path) else {
                throw ConversionWorkerError.failed("The temporary folder must be writable")
            }
            if let archiveRoot = locations.archiveRoot {
                try fileManager.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
                guard fileManager.isWritableFile(atPath: archiveRoot.path) else {
                    throw ConversionWorkerError.failed("The originals folder must be writable")
                }
            }

            let localSourceName = locations.archiveRoot == nil
                ? "source" + (source.pathExtension.isEmpty ? "" : "." + source.pathExtension)
                : timestampedOriginalName(for: source, timestamp: job.createdAt)
            guard localSourceName.utf8.count <= 255 else {
                throw ConversionWorkerError.failed(
                    "The timestamped original filename is too long for the Temporary and Originals folders"
                )
            }

            let archive = locations.archiveRoot?.appendingPathComponent(localSourceName)
            if let archive, fileManager.fileExists(atPath: archive.path) {
                throw ConversionWorkerError.failed(
                    "A timestamped original named \(localSourceName) already exists in the Originals folder"
                )
            }

            let workingDirectory = locations.temporaryRoot
                .appendingPathComponent("macconvert-\(job.id.uuidString)", isDirectory: true)
            guard !fileManager.fileExists(atPath: workingDirectory.path) else {
                throw ConversionWorkerError.failed("Temporary files already exist for this job and were left untouched")
            }
            try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: false)
            ownedURLs.append(workingDirectory)
            let temporarySource = workingDirectory.appendingPathComponent(localSourceName)
            let temporaryOutput = workingDirectory.appendingPathComponent("converted.\(outputExtension)")
            let partialOutput = workingDirectory.appendingPathComponent("partial.\(outputExtension)")
            let progressFile = workingDirectory.appendingPathComponent("progress.txt")
            let errorFile = workingDirectory.appendingPathComponent("errors.txt")

            await onUpdate(.init(state: .copyingLocally, detail: "Copying original to Temporary", progress: nil, targetURL: target))
            try Task.checkCancellation()
            try fileManager.copyItem(at: source, to: temporarySource)
            try verifyMatchingFileSizes(source, temporarySource)

            let hasTimedProgress = job.mediaKind == .video || job.mediaKind == .audio
            await onUpdate(.init(state: .converting, detail: "Converting with FFmpeg", progress: hasTimedProgress ? 0 : nil, targetURL: target))
            let progressHandler: @Sendable (Double) async -> Void = { progress in
                await onUpdate(.init(state: .converting, detail: "Converting with FFmpeg", progress: progress, targetURL: target))
            }
            let arguments = conversionArguments(job: job, input: input, source: temporarySource, output: partialOutput)
            let conversionLog = try await runConversion(
                arguments: arguments,
                duration: input.duration,
                progressFile: progressFile,
                errorFile: errorFile,
                onProgress: progressHandler
            )
            if !conversionLog.isEmpty { logLines.append(conversionLog) }

            guard fileManager.fileExists(atPath: partialOutput.path) else {
                throw ConversionWorkerError.failed("FFmpeg finished without creating an output file")
            }
            try fileManager.moveItem(at: partialOutput, to: temporaryOutput)

            await onUpdate(.init(state: .validatingLocally, detail: "Validating converted file", progress: nil, targetURL: target))
            _ = try await probe(temporaryOutput, mediaKind: job.mediaKind, countFrames: false)
            _ = try await runner.runFFmpeg(arguments: [
                "-hide_banner", "-v", "error", "-nostdin", "-i", temporaryOutput.path,
                "-map", "0:v?", "-map", "0:a?", "-f", "null", "-"
            ])

            try Task.checkCancellation()
            if replacesSource {
                if let archive {
                    await onUpdate(.init(
                        state: .archivingOriginal,
                        detail: "Archiving original before replacement",
                        progress: nil,
                        targetURL: target,
                        archiveURL: archive
                    ))
                    try Task.checkCancellation()
                    try finalizeArchive(temporarySource, at: archive, jobID: job.id, ownedURLs: &ownedURLs)
                    archivedURL = archive
                }

                await onUpdate(.init(
                    state: .publishing,
                    detail: "Installing validated replacement",
                    progress: nil,
                    targetURL: target,
                    archiveURL: archive
                ))
                try await replaceSource(
                    source,
                    with: temporaryOutput,
                    matchingOriginalCopy: temporarySource,
                    jobID: job.id,
                    mediaKind: job.mediaKind,
                    ownedURLs: &ownedURLs,
                    onInstalled: {
                        onUpdate(.init(
                            state: .validatingDestination,
                            detail: "Checking replacement",
                            progress: nil,
                            targetURL: target,
                            archiveURL: archive
                        ))
                    }
                )
                sourceWasRemoved = true
            } else {
                await onUpdate(.init(state: .publishing, detail: "Moving converted file into place", progress: nil, targetURL: target))
                let staging = targetDirectory.appendingPathComponent(".macconvert-\(job.id.uuidString)-\(targetName)")
                try Task.checkCancellation()
                guard !fileManager.fileExists(atPath: staging.path) else {
                    throw ConversionWorkerError.failed("A temporary publication file already exists and was left untouched")
                }
                ownedURLs.append(staging)
                try fileManager.copyItem(at: temporaryOutput, to: staging)
                try verifyMatchingFileSizes(temporaryOutput, staging)
                guard !fileManager.fileExists(atPath: target.path) else {
                    throw ConversionWorkerError.failed("The target appeared while the job was running; nothing was replaced")
                }
                try fileManager.moveItem(at: staging, to: target)
                publishedURL = target

                await onUpdate(.init(state: .validatingDestination, detail: "Checking published file", progress: nil, targetURL: target))
                try verifyMatchingFileSizes(temporaryOutput, target)
                _ = try await probe(target, mediaKind: job.mediaKind, countFrames: false)

                if let archive {
                    await onUpdate(.init(state: .archivingOriginal, detail: "Archiving original", progress: nil, targetURL: target, archiveURL: archive))
                    try Task.checkCancellation()
                    try finalizeArchive(temporarySource, at: archive, jobID: job.id, ownedURLs: &ownedURLs)
                    archivedURL = archive
                }

                await onUpdate(.init(state: .removingSource, detail: "Removing original from source folder", progress: nil, targetURL: target, archiveURL: archive))
                try Task.checkCancellation()
                guard try filesHaveEqualContents(source, temporarySource) else {
                    throw ConversionWorkerError.failed("The source changed while the job was running, so it was not deleted")
                }
                try Task.checkCancellation()
                try fileManager.removeItem(at: source)
                sourceWasRemoved = true
            }

            do {
                try fileManager.removeItem(at: workingDirectory)
            } catch {
                warnings.append("The conversion succeeded, but some temporary files could not be removed")
            }
            if archive == nil {
                logLines.append("Validated local and published output before deleting the original. No original backup was kept.")
            } else if replacesSource {
                logLines.append("Validated the local output and archived original before installing and validating the replacement.")
            } else {
                logLines.append("Validated local output, published output, and archived original before removing the source.")
            }
            return ConversionResult(targetURL: target, archiveURL: archive, warnings: warnings, technicalLog: logLines.joined(separator: "\n"))
        } catch {
            if case ConversionWorkerError.recoveryRequired = error {
                sourceWasRemoved = true
            }
            if !sourceWasRemoved {
                for url in ownedURLs where fileManager.fileExists(atPath: url.path) {
                    try? fileManager.removeItem(at: url)
                }
                if let publishedURL, fileManager.fileExists(atPath: publishedURL.path) {
                    try? fileManager.removeItem(at: publishedURL)
                }
                if let archivedURL, fileManager.fileExists(atPath: archivedURL.path) {
                    try? fileManager.removeItem(at: archivedURL)
                }
            }
            throw error
        }
    }

    private func finalizeArchive(
        _ temporarySource: URL,
        at archive: URL,
        jobID: UUID,
        ownedURLs: inout [URL]
    ) throws {
        let staging = archive.deletingLastPathComponent()
            .appendingPathComponent(".macconvert-\(jobID.uuidString)-archive")
        guard !fileManager.fileExists(atPath: staging.path) else {
            throw ConversionWorkerError.failed("A temporary archive file already exists and was left untouched")
        }
        ownedURLs.append(staging)
        try fileManager.copyItem(at: temporarySource, to: staging)
        try verifyMatchingFileSizes(temporarySource, staging)
        guard try filesHaveEqualContents(temporarySource, staging) else {
            throw ConversionWorkerError.failed("The archived original did not match the local source copy")
        }
        try Task.checkCancellation()
        guard !fileManager.fileExists(atPath: archive.path) else {
            throw ConversionWorkerError.failed("An original archive appeared while the job was running; nothing was replaced")
        }
        try fileManager.moveItem(at: staging, to: archive)
    }

    private func preflightSource(_ source: URL) throws -> Int64 {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw ConversionWorkerError.failed("The source file no longer exists or is not a regular file")
        }
        guard fileManager.isReadableFile(atPath: source.path) else {
            throw ConversionWorkerError.failed("The source file is not readable")
        }
        guard fileManager.isWritableFile(atPath: source.deletingLastPathComponent().path) else {
            throw ConversionWorkerError.failed("The source folder is not writable")
        }
        let values = try source.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize else {
            throw ConversionWorkerError.failed("The source file size could not be read")
        }
        return Int64(fileSize)
    }

    private func replaceSource(
        _ source: URL,
        with convertedOutput: URL,
        matchingOriginalCopy temporarySource: URL,
        jobID: UUID,
        mediaKind: MediaKind,
        ownedURLs: inout [URL],
        onInstalled: @escaping @MainActor @Sendable () async -> Void
    ) async throws {
        let directory = source.deletingLastPathComponent()
        let staging = directory.appendingPathComponent(
            ".macconvert-\(jobID.uuidString)-replacement.\(source.pathExtension)"
        )
        let backup = directory.appendingPathComponent(
            ".macconvert-\(jobID.uuidString)-original.\(source.pathExtension)"
        )
        guard !fileManager.fileExists(atPath: staging.path),
              !fileManager.fileExists(atPath: backup.path) else {
            throw ConversionWorkerError.failed("MacConvert replacement files already exist beside the source")
        }

        ownedURLs.append(staging)
        try fileManager.copyItem(at: convertedOutput, to: staging)
        try verifyMatchingFileSizes(convertedOutput, staging)

        var sourceMovedToBackup = false
        var replacementInstalled = false
        do {
            try Task.checkCancellation()
            try fileManager.moveItem(at: source, to: backup)
            sourceMovedToBackup = true

            guard try filesHaveEqualContents(backup, temporarySource) else {
                throw ConversionWorkerError.failed(
                    "The source changed while the job was running, so it was not replaced"
                )
            }
            guard !fileManager.fileExists(atPath: source.path) else {
                throw ConversionWorkerError.failed(
                    "A file appeared at the source location while the job was running; nothing was replaced"
                )
            }

            try Task.checkCancellation()
            try fileManager.moveItem(at: staging, to: source)
            replacementInstalled = true
            await onInstalled()
            try Task.checkCancellation()
            try verifyMatchingFileSizes(convertedOutput, source)
            _ = try await probe(source, mediaKind: mediaKind, countFrames: false)
            try Task.checkCancellation()
            try fileManager.removeItem(at: backup)
        } catch {
            if replacementInstalled, fileManager.fileExists(atPath: source.path) {
                try? fileManager.removeItem(at: source)
                replacementInstalled = false
            }
            if sourceMovedToBackup,
               fileManager.fileExists(atPath: backup.path),
               !fileManager.fileExists(atPath: source.path) {
                do {
                    try fileManager.moveItem(at: backup, to: source)
                    sourceMovedToBackup = false
                } catch {
                    throw ConversionWorkerError.recoveryRequired(
                        "The replacement failed and the original could not be restored automatically. The original recovery file beside the source and temporary working files were kept."
                    )
                }
            }
            if sourceMovedToBackup {
                throw ConversionWorkerError.recoveryRequired(
                    "The replacement failed and the source location changed unexpectedly. The original recovery file beside the source and temporary working files were kept."
                )
            }
            throw error
        }
    }

    private func filesHaveEqualContents(_ first: URL, _ second: URL) throws -> Bool {
        let firstSize = try fileSize(at: first)
        let secondSize = try fileSize(at: second)
        guard firstSize == secondSize else { return false }

        let firstHandle = try FileHandle(forReadingFrom: first)
        let secondHandle = try FileHandle(forReadingFrom: second)
        defer {
            try? firstHandle.close()
            try? secondHandle.close()
        }
        while true {
            try Task.checkCancellation()
            let firstData = try firstHandle.read(upToCount: 1_048_576) ?? Data()
            let secondData = try secondHandle.read(upToCount: 1_048_576) ?? Data()
            guard firstData == secondData else { return false }
            if firstData.isEmpty { return true }
        }
    }

    private func probe(_ url: URL, mediaKind: MediaKind, countFrames: Bool) async throws -> ProbeSummary {
        var arguments = ["-v", "error"]
        if countFrames { arguments.append("-count_frames") }
        arguments += ["-show_format", "-show_streams", "-of", "json", url.path]
        let result = try await runner.runFFprobe(arguments: arguments)
        guard let data = result.standardOutput.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = root["streams"] as? [[String: Any]],
              !streams.isEmpty else {
            throw ConversionWorkerError.failed("ffprobe did not find valid media streams")
        }

        let videoStreams = streams.filter { $0["codec_type"] as? String == "video" }
        let audioStreams = streams.filter { $0["codec_type"] as? String == "audio" }
        if mediaKind == .video, videoStreams.isEmpty {
            throw ConversionWorkerError.failed("The file does not contain a video stream")
        }
        if mediaKind == .picture, videoStreams.isEmpty {
            throw ConversionWorkerError.failed("The file does not contain a picture stream")
        }
        if mediaKind == .audio, audioStreams.isEmpty {
            throw ConversionWorkerError.failed("The file does not contain an audio stream")
        }

        let format = root["format"] as? [String: Any]
        let streamDurations = (videoStreams + audioStreams).compactMap { number($0["duration"]) }
        let duration = number(format?["duration"]) ?? streamDurations.max()
        let frameCount = videoStreams.compactMap { number($0["nb_read_frames"]) ?? number($0["nb_frames"]) }.max() ?? 1
        var omitted: [String] = []
        let subtitleCount = streams.filter { $0["codec_type"] as? String == "subtitle" }.count
        let attachmentCount = streams.filter { $0["codec_type"] as? String == "attachment" }.count
        let dataCount = streams.filter { $0["codec_type"] as? String == "data" }.count
        if subtitleCount > 0 { omitted.append("\(subtitleCount) subtitle stream(s) were not included") }
        if attachmentCount > 0 { omitted.append("\(attachmentCount) attachment stream(s) were not included") }
        if dataCount > 0 { omitted.append("\(dataCount) data stream(s) were not included") }

        return ProbeSummary(
            duration: duration,
            videoCodecs: videoStreams.compactMap { $0["codec_name"] as? String },
            audioCodecs: audioStreams.compactMap { $0["codec_name"] as? String },
            isAnimated: mediaKind == .picture && frameCount > 1,
            omittedStreamWarnings: omitted
        )
    }

    private func conversionArguments(
        job: ConversionJob,
        input: ProbeSummary,
        source: URL,
        output: URL
    ) -> [String] {
        var arguments = ["-hide_banner", "-loglevel", "warning", "-nostdin", "-y", "-i", source.path, "-map_metadata", "0"]
        switch job.mediaKind {
        case .video:
            arguments += ["-map", "0:v?", "-map", "0:a?", "-map_chapters", "0"]
            let canCopyVideo = job.profile.videoQuality == .preserveQuality
                && !input.videoCodecs.isEmpty
                && input.videoCodecs.allSatisfy { $0 == job.profile.videoEncoder.codecID }
            let canCopyAudio = job.profile.videoQuality == .preserveQuality
                && !input.audioCodecs.isEmpty
                && input.audioCodecs.allSatisfy { $0 == job.profile.audioEncoder.codecID }
            let usesFFmpegDefaultVideoEncoder = job.profile.videoEncoder.id == "ffmpeg_default_h264"
            if canCopyVideo {
                arguments += ["-c:v", "copy"]
            } else if !usesFFmpegDefaultVideoEncoder {
                arguments += ["-c:v", job.profile.videoEncoder.id]
            }
            if !canCopyVideo && !usesFFmpegDefaultVideoEncoder {
                arguments += videoQualityArguments(
                    job.profile.videoQuality,
                    encoderID: job.profile.videoEncoder.id
                )
            }
            arguments += ["-c:a", canCopyAudio ? "copy" : job.profile.audioEncoder.id]
            if !canCopyAudio {
                arguments += audioQualityArguments(
                    job.profile.videoQuality,
                    encoderID: job.profile.audioEncoder.id
                )
            }
            if job.profile.videoContainer.id == "mp4" || job.profile.videoContainer.id == "mov" {
                arguments += ["-movflags", "+faststart"]
                if !canCopyVideo && job.profile.videoEncoder.codecID == "h264" { arguments += ["-pix_fmt", "yuv420p"] }
            }
        case .picture:
            arguments += ["-map", "0:v:0"]
            switch job.profile.pictureFormat.id {
            case "png_apng" where input.isAnimated:
                arguments += ["-c:v", "apng", "-plays", "0", "-f", "apng"]
            case "png_apng":
                arguments += ["-c:v", "png", "-frames:v", "1", "-update", "1", "-f", "image2"]
            case "gif":
                arguments += ["-c:v", "gif", "-f", "gif"]
            case "webp":
                arguments += ["-c:v", input.isAnimated ? "libwebp_anim" : "libwebp", "-lossless", "1", "-f", "webp"]
                if !input.isAnimated { arguments += ["-frames:v", "1"] }
            case "image2_jpeg":
                arguments += ["-c:v", "mjpeg", "-q:v", pictureQualityValue(job.profile.pictureQuality), "-frames:v", "1", "-update", "1", "-f", "image2"]
            case "image2_tiff":
                arguments += ["-c:v", "tiff", "-frames:v", "1", "-update", "1", "-f", "image2"]
            default:
                arguments += ["-frames:v", "1"]
            }
        case .audio:
            arguments += ["-map", "0:a:0", "-vn"]
            let canCopyAudio = job.profile.audioQuality == .preserveQuality
                && !input.audioCodecs.isEmpty
                && input.audioCodecs.allSatisfy { $0 == job.profile.audioOutputEncoder.codecID }
            arguments += ["-c:a", canCopyAudio ? "copy" : job.profile.audioOutputEncoder.id]
            if !canCopyAudio {
                arguments += audioQualityArguments(
                    job.profile.audioQuality,
                    encoderID: job.profile.audioOutputEncoder.id
                )
            }
            if job.profile.audioContainer.id == "ipod" {
                arguments += ["-movflags", "+faststart"]
            }
        case .unsupported:
            break
        }
        arguments += ["-progress", "pipe:1", "-stats_period", "0.25", "-nostats", output.path]
        return arguments
    }

    private func videoQualityArguments(
        _ quality: QualityPreset,
        encoderID: String
    ) -> [String] {
        if encoderID.contains("264") || encoderID.contains("265") {
            let value = quality == .tinyFile ? "30" : quality == .smallFile ? "23" : "18"
            return ["-crf", value]
        }
        let value = quality == .tinyFile ? "36" : quality == .smallFile ? "30" : "22"
        return ["-crf", value]
    }

    private func audioQualityArguments(_ quality: QualityPreset, encoderID: String) -> [String] {
        if encoderID == "flac" || encoderID == "alac" || encoderID.hasPrefix("pcm_") {
            return []
        }
        return ["-b:a", quality == .tinyFile ? "96k" : quality == .smallFile ? "160k" : "256k"]
    }

    private func pictureQualityValue(_ quality: QualityPreset) -> String {
        quality == .tinyFile ? "8" : quality == .smallFile ? "4" : "2"
    }

    private func targetExtension(job: ConversionJob, isAnimated: Bool) throws -> String {
        switch job.mediaKind {
        case .video: job.profile.videoContainer.fileExtension
        case .picture: job.profile.pictureFormat.fileExtension(isAnimated: isAnimated)
        case .audio: job.profile.audioContainer.fileExtension
        case .unsupported: throw ConversionWorkerError.failed("Unsupported file type")
        }
    }

    private func runConversion(
        arguments: [String],
        duration: Double?,
        progressFile: URL,
        errorFile: URL,
        onProgress: @escaping @Sendable (Double) async -> Void
    ) async throws -> String {
        try Task.checkCancellation()
        fileManager.createFile(atPath: progressFile.path, contents: nil)
        fileManager.createFile(atPath: errorFile.path, contents: nil)
        let progressHandle = try FileHandle(forWritingTo: progressFile)
        let errorHandle = try FileHandle(forWritingTo: errorFile)
        defer {
            try? progressHandle.close()
            try? errorHandle.close()
        }

        let process = Process()
        process.executableURL = executables.ffmpeg
        process.arguments = arguments
        process.standardOutput = progressHandle
        process.standardError = errorHandle
        do {
            try process.run()
        } catch {
            throw FFmpegRunnerError.launchFailed(error.localizedDescription)
        }

        do {
            while process.isRunning {
                try Task.checkCancellation()
                if let duration, duration > 0,
                   let progressText = try? String(contentsOf: progressFile, encoding: .utf8),
                   let outputSeconds = latestOutputTime(in: progressText) {
                    await onProgress(min(max(outputSeconds / duration, 0), 0.99))
                }
                try await Task.sleep(for: .milliseconds(200))
            }
            try Task.checkCancellation()
        } catch {
            if process.isRunning { process.terminate() }
            await Task.detached {
                let deadline = Date().addingTimeInterval(2)
                while process.isRunning, Date() < deadline {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
            }.value
            throw error
        }
        try? progressHandle.synchronize()
        try? errorHandle.synchronize()
        let diagnostics = (try? String(contentsOf: errorFile, encoding: .utf8)) ?? ""
        guard process.terminationStatus == 0 else {
            let message = diagnostics.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConversionWorkerError.failed(message.isEmpty ? "FFmpeg conversion failed" : message)
        }
        if duration != nil { await onProgress(1) }
        return diagnostics.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func latestOutputTime(in progress: String) -> Double? {
        for line in progress.split(separator: "\n").reversed() {
            if line.hasPrefix("out_time_us="), let microseconds = Double(line.dropFirst("out_time_us=".count)) {
                return microseconds / 1_000_000
            }
            if line.hasPrefix("out_time_ms="), let microseconds = Double(line.dropFirst("out_time_ms=".count)) {
                return microseconds / 1_000_000
            }
        }
        return nil
    }

    private func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private func verifyMatchingFileSizes(_ first: URL, _ second: URL) throws {
        let firstSize = try fileSize(at: first)
        let secondSize = try fileSize(at: second)
        guard firstSize == secondSize else {
            throw ConversionWorkerError.failed(
                "The copied \(second.lastPathComponent) file size did not match \(first.lastPathComponent) (\(secondSize) versus \(firstSize) bytes)"
            )
        }
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber else {
            throw ConversionWorkerError.failed("The size of \(url.lastPathComponent) could not be read")
        }
        return size.int64Value
    }

    private func timestampedOriginalName(for source: URL, timestamp: Date) -> String {
        let unixMilliseconds = Int64((timestamp.timeIntervalSince1970 * 1_000).rounded(.down))
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        return ext.isEmpty
            ? "\(base)_\(unixMilliseconds)"
            : "\(base)_\(unixMilliseconds).\(ext)"
    }

}
