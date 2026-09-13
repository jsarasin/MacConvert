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

struct SameFormatWarning: Identifiable, Equatable {
    let id: UUID
    let batchID: UUID
    let sourceURL: URL
    let targetFormatName: String
    let remainingFileCount: Int
    let backsUpOriginal: Bool
}

enum SameFormatDecision {
    case skipAll
    case replaceAll
    case skipThisFile
    case replaceThisFile
}

private struct PendingSameFormatBatch {
    let id: UUID
    var jobs: [ConversionJob]
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
    var loopAnimation = true

    var ffmpegCatalog = FFmpegCatalog.empty
    var ffmpegStatus = "Checking bundled FFmpeg…"
    var ffmpegError: String?
    var isDiscoveringFormats = false
    var isCatalogRefreshQueued = false
    var hasAttemptedCatalogLoad = false
    var isShowingFormatSupport = false
    var activeFFmpegURL: URL?
    var activeFFprobeURL: URL?

    var jobs: [ConversionJob] = [] {
        didSet { persistJobs() }
    }
    var selectedJobID: UUID?
    var presentedJob: ConversionJob?
    var customSheetKind: CustomSheetKind?
    var sameFormatWarning: SameFormatWarning?
    var isDropTargeted = false
    var queueIsPaused = false
    @ObservationIgnored private var pendingSameFormatBatches: [PendingSameFormatBatch] = []

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        if settings.rememberHistory,
           let data = settings.defaultsData(forKey: "jobsJournal"),
           let restored = try? JSONDecoder().decode([ConversionJob].self, from: data) {
            self.jobs = restored.map(Self.recoveredJob)
        }
    }

    var availableVideoContainers: [ContainerOption] {
        let options = ffmpegCatalog.muxers
            .filter { !["apng", "gif"].contains($0.id) }
            .map(containerOption)
        let filtered = settings.showAllSupportedFormats
            ? options
            : options.filter { FFmpegCompatibility.popularContainerIDs.contains($0.id) }
        var result = preferredOrder(filtered, ids: ["mp4", "mov", "matroska", "webm"])
        let encoderIDs = Set(ffmpegCatalog.encoders.filter { $0.mediaKind == .video }.map(\.codecID))
        if ffmpegCatalog.muxerIDs.contains("apng") && encoderIDs.contains("apng") {
            result.append(.animatedPNG)
        }
        if ffmpegCatalog.muxerIDs.contains("gif") && encoderIDs.contains("gif") {
            result.append(.animatedGIF)
        }
        return result
    }

    var availableVideoEncoders: [EncoderOption] {
        guard !selectedVideoContainer.isAnimatedImageTarget else { return [] }
        var options = availableEncoders(kind: .video, containerID: selectedVideoContainer.id)
        if options.contains(where: { $0.codecID == "h264" }) {
            options.insert(.h264, at: 0)
        }
        return options
    }

    var availableAudioEncoders: [EncoderOption] {
        guard selectedVideoContainer.supportsAudio else { return [] }
        return availableEncoders(kind: .audio, containerID: selectedVideoContainer.id)
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
            audioQuality: selectedAudioQuality,
            loopAnimation: loopAnimation
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
        let profile = currentProfile
        let locationSnapshot = Result { try captureLocations() }

        for url in urls where !hasUnfinishedOrPendingJob(for: url) {
            let kind = classify(url)
            var job = ConversionJob(
                sourceURL: url, mediaKind: kind, profile: profile,
                locations: try? locationSnapshot.get()
            )

            if case .failure(let error) = locationSnapshot {
                job.state = .failed
                job.statusDetail = error.localizedDescription
                jobs.append(job)
                loadSourceFileSize(for: job.id, from: url)
                continue
            }

            if kind == .unsupported {
                job.state = .failed
                job.statusDetail = "Unsupported file type"
            }

            jobs.append(job)
            loadSourceFileSize(for: job.id, from: url)
        }
        if settings.startImmediately {
            startQueuedJobs()
        }
    }

    func resolveSameFormatWarning(_ warningID: UUID, decision: SameFormatDecision) {
        guard sameFormatWarning?.id == warningID,
              let batchIndex = pendingSameFormatBatches.firstIndex(where: { $0.id == sameFormatWarning?.batchID }) else {
            return
        }

        sameFormatWarning = nil
        switch decision {
        case .skipAll:
            pendingSameFormatBatches.remove(at: batchIndex)
        case .replaceAll:
            let approvedJobs = pendingSameFormatBatches.remove(at: batchIndex).jobs
            appendApprovedSameFormatJobs(approvedJobs)
        case .skipThisFile:
            pendingSameFormatBatches[batchIndex].jobs.removeFirst()
            if pendingSameFormatBatches[batchIndex].jobs.isEmpty {
                pendingSameFormatBatches.remove(at: batchIndex)
            }
        case .replaceThisFile:
            let approvedJob = pendingSameFormatBatches[batchIndex].jobs.removeFirst()
            if pendingSameFormatBatches[batchIndex].jobs.isEmpty {
                pendingSameFormatBatches.remove(at: batchIndex)
            }
            appendApprovedSameFormatJobs([approvedJob])
        }

        if settings.startImmediately { startQueuedJobs() }
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.presentNextSameFormatWarningIfNeeded()
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
        if let task = jobTasks[id] {
            task.cancel()
            updateJob(id) { job in
                job.statusDetail = "Cancelling…"
            }
            return
        }
        updateJob(id) { job in
            guard !job.state.isFinished else { return }
            job.state = .cancelled
            job.progress = nil
            job.statusDetail = "Cancelled before conversion"
        }
    }

    func proceed(_ id: UUID) {
        updateJob(id) { job in
            guard job.state == .awaitingConfirmation else { return }
            job.confirmationAcknowledged = true
            job.confirmationReason = nil
            job.state = .queued
            job.statusDetail = "Waiting to be inspected"
            job.progress = nil
        }
        startQueuedJobs()
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
            job.targetURL = nil
            job.archiveURL = nil
            job.informationalNotes = []
            job.confirmationReason = nil
            job.confirmationAcknowledged = false
            job.originalWasRemoved = nil
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
        let folder = settings.archivePath.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("MacConvert Originals", isDirectory: true)
            : URL(fileURLWithPath: settings.archivePath, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        FinderService.reveal(folder)
    }

    var canShowOriginals: Bool { true }

    private func captureLocations() throws -> ConversionLocations {
        if settings.backupOriginals && settings.archivePath.isEmpty {
            throw ConversionWorkerError.failed("Choose a backup folder in Settings, then add the files again")
        }
        return ConversionLocations(
            temporaryRoot: URL(fileURLWithPath: settings.temporaryPath, isDirectory: true),
            archiveRoot: settings.backupOriginals
                ? URL(fileURLWithPath: settings.archivePath, isDirectory: true) : nil,
            outputMode: settings.outputDestinationMode,
            outputRoot: URL(fileURLWithPath: settings.outputPath, isDirectory: true),
            removeOriginalAfterSuccess: settings.removeOriginalAfterSuccess
        )
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

    private func persistJobs() {
        guard settings.rememberHistory,
              let data = try? JSONEncoder().encode(jobs) else { return }
        settings.setDefaultsData(data, forKey: "jobsJournal")
    }

    private static func recoveredJob(_ job: ConversionJob) -> ConversionJob {
        var recovered = job
        if job.state.isActive {
            recovered.state = .queued
            recovered.progress = nil
            recovered.statusDetail = "Recovered after the app closed; waiting to be inspected"
        }
        return recovered
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
                guard let locations = queuedJob.locations else {
                    throw ConversionWorkerError.failed("The job has no saved file locations. Check Settings and add the file again")
                }
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
            if !job.confirmationAcknowledged {
                let preflight = try await worker.preflight(for: job)
                if job.profile.videoContainer.isAnimatedImageTarget && preflight.hasAudio {
                    updateJob(job.id) { current in
                        current.informationalNotes = ["Audio will be stripped because \(current.profile.videoContainer.displayName) does not support audio."]
                    }
                }
                if let reason = preflight.confirmationReason {
                    updateJob(job.id) { current in
                        current.state = .awaitingConfirmation
                        current.confirmationReason = reason
                        current.progress = nil
                        current.statusDetail = current.confirmationMessage ?? "Awaiting confirmation"
                    }
                    jobTasks[job.id] = nil
                    scheduleQueuedJobs()
                    return
                }
            }
            let result = try await worker.process(job: job, locations: locations) { [weak self] update in
                guard let self else { return }
                self.apply(update, to: job.id)
            }
            updateJob(job.id) { current in
                current.targetURL = result.targetURL
                current.archiveURL = result.archiveURL
                current.warnings = result.warnings
                current.informationalNotes = result.informationalNotes
                current.originalWasRemoved = result.originalWasRemoved
                current.confirmationReason = nil
                current.technicalLog = result.technicalLog
                current.progress = nil
                if result.warnings.isEmpty {
                    current.state = .successful
                    current.statusDetail = result.informationalNotes.isEmpty
                        ? "Successful"
                        : "Successful — \(result.informationalNotes.joined(separator: " • "))"
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

    private func isAlreadyTargetFormat(
        url: URL,
        kind: MediaKind,
        profile: ConversionProfile
    ) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        switch kind {
        case .video:
            return fileExtension == profile.videoContainer.fileExtension
        case .picture:
            return fileExtension == profile.pictureFormat.stillExtension
                || fileExtension == profile.pictureFormat.animatedExtension
        case .audio:
            return fileExtension == profile.audioContainer.fileExtension
        case .unsupported:
            return false
        }
    }

    private func hasUnfinishedOrPendingJob(for url: URL) -> Bool {
        jobs.contains { $0.sourceURL == url && !$0.state.isFinished }
            || pendingSameFormatBatches.contains { batch in
                batch.jobs.contains { $0.sourceURL == url }
            }
    }

    private func appendApprovedSameFormatJobs(_ approvedJobs: [ConversionJob]) {
        for job in approvedJobs {
            jobs.append(job)
            loadSourceFileSize(for: job.id, from: job.sourceURL)
        }
    }

    private func presentNextSameFormatWarningIfNeeded() {
        guard sameFormatWarning == nil,
              let batch = pendingSameFormatBatches.first,
              let job = batch.jobs.first else { return }
        sameFormatWarning = SameFormatWarning(
            id: UUID(),
            batchID: batch.id,
            sourceURL: job.sourceURL,
            targetFormatName: targetFormatName(for: job),
            remainingFileCount: batch.jobs.count,
            backsUpOriginal: job.locations?.archiveRoot != nil
        )
    }

    private func targetFormatName(for job: ConversionJob) -> String {
        switch job.mediaKind {
        case .video: job.profile.videoContainer.displayName
        case .picture: job.profile.pictureFormat.displayName
        case .audio: job.profile.audioContainer.displayName
        case .unsupported: "the selected output"
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
