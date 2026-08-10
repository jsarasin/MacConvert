import CryptoKit
import Foundation

struct ConversionLocations: Sendable {
    let temporaryRoot: URL
    let archiveRoot: URL
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
    let archiveURL: URL
    let warnings: [String]
    let technicalLog: String
}

enum ConversionWorkerError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): message
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
            guard !fileManager.fileExists(atPath: target.path) else {
                throw ConversionWorkerError.failed("A file named \(targetName) already exists at the destination")
            }
            await onUpdate(.init(state: .inspecting, detail: "Source is ready", progress: nil, targetURL: target))

            try fileManager.createDirectory(at: locations.temporaryRoot, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: locations.archiveRoot, withIntermediateDirectories: true)
            guard fileManager.isWritableFile(atPath: locations.temporaryRoot.path),
                  fileManager.isWritableFile(atPath: locations.archiveRoot.path) else {
                throw ConversionWorkerError.failed("The temporary and originals folders must be writable")
            }

            let archive = locations.archiveRoot.appendingPathComponent(source.lastPathComponent)
            guard !fileManager.fileExists(atPath: archive.path) else {
                throw ConversionWorkerError.failed(
                    "An original named \(source.lastPathComponent) already exists in the Originals folder"
                )
            }

            let temporarySource = locations.temporaryRoot.appendingPathComponent(source.lastPathComponent)
            let temporaryOutput = locations.temporaryRoot.appendingPathComponent(targetName)
            let partialOutput = locations.temporaryRoot
                .appendingPathComponent(".macconvert-\(job.id.uuidString)-partial.\(outputExtension)")
            let progressFile = locations.temporaryRoot
                .appendingPathComponent(".macconvert-\(job.id.uuidString)-progress.txt")
            let errorFile = locations.temporaryRoot
                .appendingPathComponent(".macconvert-\(job.id.uuidString)-errors.txt")
            ownedURLs.append(contentsOf: [partialOutput, progressFile, errorFile])

            if fileManager.fileExists(atPath: temporarySource.path) {
                if try fileHash(source) == fileHash(temporarySource) {
                    throw ConversionWorkerError.failed("Exact file already converted")
                }
                try preserveExistingTemporaryFile(temporarySource)
                warnings.append("A different file with the same filename existed in Temporary")
            }
            if fileManager.fileExists(atPath: temporaryOutput.path) {
                try preserveExistingTemporaryFile(temporaryOutput)
                if !warnings.contains("A different file with the same filename existed in Temporary") {
                    warnings.append("A different file with the same filename existed in Temporary")
                }
            }

            await onUpdate(.init(state: .copyingLocally, detail: "Copying original to Temporary", progress: nil, targetURL: target))
            try fileManager.copyItem(at: source, to: temporarySource)
            ownedURLs.append(temporarySource)
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
            ownedURLs.append(temporaryOutput)

            await onUpdate(.init(state: .validatingLocally, detail: "Validating converted file", progress: nil, targetURL: target))
            _ = try await probe(temporaryOutput, mediaKind: job.mediaKind, countFrames: false)
            _ = try await runner.runFFmpeg(arguments: [
                "-hide_banner", "-v", "error", "-nostdin", "-i", temporaryOutput.path,
                "-map", "0:v?", "-map", "0:a?", "-f", "null", "-"
            ])

            await onUpdate(.init(state: .publishing, detail: "Moving converted file into place", progress: nil, targetURL: target))
            let staging = targetDirectory.appendingPathComponent(".macconvert-\(job.id.uuidString)-\(targetName)")
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

            await onUpdate(.init(state: .archivingOriginal, detail: "Archiving original", progress: nil, targetURL: target, archiveURL: archive))
            archivedURL = archive
            try fileManager.copyItem(at: temporarySource, to: archive)
            try verifyMatchingFileSizes(temporarySource, archive)
            try fileManager.removeItem(at: temporarySource)

            await onUpdate(.init(state: .removingSource, detail: "Removing original from source folder", progress: nil, targetURL: target, archiveURL: archive))
            try fileManager.removeItem(at: source)
            sourceWasRemoved = true

            try? fileManager.removeItem(at: temporaryOutput)
            for url in [progressFile, errorFile] { try? fileManager.removeItem(at: url) }
            logLines.append("Validated local output, published output, and archived original before removing the source.")
            return ConversionResult(targetURL: target, archiveURL: archive, warnings: warnings, technicalLog: logLines.joined(separator: "\n"))
        } catch {
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

        while process.isRunning {
            if Task.isCancelled {
                process.terminate()
                while process.isRunning {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                throw CancellationError()
            }
            if let duration, duration > 0,
               let progressText = try? String(contentsOf: progressFile, encoding: .utf8),
               let outputSeconds = latestOutputTime(in: progressText) {
                await onProgress(min(max(outputSeconds / duration, 0), 0.99))
            }
            try await Task.sleep(for: .milliseconds(200))
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
        let firstSize = try first.resourceValues(forKeys: [.fileSizeKey]).fileSize
        let secondSize = try second.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard firstSize != nil, firstSize == secondSize else {
            throw ConversionWorkerError.failed("A copied file did not match the expected size")
        }
    }

    private func fileHash(_ url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize()
    }

    private func preserveExistingTemporaryFile(_ url: URL) throws {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let name = ext.isEmpty ? "\(base) \(stamp)" : "\(base) \(stamp).\(ext)"
        let preserved = url.deletingLastPathComponent().appendingPathComponent(name)
        guard !fileManager.fileExists(atPath: preserved.path) else {
            throw ConversionWorkerError.failed("A timestamped Temporary collision also exists")
        }
        try fileManager.moveItem(at: url, to: preserved)
    }

}
