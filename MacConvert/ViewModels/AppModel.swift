import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

enum CustomSheetKind: String, Identifiable {
    case video
    case picture
    case audio
    var id: Self { self }
}

enum FFmpegToolKind {
    case ffmpeg
    case ffprobe

    var displayName: String { self == .ffmpeg ? "FFmpeg" : "ffprobe" }
}

@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    @ObservationIgnored private var jobTasks: [UUID: Task<Void, Never>] = [:]

    var selectedVideoContainer: ContainerOption = .mp4
    var selectedVideoEncoder: EncoderOption = .h264
    var selectedAudioEncoder: EncoderOption = .aac
    var selectedVideoQuality: QualityPreset = .preserveQuality
    var selectedPictureFormat: PictureFormatOption = .pngAPNG
    var selectedPictureQuality: QualityPreset = .preserveQuality
    var selectedAudioContainer: ContainerOption = .m4a
    var selectedAudioOutputEncoder: EncoderOption = .aac
    var selectedAudioQuality: QualityPreset = .preserveQuality

    var ffmpegCatalog = FFmpegCatalog.empty
    var ffmpegStatus = "Checking bundled FFmpeg…"
    var ffmpegError: String?
    var isDiscoveringFormats = false
    var isCatalogRefreshQueued = false
    var hasAttemptedCatalogLoad = false
    var isShowingFormatSupport = false
    var activeFFmpegURL: URL?
    var activeFFprobeURL: URL?

    var jobs: [ConversionJob] = []
    var selectedJobID: UUID?
    var presentedJob: ConversionJob?
    var customSheetKind: CustomSheetKind?
    var isDropTargeted = false
    var queueIsPaused = false

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    var availableVideoContainers: [ContainerOption] {
        let options = ffmpegCatalog.muxers.map(containerOption)
        let filtered = settings.showAllSupportedFormats
            ? options
            : options.filter { FFmpegCompatibility.popularContainerIDs.contains($0.id) }
        return preferredOrder(filtered, ids: ["mp4", "mov", "matroska", "webm"])
    }

    var availableVideoEncoders: [EncoderOption] {
        var options = availableEncoders(kind: .video, containerID: selectedVideoContainer.id)
        if options.contains(where: { $0.codecID == "h264" }) {
            options.insert(.h264, at: 0)
        }
        return options
    }

    var availableAudioEncoders: [EncoderOption] {
        availableEncoders(kind: .audio, containerID: selectedVideoContainer.id)
    }

    var availableAudioContainers: [ContainerOption] {
        let options = ffmpegCatalog.muxers
            .filter { FFmpegCompatibility.audioContainerIDs.contains($0.id) }
            .map(containerOption)
        let filtered = settings.showAllSupportedFormats
            ? options
            : options.filter { FFmpegCompatibility.popularAudioContainerIDs.contains($0.id) }
        return preferredOrder(filtered, ids: ["ipod", "mp3", "flac", "ogg", "opus", "wav", "caf"])
    }

    var availableAudioOutputEncoders: [EncoderOption] {
        availableEncoders(kind: .audio, containerID: selectedAudioContainer.id)
    }

    var availablePictureFormats: [PictureFormatOption] {
        let muxers = ffmpegCatalog.muxerIDs
        let encoderIDs = Set(ffmpegCatalog.encoders.filter { $0.mediaKind == .video }.map(\.codecID))
        var options: [PictureFormatOption] = []
        if muxers.contains("image2") && muxers.contains("apng") && encoderIDs.contains("png") && encoderIDs.contains("apng") {
            options.append(.pngAPNG)
        }
        if muxers.contains("gif") && encoderIDs.contains("gif") { options.append(.gif) }
        if muxers.contains("image2") && encoderIDs.contains("mjpeg") { options.append(.jpeg) }
        if muxers.contains("image2") && encoderIDs.contains("tiff") { options.append(.tiff) }
        if muxers.contains("webp") && encoderIDs.contains("webp") { options.append(.webP) }
        return options
    }

    var currentProfile: ConversionProfile {
        ConversionProfile(
            videoContainer: selectedVideoContainer,
            videoEncoder: selectedVideoEncoder,
            audioEncoder: selectedAudioEncoder,
            videoQuality: selectedVideoQuality,
            pictureFormat: selectedPictureFormat,
            pictureQuality: selectedPictureQuality,
            audioContainer: selectedAudioContainer,
            audioOutputEncoder: selectedAudioOutputEncoder,
            audioQuality: selectedAudioQuality
        )
    }

    var selectedJob: ConversionJob? {
        guard let selectedJobID else { return nil }
        return jobs.first(where: { $0.id == selectedJobID })
    }

    var finishedJobCount: Int { jobs.filter(\.state.isFinished).count }
    var activeJobCount: Int { jobs.filter(\.state.isActive).count }
    var warningJobCount: Int { jobs.filter { $0.state == .successfulWithWarning }.count }
    var hasQueuedJobs: Bool { jobs.contains { $0.state == .queued } }

    var inheritedSearchPath: String {
        ProcessInfo.processInfo.environment["PATH"] ?? ""
    }

    var ffmpegSourceSummary: String {
        ffmpegSourceSummary(for: settings.ffmpegSourceMode)
    }

    var isUsingNonRedistributableFFmpeg: Bool {
        ffmpegCatalog.buildConfiguration.contains("--enable-nonfree")
    }

    func loadFFmpegCatalogIfNeeded() async {
        guard !hasAttemptedCatalogLoad else { return }
        await refreshFFmpegCatalog()
    }

    func refreshFFmpegCatalog() async {
        guard !isDiscoveringFormats else {
            isCatalogRefreshQueued = true
            return
        }
        isDiscoveringFormats = true
        hasAttemptedCatalogLoad = true
        ffmpegError = nil
        activeFFmpegURL = nil
        activeFFprobeURL = nil
        let sourceMode = settings.ffmpegSourceMode
        let customFFmpegPath = settings.customFFmpegPath
        let customFFprobePath = settings.customFFprobePath
        let sourceSummary = ffmpegSourceSummary(for: sourceMode)
        ffmpegStatus = "Reading \(sourceSummary) FFmpeg capabilities…"

        do {
            let executables = try resolveFFmpegExecutables(
                sourceMode: sourceMode,
                customFFmpegPath: customFFmpegPath,
                customFFprobePath: customFFprobePath
            )
            activeFFmpegURL = executables.ffmpeg
            activeFFprobeURL = executables.ffprobe
            let runner = FFmpegRunner(executables: executables)
            ffmpegCatalog = try await runner.discoverCatalog()
            ffmpegStatus = "FFmpeg \(ffmpegCatalog.version) • \(sourceSummary)"
            normalizeSelections()
        } catch {
            ffmpegCatalog = .empty
            ffmpegError = error.localizedDescription
            ffmpegStatus = "FFmpeg unavailable"
        }

        isDiscoveringFormats = false
        if isCatalogRefreshQueued {
            isCatalogRefreshQueued = false
            await refreshFFmpegCatalog()
        }
    }

    func ffmpegSourceChanged() {
        hasAttemptedCatalogLoad = false
        Task { await refreshFFmpegCatalog() }
    }

    func chooseCustomExecutable(_ kind: FFmpegToolKind) {
        let panel = NSOpenPanel()
        panel.title = "Choose \(kind.displayName)"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        let currentPath = kind == .ffmpeg ? settings.customFFmpegPath : settings.customFFprobePath
        if !currentPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: currentPath).deletingLastPathComponent()
        }

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        if kind == .ffmpeg {
            settings.customFFmpegPath = selectedURL.path
        } else {
            settings.customFFprobePath = selectedURL.path
        }

        if settings.ffmpegSourceMode == .custom,
           !settings.customFFmpegPath.isEmpty,
           !settings.customFFprobePath.isEmpty {
            ffmpegSourceChanged()
        }
    }

    func chooseVideoContainer(_ container: ContainerOption) {
        selectedVideoContainer = container
        normalizeEncoderSelections()
    }

    func chooseAudioContainer(_ container: ContainerOption) {
        selectedAudioContainer = container
        normalizeAudioOutputEncoderSelection()
    }

    func supportedFormatsSettingChanged() {
        normalizeSelections()
    }

    func addFiles(_ urls: [URL]) {
        for url in urls where !jobs.contains(where: { $0.sourceURL == url && !$0.state.isFinished }) {
            let kind = classify(url)
            var job = ConversionJob(sourceURL: url, mediaKind: kind, profile: currentProfile)

            if kind == .unsupported {
                job.state = .failed
                job.statusDetail = "Unsupported file type"
            } else if isAlreadyTargetFormat(url: url, kind: kind) {
                job.state = .failed
                job.statusDetail = "File is already in the selected output format"
            }

            jobs.append(job)
            loadSourceFileSize(for: job.id, from: url)
        }
        if settings.startImmediately {
            startQueuedJobs()
        }
    }

    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose Files to Convert"
        panel.prompt = "Add Files"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.data]

        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    func inspect(_ job: ConversionJob) {
        presentedJob = job
    }

    func inspectSelectedJob() {
        guard let selectedJob else { return }
        inspect(selectedJob)
    }

    func cancel(_ id: UUID) {
        jobTasks[id]?.cancel()
        updateJob(id) { job in
            guard !job.state.isFinished else { return }
            job.state = .cancelled
            job.progress = nil
            job.statusDetail = "Cancelled before conversion"
        }
    }

    func cancelSelectedJob() {
        guard let selectedJobID else { return }
        cancel(selectedJobID)
    }

    func retry(_ id: UUID) {
        updateJob(id) { job in
            guard job.state == .failed || job.state == .cancelled else { return }
            job.state = .queued
            job.progress = nil
            job.statusDetail = "Waiting to be inspected"
            job.warnings = []
            job.technicalLog = ""
        }
        startQueuedJobs()
    }

    func startQueuedJobs() {
        queueIsPaused = false
        scheduleQueuedJobs()
    }

    func toggleQueue() {
        if queueIsPaused || hasQueuedJobs {
            startQueuedJobs()
        } else {
            queueIsPaused = true
        }
    }

    func retrySelectedJob() {
        guard let selectedJobID else { return }
        retry(selectedJobID)
    }

    func clearHistory() {
        jobs.removeAll(where: { $0.state.isFinished })
        if let selectedJobID, !jobs.contains(where: { $0.id == selectedJobID }) {
            self.selectedJobID = nil
        }
    }

    func showTemporary() {
        FinderService.reveal(URL(fileURLWithPath: settings.temporaryPath, isDirectory: true))
    }

    func showOriginals() {
        FinderService.reveal(URL(fileURLWithPath: settings.archivePath, isDirectory: true))
    }

    func chooseVideoQuality(_ quality: QualityPreset) {
        selectedVideoQuality = quality
        if quality == .custom { customSheetKind = .video }
    }

    func choosePictureQuality(_ quality: QualityPreset) {
        selectedPictureQuality = quality
        if quality == .custom { customSheetKind = .picture }
    }

    func chooseAudioQuality(_ quality: QualityPreset) {
        selectedAudioQuality = quality
        if quality == .custom { customSheetKind = .audio }
    }

    func cancelCustomSheet(_ kind: CustomSheetKind) {
        if kind == .video { selectedVideoQuality = .preserveQuality }
        if kind == .picture { selectedPictureQuality = .preserveQuality }
        if kind == .audio { selectedAudioQuality = .preserveQuality }
        customSheetKind = nil
    }

    private func updateJob(_ id: UUID, action: (inout ConversionJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        action(&jobs[index])
    }

    private func scheduleQueuedJobs() {
        guard !queueIsPaused else { return }
        let availableSlots = max(0, settings.maximumConcurrentJobs - jobTasks.count)
        guard availableSlots > 0 else { return }

        let queuedJobs = jobs.filter { $0.state == .queued }.prefix(availableSlots)
        for queuedJob in queuedJobs {
            do {
                let executables = try resolveFFmpegExecutables(
                    sourceMode: settings.ffmpegSourceMode,
                    customFFmpegPath: settings.customFFmpegPath,
                    customFFprobePath: settings.customFFprobePath
                )
                let locations = ConversionLocations(
                    temporaryRoot: URL(fileURLWithPath: settings.temporaryPath, isDirectory: true),
                    archiveRoot: URL(fileURLWithPath: settings.archivePath, isDirectory: true),
                    outputMode: settings.outputDestinationMode,
                    outputRoot: URL(fileURLWithPath: settings.outputPath, isDirectory: true)
                )
                updateJob(queuedJob.id) { job in
                    job.state = .inspecting
                    job.statusDetail = "Preparing to inspect"
                    job.progress = nil
                }
                let task = Task { [weak self] in
                    guard let self else { return }
                    await self.runJob(queuedJob, executables: executables, locations: locations)
                }
                jobTasks[queuedJob.id] = task
            } catch {
                updateJob(queuedJob.id) { job in
                    job.state = .failed
                    job.statusDetail = error.localizedDescription
                    job.technicalLog = error.localizedDescription
                }
            }
        }
    }

    private func runJob(
        _ job: ConversionJob,
        executables: FFmpegExecutables,
        locations: ConversionLocations
    ) async {
        let worker = ConversionWorker(executables: executables)
        do {
            let result = try await worker.process(job: job, locations: locations) { [weak self] update in
                guard let self else { return }
                self.apply(update, to: job.id)
            }
            updateJob(job.id) { current in
                guard current.state != .cancelled else { return }
                current.targetURL = result.targetURL
                current.archiveURL = result.archiveURL
                current.warnings = result.warnings
                current.technicalLog = result.technicalLog
                current.progress = nil
                if result.warnings.isEmpty {
                    current.state = .successful
                    current.statusDetail = "Successful"
                } else {
                    current.state = .successfulWithWarning
                    current.statusDetail = "Successful with warning"
                }
            }
        } catch is CancellationError {
            updateJob(job.id) { current in
                current.state = .cancelled
                current.progress = nil
                current.statusDetail = "Cancelled"
            }
        } catch {
            updateJob(job.id) { current in
                guard current.state != .cancelled else { return }
                current.state = .failed
                current.progress = nil
                current.statusDetail = error.localizedDescription
                current.technicalLog = error.localizedDescription
            }
            if !settings.continueAfterFailure {
                queueIsPaused = true
            }
        }
        jobTasks[job.id] = nil
        scheduleQueuedJobs()
    }

    private func apply(_ update: ConversionUpdate, to id: UUID) {
        updateJob(id) { job in
            guard job.state != .cancelled else { return }
            job.state = update.state
            job.statusDetail = update.detail
            job.progress = update.progress
            if let sourceFileSizeBytes = update.sourceFileSizeBytes {
                job.sourceFileSizeBytes = sourceFileSizeBytes
            }
            if let targetURL = update.targetURL { job.targetURL = targetURL }
            if let archiveURL = update.archiveURL { job.archiveURL = archiveURL }
            if let technicalLog = update.technicalLog {
                job.technicalLog += job.technicalLog.isEmpty ? technicalLog : "\n\(technicalLog)"
            }
        }
    }

    private func classify(_ url: URL) -> MediaKind {
        let videoExtensions = Set(["webm", "mkv", "mov", "mp4", "m4v", "avi"])
        let pictureExtensions = Set(["webp", "gif", "apng", "png", "jpg", "jpeg", "tif", "tiff", "heic", "heif"])
        let audioExtensions = Set(["m4a", "aac", "mp3", "flac", "ogg", "opus", "wav", "aiff", "aif", "caf", "wma", "ac3", "eac3", "amr", "au"])
        let fileExtension = url.pathExtension.lowercased()
        if videoExtensions.contains(fileExtension) { return .video }
        if pictureExtensions.contains(fileExtension) { return .picture }
        if audioExtensions.contains(fileExtension) { return .audio }
        return .unsupported
    }

    private func loadSourceFileSize(for jobID: UUID, from sourceURL: URL) {
        Task { [weak self] in
            let byteCount = await Task.detached(priority: .utility) {
                guard let values = try? sourceURL.resourceValues(forKeys: [.fileSizeKey]),
                      let fileSize = values.fileSize else {
                    return Optional<Int64>.none
                }
                return Int64(fileSize)
            }.value
            guard let self, let byteCount else { return }
            updateJob(jobID) { job in
                job.sourceFileSizeBytes = byteCount
            }
        }
    }

    private func resolveFFmpegExecutables(
        sourceMode: FFmpegSourceMode,
        customFFmpegPath: String,
        customFFprobePath: String
    ) throws -> FFmpegExecutables {
        switch sourceMode {
        case .bundled:
            return try .bundled()
        case .path:
            return try .inPath()
        case .custom:
            return try .custom(
                ffmpegPath: customFFmpegPath,
                ffprobePath: customFFprobePath
            )
        }
    }

    private func ffmpegSourceSummary(for sourceMode: FFmpegSourceMode) -> String {
        switch sourceMode {
        case .bundled: "Bundled"
        case .path: "$PATH"
        case .custom: "Custom"
        }
    }

    private func isAlreadyTargetFormat(url: URL, kind: MediaKind) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        switch kind {
        case .video:
            return fileExtension == selectedVideoContainer.fileExtension
        case .picture:
            return fileExtension == selectedPictureFormat.stillExtension
                || fileExtension == selectedPictureFormat.animatedExtension
        case .audio:
            return fileExtension == selectedAudioContainer.fileExtension
        case .unsupported:
            return false
        }
    }

    private func availableEncoders(kind: EncoderMediaKind, containerID: String) -> [EncoderOption] {
        let options = ffmpegCatalog.encoders
            .filter { $0.mediaKind == kind }
            .filter { FFmpegCompatibility.supports(containerID: containerID, codecID: $0.codecID, mediaKind: kind) }
            .map(encoderOption)
        let filtered = settings.showAllSupportedFormats
            ? options
            : options.filter {
                let popular = kind == .video
                    ? FFmpegCompatibility.popularVideoCodecIDs
                    : FFmpegCompatibility.popularAudioCodecIDs
                return popular.contains($0.codecID)
            }
        let order = kind == .video
            ? ["ffmpeg_default_h264", "libx264", "libx265", "libsvtav1", "libaom-av1", "librav1e", "libvpx-vp9", "prores_ks"]
            : ["aac", "aac_at", "alac", "opus", "mp3", "flac"]
        return preferredOrder(filtered, ids: order)
    }

    private func containerOption(_ muxer: FFmpegMuxer) -> ContainerOption {
        switch muxer.id {
        case "mp4": return .mp4
        case "mov": return .mov
        case "matroska": return .matroska
        case "webm": return .webM
        case "ipod": return .m4a
        case "mp3": return .mp3
        case "flac": return .flac
        case "ogg": return .ogg
        case "opus": return .opus
        case "wav": return .wav
        case "caf": return .caf
        default:
            return ContainerOption(
                id: muxer.id,
                displayName: "\(muxer.id.uppercased()) — \(muxer.description)",
                fileExtension: muxer.id,
                isPopular: false
            )
        }
    }

    private func encoderOption(_ encoder: FFmpegEncoder) -> EncoderOption {
        let baseName: String
        switch encoder.codecID {
        case "h264": baseName = "H.264"
        case "hevc": baseName = "HEVC (H.265)"
        case "av1": baseName = "AV1"
        case "vp9": baseName = "VP9"
        case "vp8": baseName = "VP8"
        case "prores": baseName = "Apple ProRes"
        case "aac": baseName = "AAC-LC"
        case "alac": baseName = "Apple Lossless"
        case "opus": baseName = "Opus"
        case "vorbis": baseName = "Vorbis"
        case "mp3": baseName = "MP3"
        case "flac": baseName = "FLAC"
        default: baseName = encoder.description
        }
        let displayName = encoder.isHardwareAccelerated ? "\(baseName) (Hardware)" : baseName
        return EncoderOption(
            id: encoder.id,
            displayName: displayName,
            codecID: encoder.codecID,
            mediaKind: encoder.mediaKind,
            isPopular: encoder.mediaKind == .video
                ? FFmpegCompatibility.popularVideoCodecIDs.contains(encoder.codecID)
                : FFmpegCompatibility.popularAudioCodecIDs.contains(encoder.codecID),
            isHardwareAccelerated: encoder.isHardwareAccelerated
        )
    }

    private func normalizeSelections() {
        if !availableVideoContainers.contains(selectedVideoContainer), let first = availableVideoContainers.first {
            selectedVideoContainer = first
        }
        normalizeEncoderSelections()
        if !availableAudioContainers.contains(selectedAudioContainer), let first = availableAudioContainers.first {
            selectedAudioContainer = first
        }
        normalizeAudioOutputEncoderSelection()
        if !availablePictureFormats.contains(selectedPictureFormat), let first = availablePictureFormats.first {
            selectedPictureFormat = first
        }
    }

    private func normalizeEncoderSelections() {
        if !availableVideoEncoders.contains(selectedVideoEncoder), let first = availableVideoEncoders.first {
            selectedVideoEncoder = first
        }
        if !availableAudioEncoders.contains(selectedAudioEncoder), let first = availableAudioEncoders.first {
            selectedAudioEncoder = first
        }
    }

    private func normalizeAudioOutputEncoderSelection() {
        if !availableAudioOutputEncoders.contains(selectedAudioOutputEncoder),
           let first = availableAudioOutputEncoders.first {
            selectedAudioOutputEncoder = first
        }
    }

    private func preferredOrder<T: Identifiable>(_ values: [T], ids: [String]) -> [T] where T.ID == String {
        values.sorted {
            let left = ids.firstIndex(of: $0.id) ?? Int.max
            let right = ids.firstIndex(of: $1.id) ?? Int.max
            if left != right { return left < right }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
    }
}
