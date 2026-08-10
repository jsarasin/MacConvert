import XCTest

@MainActor
final class MacConvertTests: XCTestCase {
    func testAdaptivePictureFormatUsesPNGForStillImages() {
        XCTAssertEqual(PictureFormatOption.pngAPNG.fileExtension(isAnimated: false), "png")
    }

    func testAdaptivePictureFormatUsesAPNGForAnimatedImages() {
        XCTAssertEqual(PictureFormatOption.pngAPNG.fileExtension(isAnimated: true), "apng")
        XCTAssertTrue(PictureFormatOption.pngAPNG.supportsAnimation)
    }

    func testStillOnlyFormatsReportNoAnimationSupport() {
        XCTAssertFalse(PictureFormatOption.jpeg.supportsAnimation)
        XCTAssertFalse(PictureFormatOption.tiff.supportsAnimation)
    }

    func testFinishedJobStates() {
        XCTAssertTrue(JobState.successful.isFinished)
        XCTAssertTrue(JobState.failed.isFinished)
        XCTAssertFalse(JobState.queued.isFinished)
        XCTAssertFalse(JobState.converting.isFinished)
    }

    func testJobSourceSizeUsesReadableMBAndGBRounding() {
        var megabyteJob = ConversionJob(
            sourceURL: URL(fileURLWithPath: "/tmp/example.webm"),
            mediaKind: .video,
            profile: .standard
        )
        megabyteJob.sourceFileSizeBytes = 52_430_000
        XCTAssertEqual(megabyteJob.sourceFileSizeDisplay, "52.4 MB")

        var gigabyteJob = megabyteJob
        gigabyteJob.sourceFileSizeBytes = 1_536_000_000
        XCTAssertEqual(gigabyteJob.sourceFileSizeDisplay, "1.54 GB")
    }

    func testDefaultProfileMatchesProductDefaults() {
        let profile = ConversionProfile.standard
        XCTAssertEqual(profile.videoContainer, .mp4)
        XCTAssertEqual(profile.videoEncoder, .h264)
        XCTAssertEqual(profile.audioEncoder, .aac)
        XCTAssertEqual(profile.videoQuality, .preserveQuality)
        XCTAssertEqual(profile.pictureFormat, .pngAPNG)
        XCTAssertEqual(profile.pictureQuality, .preserveQuality)
        XCTAssertEqual(profile.audioContainer, .m4a)
        XCTAssertEqual(profile.audioOutputEncoder, .aac)
        XCTAssertEqual(profile.audioQuality, .preserveQuality)
    }

    func testMuxerParserExpandsAliasesAndOnlyIncludesWritableFormats() {
        let output = """
         D  matroska,webm   Matroska / WebM
          E mp4             MP4 (MPEG-4 Part 14)
         DE mov,mp4         QuickTime / MOV
        """
        let muxers = FFmpegCatalogParser.parseMuxers(output)
        XCTAssertEqual(Set(muxers.map(\.id)), ["mov", "mp4"])
    }

    func testEncoderParserFindsSoftwareMediaCodecs() {
        let output = """
         V....D libx264           libx264 H.264 encoder (codec h264)
         A....D aac               AAC (Advanced Audio Coding)
         S..... srt               SubRip subtitle
        """
        let encoders = FFmpegCatalogParser.parseEncoders(output)
        XCTAssertEqual(encoders.count, 2)
        XCTAssertEqual(encoders.first(where: { $0.id == "libx264" })?.codecID, "h264")
        XCTAssertEqual(encoders.first(where: { $0.id == "libx264" })?.isHardwareAccelerated, false)
        XCTAssertEqual(encoders.first(where: { $0.id == "aac" })?.mediaKind, .audio)
    }

    func testCompatibilityFiltersWebMEncoders() {
        XCTAssertTrue(FFmpegCompatibility.supports(containerID: "webm", codecID: "vp9", mediaKind: .video))
        XCTAssertTrue(FFmpegCompatibility.supports(containerID: "webm", codecID: "opus", mediaKind: .audio))
        XCTAssertFalse(FFmpegCompatibility.supports(containerID: "webm", codecID: "h264", mediaKind: .video))
        XCTAssertFalse(FFmpegCompatibility.supports(containerID: "webm", codecID: "aac", mediaKind: .audio))
    }

    func testCompatibilityFiltersStandaloneAudioEncoders() {
        XCTAssertTrue(FFmpegCompatibility.supports(containerID: "ipod", codecID: "aac", mediaKind: .audio))
        XCTAssertFalse(FFmpegCompatibility.supports(containerID: "ipod", codecID: "opus", mediaKind: .audio))
        XCTAssertTrue(FFmpegCompatibility.supports(containerID: "flac", codecID: "flac", mediaKind: .audio))
        XCTAssertFalse(FFmpegCompatibility.supports(containerID: "flac", codecID: "aac", mediaKind: .audio))
    }

    func testAddingAudioCreatesAnAudioJob() {
        let suiteName = "MacConvertTests.AudioClassification.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.startImmediately = false
        let model = AppModel(settings: settings)

        model.addFiles([URL(fileURLWithPath: "/tmp/example.flac")])

        XCTAssertEqual(model.jobs.count, 1)
        XCTAssertEqual(model.jobs[0].mediaKind, .audio)
        XCTAssertEqual(model.jobs[0].profile.audioContainer, .m4a)
        XCTAssertTrue(model.jobs[0].profileSummary.contains("FLAC → M4A"))
    }

    func testWAVConvertsToDefaultM4AAudioProfile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacConvertAudioTests-\(UUID().uuidString)", isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
        let archiveDirectory = root.appendingPathComponent("Originals", isDirectory: true)
        let temporaryDirectory = root.appendingPathComponent("Temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = sourceDirectory.appendingPathComponent("sample.wav")
        let executables = try testExecutables()
        let runner = FFmpegRunner(executables: executables)
        _ = try await runner.runFFmpeg(arguments: [
            "-hide_banner", "-v", "error", "-y",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=0.5",
            "-c:a", "pcm_s16le", source.path
        ])

        let worker = ConversionWorker(executables: executables)
        let result = try await worker.process(
            job: ConversionJob(sourceURL: source, mediaKind: .audio, profile: .standard),
            locations: ConversionLocations(
                temporaryRoot: temporaryDirectory,
                archiveRoot: archiveDirectory,
                outputMode: .besideSource,
                outputRoot: root
            ),
            onUpdate: { _ in }
        )

        XCTAssertEqual(result.targetURL.lastPathComponent, "sample.m4a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.archiveURL.path))
        let probe = try await runner.runFFprobe(arguments: [
            "-v", "error", "-show_entries", "stream=codec_name", "-of", "csv=p=0", result.targetURL.path
        ])
        XCTAssertTrue(probe.standardOutput.contains("aac"))
    }

    func testFFmpegCanDiscoverItsRuntimeCatalog() async throws {
        let runner = FFmpegRunner(executables: try testExecutables())
        let catalog = try await runner.discoverCatalog()

        XCTAssertEqual(catalog.version, "8.1.2")
        XCTAssertTrue(catalog.muxerIDs.contains("mp4"))
        XCTAssertTrue(catalog.muxerIDs.contains("apng"))
        XCTAssertTrue(catalog.encoders.contains { $0.codecID == "aac" && $0.mediaKind == .audio })
        XCTAssertTrue(catalog.buildConfiguration.contains("--enable-nonfree"))
        XCTAssertTrue(catalog.encoders.contains { $0.id == "libfdk_aac" })
        XCTAssertTrue(catalog.encoders.contains { $0.id == "libx264" })
        XCTAssertTrue(catalog.encoders.contains { $0.id == "libx265" })
        XCTAssertTrue(catalog.encoders.contains { $0.id == "libsvtav1" })
        XCTAssertTrue(catalog.encoders.contains { $0.id == "libwebp_anim" })
    }

    func testAddingAFileStartsTheQueueAutomatically() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacConvertQueueTests-\(UUID().uuidString)", isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = sourceDirectory.appendingPathComponent("queued.webm")
        let executables = try testExecutables()
        let runner = FFmpegRunner(executables: executables)
        _ = try await runner.runFFmpeg(arguments: [
            "-hide_banner", "-v", "error", "-y",
            "-f", "lavfi", "-i", "testsrc2=size=128x72:rate=24:duration=1",
            "-c:v", "libvpx-vp9", source.path
        ])

        let suiteName = "MacConvertTests.Queue.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.temporaryPath = root.appendingPathComponent("Temporary", isDirectory: true).path
        settings.archivePath = root.appendingPathComponent("Originals", isDirectory: true).path
        settings.startImmediately = true
        settings.ffmpegSourceMode = .custom
        settings.customFFmpegPath = executables.ffmpeg.path
        settings.customFFprobePath = executables.ffprobe.path
        let model = AppModel(settings: settings)

        model.addFiles([source])
        XCTAssertEqual(model.jobs.count, 1)
        XCTAssertNotEqual(model.jobs[0].state, .queued)

        for _ in 0..<100 where !model.jobs[0].state.isFinished {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(model.jobs[0].state == .successful || model.jobs[0].state == .successfulWithWarning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        let target = try XCTUnwrap(model.jobs[0].targetURL)
        let archive = try XCTUnwrap(model.jobs[0].archiveURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        XCTAssertEqual(archive.deletingLastPathComponent().standardizedFileURL, URL(fileURLWithPath: settings.archivePath, isDirectory: true).standardizedFileURL)
        XCTAssertEqual(archive.lastPathComponent, "queued.webm")
        let archiveContents = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: settings.archivePath, isDirectory: true),
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        XCTAssertFalse(try archiveContents.contains { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true })

        let probe = try await runner.runFFprobe(arguments: [
            "-v", "error", "-show_entries", "stream=codec_name", "-of", "csv=p=0", target.path
        ])
        XCTAssertTrue(probe.standardOutput.contains("h264"))
    }

    func testExistingFlatArchiveNameFailsBeforeConversionAndPreservesSource() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacConvertArchiveCollisionTests-\(UUID().uuidString)", isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
        let archiveDirectory = root.appendingPathComponent("Originals", isDirectory: true)
        let temporaryDirectory = root.appendingPathComponent("Temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = sourceDirectory.appendingPathComponent("duplicate.webm")
        let executables = try testExecutables()
        let runner = FFmpegRunner(executables: executables)
        _ = try await runner.runFFmpeg(arguments: [
            "-hide_banner", "-v", "error", "-y",
            "-f", "lavfi", "-i", "testsrc2=size=64x64:rate=12:duration=0.5",
            "-c:v", "libvpx-vp9", source.path
        ])
        let existingArchive = archiveDirectory.appendingPathComponent(source.lastPathComponent)
        try Data("existing original".utf8).write(to: existingArchive)

        let worker = ConversionWorker(executables: executables)
        let job = ConversionJob(sourceURL: source, mediaKind: .video, profile: .standard)
        do {
            _ = try await worker.process(
                job: job,
                locations: ConversionLocations(
                    temporaryRoot: temporaryDirectory,
                    archiveRoot: archiveDirectory,
                    outputMode: .besideSource,
                    outputRoot: root
                ),
                onUpdate: { _ in }
            )
            XCTFail("The job should fail when its flat archive filename already exists")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "An original named duplicate.webm already exists in the Originals folder"
            )
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceDirectory.appendingPathComponent("duplicate.mp4").path))
        XCTAssertEqual(try Data(contentsOf: existingArchive), Data("existing original".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("duplicate.webm").path))
    }

    func testStaticWebPConvertsToSinglePNGWithoutSequenceWarning() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacConvertWebPTests-\(UUID().uuidString)", isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
        let archiveDirectory = root.appendingPathComponent("Originals", isDirectory: true)
        let temporaryDirectory = root.appendingPathComponent("Temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = sourceDirectory.appendingPathComponent("picture.webp")
        let executables = try testExecutables()
        let runner = FFmpegRunner(executables: executables)
        _ = try await runner.runFFmpeg(arguments: [
            "-hide_banner", "-v", "error", "-y",
            "-f", "lavfi", "-i", "color=c=royalblue:size=80x60",
            "-frames:v", "1", "-c:v", "libwebp", "-lossless", "1", "-f", "webp", source.path
        ])

        let worker = ConversionWorker(executables: executables)
        let result = try await worker.process(
            job: ConversionJob(sourceURL: source, mediaKind: .picture, profile: .standard),
            locations: ConversionLocations(
                temporaryRoot: temporaryDirectory,
                archiveRoot: archiveDirectory,
                outputMode: .besideSource,
                outputRoot: root
            ),
            onUpdate: { _ in }
        )

        XCTAssertEqual(result.targetURL.lastPathComponent, "picture.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.targetURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.archiveURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(result.technicalLog.contains("does not contain an image sequence pattern"))
        let probe = try await runner.runFFprobe(arguments: [
            "-v", "error", "-show_entries", "stream=codec_name", "-of", "csv=p=0", result.targetURL.path
        ])
        XCTAssertTrue(probe.standardOutput.contains("png"))
    }

    func testBundledIsTheDefaultFFmpegSource() {
        let suiteName = "MacConvertTests.FFmpegSource.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.ffmpegSourceMode, .bundled)
    }

    func testPATHSourceResolvesBothExecutablesFromTheSpecifiedSearchPath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacConvertPATHTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let ffmpeg = directory.appendingPathComponent("ffmpeg")
        let ffprobe = directory.appendingPathComponent("ffprobe")
        XCTAssertTrue(FileManager.default.createFile(atPath: ffmpeg.path, contents: Data("#!/bin/sh\n".utf8)))
        XCTAssertTrue(FileManager.default.createFile(atPath: ffprobe.path, contents: Data("#!/bin/sh\n".utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffmpeg.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffprobe.path)

        let executables = try FFmpegExecutables.inPath(environment: ["PATH": directory.path])
        XCTAssertEqual(executables.ffmpeg, ffmpeg)
        XCTAssertEqual(executables.ffprobe, ffprobe)
    }

    func testCustomSourceRejectsANonExecutablePath() {
        XCTAssertThrowsError(
            try FFmpegExecutables.custom(ffmpegPath: "/not/an/executable", ffprobePath: "/also/missing")
        )
    }

    private func testExecutables() throws -> FFmpegExecutables {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try .custom(
            ffmpegPath: projectRoot.appendingPathComponent("MacConvert/Resources/Tools/ffmpeg").path,
            ffprobePath: projectRoot.appendingPathComponent("MacConvert/Resources/Tools/ffprobe").path
        )
    }
}
