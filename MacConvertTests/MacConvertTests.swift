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

    func testFinderLocationsFollowJobFilesAndStatus() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacConvertFinderLocationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("movie.webm")
        let archive = root.appendingPathComponent("movie_1786401234567.webm")
        let replacement = root.appendingPathComponent("movie.mp4")
        try Data("source".utf8).write(to: source)

        var job = ConversionJob(sourceURL: source, mediaKind: .video, profile: .standard)
        job.targetURL = replacement
        var locations = FinderService.existingLocations(for: job)
        XCTAssertEqual(locations.original, source)
        XCTAssertNil(locations.replacement)

        try Data("archive".utf8).write(to: archive)
        try Data("replacement".utf8).write(to: replacement)
        try FileManager.default.removeItem(at: source)
        job.archiveURL = archive
        job.state = .successful
        locations = FinderService.existingLocations(for: job)
        XCTAssertEqual(locations.original, archive)
        XCTAssertEqual(locations.replacement, replacement)
    }

    func testSuccessfulSameFormatReplacementWithoutBackupHasNoOriginalFinderLocation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacConvertFinderReplacementTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let replacement = root.appendingPathComponent("movie.mp4")
        try Data("replacement".utf8).write(to: replacement)
        var profile = ConversionProfile.standard
        profile.videoQuality = .smallFile
        var job = ConversionJob(
            sourceURL: replacement,
            mediaKind: .video,
            profile: profile,
            sameFormatPolicy: .replaceSource
        )
        job.targetURL = replacement
        job.state = .successful

        let locations = FinderService.existingLocations(for: job)

        XCTAssertNil(locations.original)
        XCTAssertEqual(locations.replacement, replacement)

        for state in [JobState.failed, .cancelled] {
            job.state = state
            let restoredLocations = FinderService.existingLocations(for: job)
            XCTAssertEqual(restoredLocations.original, replacement)
            XCTAssertNil(restoredLocations.replacement)
        }
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

    func testLocationDefaultsUseSystemTemporaryStorageWithoutOriginalBackups() {
        let suiteName = "MacConvertTests.LocationDefaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.backupOriginals)
        XCTAssertTrue(settings.archivePath.isEmpty)
        XCTAssertEqual(settings.outputDestinationMode, .besideSource)
        XCTAssertEqual(
            URL(fileURLWithPath: settings.temporaryPath).standardizedFileURL,
            FileManager.default.temporaryDirectory.appendingPathComponent("MacConvert").standardizedFileURL
        )
    }

    func testLegacyLocationSettingsDoNotEnableBackupsOrRetainCustomTemporaryStorage() {
        let suiteName = "MacConvertTests.LegacyLocations.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("/legacy/MacConverted", forKey: "archivePath")
        defaults.set("/legacy/MacConverted/temp", forKey: "temporaryPath")

        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.backupOriginals)
        XCTAssertEqual(settings.archivePath, "/legacy/MacConverted")
        XCTAssertEqual(
            URL(fileURLWithPath: settings.temporaryPath).standardizedFileURL,
            FileManager.default.temporaryDirectory.appendingPathComponent("MacConvert").standardizedFileURL
        )
        XCTAssertNil(defaults.object(forKey: "temporaryPath"))
    }

    func testBackupOptInPersistsAndRestoringLocationsDisablesIt() {
        let suiteName = "MacConvertTests.RestoreLocations.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.archivePath = "/chosen/Originals"
        settings.backupOriginals = true
        settings.outputDestinationMode = .chosenFolder

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertTrue(reloaded.backupOriginals)
        XCTAssertEqual(reloaded.archivePath, "/chosen/Originals")
        reloaded.restoreLocationDefaults()

        let restored = AppSettings(defaults: defaults)
        XCTAssertFalse(restored.backupOriginals)
        XCTAssertTrue(restored.archivePath.isEmpty)
        XCTAssertEqual(restored.outputDestinationMode, .besideSource)
    }

    func testQueuedJobsKeepTheirOriginalBackupAndOutputLocationSettings() throws {
        let model = makeStoppedModel(suite: "LocationSnapshots")
        model.addFiles([URL(fileURLWithPath: "/tmp/without-backup.webm")])
        let firstLocations = try XCTUnwrap(model.jobs.first?.locations)
        XCTAssertNil(firstLocations.archiveRoot)
        XCTAssertEqual(firstLocations.outputMode, .besideSource)

        model.settings.backupOriginals = true
        model.settings.archivePath = "/chosen/Originals"
        model.settings.outputDestinationMode = .chosenFolder
        model.settings.outputPath = "/chosen/Output"
        model.addFiles([URL(fileURLWithPath: "/tmp/with-backup.webm")])
        let secondLocations = try XCTUnwrap(model.jobs.last?.locations)
        XCTAssertEqual(secondLocations.archiveRoot?.path, "/chosen/Originals")
        XCTAssertEqual(secondLocations.outputMode, .chosenFolder)
        XCTAssertEqual(secondLocations.outputRoot.path, "/chosen/Output")

        model.settings.restoreLocationDefaults()
        XCTAssertEqual(model.jobs[0].locations, firstLocations)
        XCTAssertEqual(model.jobs[1].locations, secondLocations)
        let restoredJob = try JSONDecoder().decode(
            ConversionJob.self,
            from: JSONEncoder().encode(model.jobs[1])
        )
        XCTAssertEqual(restoredJob.locations, secondLocations)
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

    func testPreserveQualityStillRejectsAFileAlreadyInTheTargetFormat() {
        let model = makeStoppedModel(suite: "PreserveSameFormat")

        model.addFiles([URL(fileURLWithPath: "/tmp/already.mp4")])

        XCTAssertEqual(model.jobs.count, 1)
        XCTAssertEqual(model.jobs[0].state, .failed)
        XCTAssertEqual(model.jobs[0].statusDetail, "File is already in the selected output format")
        XCTAssertNil(model.sameFormatWarning)
    }

    func testNonPreserveQualityWaitsForSameFormatDecision() {
        let model = makeStoppedModel(suite: "PromptSameFormat")
        model.selectedVideoQuality = .smallFile

        model.addFiles([URL(fileURLWithPath: "/tmp/reencode.mp4")])

        XCTAssertTrue(model.jobs.isEmpty)
        XCTAssertEqual(model.sameFormatWarning?.sourceURL.lastPathComponent, "reencode.mp4")
        XCTAssertEqual(model.sameFormatWarning?.remainingFileCount, 1)
    }

    func testReplaceThisFileUsesTheProfileCapturedWhenTheBatchWasAdded() async throws {
        let model = makeStoppedModel(suite: "ReplaceOneSameFormat")
        model.selectedVideoQuality = .smallFile
        model.settings.backupOriginals = true
        model.settings.archivePath = "/chosen/Originals"
        model.addFiles([URL(fileURLWithPath: "/tmp/reencode.mp4")])
        let warning = try XCTUnwrap(model.sameFormatWarning)

        model.selectedVideoQuality = .tinyFile
        model.settings.restoreLocationDefaults()
        model.resolveSameFormatWarning(warning.id, decision: .replaceThisFile)
        await Task.yield()

        XCTAssertNil(model.sameFormatWarning)
        XCTAssertEqual(model.jobs.count, 1)
        XCTAssertEqual(model.jobs[0].profile.videoQuality, .smallFile)
        XCTAssertEqual(model.jobs[0].sameFormatPolicy, .replaceSource)
        XCTAssertEqual(model.jobs[0].state, .queued)
        XCTAssertEqual(model.jobs[0].locations?.archiveRoot?.path, "/chosen/Originals")
    }

    func testSkipThisFileAdvancesToTheNextMatchingFile() async throws {
        let model = makeStoppedModel(suite: "SkipOneSameFormat")
        model.selectedVideoQuality = .smallFile
        model.addFiles([
            URL(fileURLWithPath: "/tmp/skip.mp4"),
            URL(fileURLWithPath: "/tmp/keep.mp4")
        ])
        let firstWarning = try XCTUnwrap(model.sameFormatWarning)

        model.resolveSameFormatWarning(firstWarning.id, decision: .skipThisFile)
        for _ in 0..<10 where model.sameFormatWarning == nil {
            await Task.yield()
        }
        let secondWarning = try XCTUnwrap(model.sameFormatWarning)

        XCTAssertEqual(secondWarning.sourceURL.lastPathComponent, "keep.mp4")
        XCTAssertEqual(secondWarning.remainingFileCount, 1)
        XCTAssertTrue(model.jobs.isEmpty)

        model.resolveSameFormatWarning(secondWarning.id, decision: .replaceThisFile)
        await Task.yield()
        XCTAssertEqual(model.jobs.map(\.sourceURL.lastPathComponent), ["keep.mp4"])
    }

    func testSkipAndReplaceAllApplyOnlyToTheCurrentAddedBatch() async throws {
        let model = makeStoppedModel(suite: "AllSameFormat")
        model.selectedVideoQuality = .tinyFile
        model.addFiles([
            URL(fileURLWithPath: "/tmp/one.mp4"),
            URL(fileURLWithPath: "/tmp/two.mp4")
        ])
        let firstWarning = try XCTUnwrap(model.sameFormatWarning)
        model.resolveSameFormatWarning(firstWarning.id, decision: .replaceAll)
        await Task.yield()

        XCTAssertEqual(model.jobs.map(\.sourceURL.lastPathComponent), ["one.mp4", "two.mp4"])
        XCTAssertNil(model.sameFormatWarning)

        model.addFiles([URL(fileURLWithPath: "/tmp/three.mp4")])
        let secondWarning = try XCTUnwrap(model.sameFormatWarning)
        model.resolveSameFormatWarning(secondWarning.id, decision: .skipAll)
        await Task.yield()

        XCTAssertEqual(model.jobs.map(\.sourceURL.lastPathComponent), ["one.mp4", "two.mp4"])
        XCTAssertNil(model.sameFormatWarning)
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(result.archiveURL).path))
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
        settings.backupOriginals = true
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
        XCTAssertNotNil(
            archive.lastPathComponent.range(
                of: #"^queued_[0-9]{13}\.webm$"#,
                options: .regularExpression
            )
        )
        let archiveContents = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: settings.archivePath, isDirectory: true),
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        XCTAssertFalse(try archiveContents.contains { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true })
        let workDirectory = URL(fileURLWithPath: settings.temporaryPath, isDirectory: true)
            .appendingPathComponent("macconvert-\(model.jobs[0].id.uuidString)", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workDirectory.path))

        let probe = try await runner.runFFprobe(arguments: [
            "-v", "error", "-show_entries", "stream=codec_name", "-of", "csv=p=0", target.path
        ])
        XCTAssertTrue(probe.standardOutput.contains("h264"))
    }

    func testExistingOriginalFilenameDoesNotCollideWithTimestampedArchive() async throws {
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
        let result = try await worker.process(
            job: job,
            locations: ConversionLocations(
                temporaryRoot: temporaryDirectory,
                archiveRoot: archiveDirectory,
                outputMode: .besideSource,
                outputRoot: root
            ),
            onUpdate: { _ in }
        )

        let expectedTimestamp = Int64((job.createdAt.timeIntervalSince1970 * 1_000).rounded(.down))
        XCTAssertEqual(try XCTUnwrap(result.archiveURL).lastPathComponent, "duplicate_\(expectedTimestamp).webm")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceDirectory.appendingPathComponent("duplicate.mp4").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(result.archiveURL).path))
        XCTAssertEqual(try Data(contentsOf: existingArchive), Data("existing original".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("duplicate_\(expectedTimestamp).webm").path))
    }

    func testApprovedSameFormatConversionArchivesThenReplacesTheOriginal() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacConvertSameFormatReplacementTests-\(UUID().uuidString)", isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
        let archiveDirectory = root.appendingPathComponent("Originals", isDirectory: true)
        let temporaryDirectory = root.appendingPathComponent("Temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = sourceDirectory.appendingPathComponent("same.mp4")
        let executables = try testExecutables()
        let runner = FFmpegRunner(executables: executables)
        _ = try await runner.runFFmpeg(arguments: [
            "-hide_banner", "-v", "error", "-y",
            "-f", "lavfi", "-i", "testsrc2=size=96x54:rate=12:duration=0.5",
            "-c:v", "libx264", "-crf", "12", "-pix_fmt", "yuv420p", source.path
        ])
        let originalData = try Data(contentsOf: source)
        var profile = ConversionProfile.standard
        profile.videoQuality = .tinyFile
        let job = ConversionJob(
            sourceURL: source,
            mediaKind: .video,
            profile: profile,
            sameFormatPolicy: .replaceSource
        )

        let worker = ConversionWorker(executables: executables)
        let result = try await worker.process(
            job: job,
            locations: ConversionLocations(
                temporaryRoot: temporaryDirectory,
                archiveRoot: archiveDirectory,
                outputMode: .besideSource,
                outputRoot: root
            ),
            onUpdate: { _ in }
        )

        XCTAssertEqual(result.targetURL, source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertNotEqual(try Data(contentsOf: source), originalData)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(result.archiveURL)), originalData)
        let probe = try await runner.runFFprobe(arguments: [
            "-v", "error", "-show_entries", "stream=codec_name", "-of", "csv=p=0", source.path
        ])
        XCTAssertTrue(probe.standardOutput.contains("h264"))
        let sourceDirectoryFiles = try FileManager.default.contentsOfDirectory(atPath: sourceDirectory.path)
        XCTAssertEqual(sourceDirectoryFiles, ["same.mp4"])
    }

    func testConversionWithoutBackupValidatesBeforeDeletingSourceAndCleansTemporaryFiles() async throws {
        let fixture = try await makeVideoFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let worker = ConversionWorker(executables: fixture.executables)
        var states: [JobState] = []

        let result = try await worker.process(
            job: ConversionJob(sourceURL: fixture.source, mediaKind: .video, profile: .standard),
            locations: fixture.locations,
            onUpdate: { update in
                states.append(update.state)
                XCTAssertNil(update.archiveURL)
                XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path))
            }
        )

        XCTAssertNil(result.archiveURL)
        XCTAssertEqual(result.targetURL.lastPathComponent, "sample.mp4")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Originals").path))
        XCTAssertFalse(states.contains(.archivingOriginal))
        let destinationValidation = try XCTUnwrap(states.firstIndex(of: .validatingDestination))
        let sourceRemoval = try XCTUnwrap(states.firstIndex(of: .removingSource))
        XCTAssertLessThan(destinationValidation, sourceRemoval)
        let runner = FFmpegRunner(executables: fixture.executables)
        let probe = try await runner.runFFprobe(arguments: [
            "-v", "error", "-show_entries", "stream=codec_name", "-of", "csv=p=0", result.targetURL.path
        ])
        XCTAssertTrue(probe.standardOutput.contains("h264"))
        try assertTemporaryStorageIsEmpty(fixture.locations.temporaryRoot)
    }

    func testNoBackupCollisionPreservesOriginalAndExistingDestination() async throws {
        let fixture = try await makeVideoFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let target = fixture.source.deletingPathExtension().appendingPathExtension("mp4")
        let existingOutput = Data("unrelated existing output".utf8)
        try existingOutput.write(to: target)
        let worker = ConversionWorker(executables: fixture.executables)

        do {
            _ = try await worker.process(
                job: ConversionJob(sourceURL: fixture.source, mediaKind: .video, profile: .standard),
                locations: fixture.locations,
                onUpdate: { _ in }
            )
            XCTFail("An existing target must fail without replacing any file")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("already exists"))
        }

        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.originalData)
        XCTAssertEqual(try Data(contentsOf: target), existingOutput)
        try assertTemporaryStorageIsEmpty(fixture.locations.temporaryRoot)
    }

    func testNoBackupDestinationValidationFailurePreservesOriginalAndRollsBackOutput() async throws {
        let fixture = try await makeVideoFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let target = fixture.source.deletingPathExtension().appendingPathExtension("mp4")
        let worker = ConversionWorker(executables: fixture.executables)
        var reachedDestinationValidation = false

        do {
            _ = try await worker.process(
                job: ConversionJob(sourceURL: fixture.source, mediaKind: .video, profile: .standard),
                locations: fixture.locations,
                onUpdate: { update in
                    if update.state == .validatingDestination {
                        reachedDestinationValidation = true
                        do {
                            try Data("damaged output".utf8).write(to: target)
                        } catch {
                            XCTFail("Could not damage the test output: \(error)")
                        }
                    }
                }
            )
            XCTFail("An invalid published output must never permit source deletion")
        } catch {
            XCTAssertTrue(reachedDestinationValidation)
        }

        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.originalData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        try assertTemporaryStorageIsEmpty(fixture.locations.temporaryRoot)
    }

    func testNoBackupCancellationBeforeConversionOrSourceDeletionPreservesOriginal() async throws {
        for cancellationState in [JobState.converting, .removingSource] {
            let fixture = try await makeVideoFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let worker = ConversionWorker(executables: fixture.executables)
            let task = Task {
                try await worker.process(
                    job: ConversionJob(sourceURL: fixture.source, mediaKind: .video, profile: .standard),
                    locations: fixture.locations,
                    onUpdate: { update in
                        if update.state == cancellationState {
                            withUnsafeCurrentTask { $0?.cancel() }
                        }
                    }
                )
            }

            do {
                _ = try await task.value
                XCTFail("Cancellation during \(cancellationState) must stop the job")
            } catch {
                XCTAssertTrue(error is CancellationError)
            }

            XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.originalData)
            let target = fixture.source.deletingPathExtension().appendingPathExtension("mp4")
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
            try assertTemporaryStorageIsEmpty(fixture.locations.temporaryRoot)
        }
    }

    func testNoBackupConversionPreservesSourceChangedBeforeDeletion() async throws {
        let fixture = try await makeVideoFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let modifiedSource = Data("new content saved while conversion was running".utf8)
        let worker = ConversionWorker(executables: fixture.executables)
        var reachedSourceRemoval = false

        do {
            _ = try await worker.process(
                job: ConversionJob(sourceURL: fixture.source, mediaKind: .video, profile: .standard),
                locations: fixture.locations,
                onUpdate: { update in
                    if update.state == .removingSource {
                        reachedSourceRemoval = true
                        do {
                            try modifiedSource.write(to: fixture.source)
                        } catch {
                            XCTFail("Could not modify the test source: \(error)")
                        }
                    }
                }
            )
            XCTFail("A source changed during conversion must be retained")
        } catch {
            XCTAssertTrue(reachedSourceRemoval)
            XCTAssertTrue(error.localizedDescription.contains("changed"))
        }

        XCTAssertEqual(try Data(contentsOf: fixture.source), modifiedSource)
        let target = fixture.source.deletingPathExtension().appendingPathExtension("mp4")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        try assertTemporaryStorageIsEmpty(fixture.locations.temporaryRoot)
    }

    func testApprovedSameFormatConversionWithoutBackupReplacesAndCleansOriginalCopies() async throws {
        let fixture = try await makeVideoFixture(fileExtension: "mp4")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var profile = ConversionProfile.standard
        profile.videoQuality = .tinyFile
        let worker = ConversionWorker(executables: fixture.executables)

        let result = try await worker.process(
            job: ConversionJob(
                sourceURL: fixture.source,
                mediaKind: .video,
                profile: profile,
                sameFormatPolicy: .replaceSource
            ),
            locations: fixture.locations,
            onUpdate: { update in XCTAssertNil(update.archiveURL) }
        )

        XCTAssertEqual(result.targetURL, fixture.source)
        XCTAssertNil(result.archiveURL)
        XCTAssertNotEqual(try Data(contentsOf: fixture.source), fixture.originalData)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: fixture.source.deletingLastPathComponent().path),
            ["sample.mp4"]
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Originals").path))
        try assertTemporaryStorageIsEmpty(fixture.locations.temporaryRoot)
    }

    func testNoBackupSameFormatValidationFailureRestoresOriginalAndCleansTemporaryFiles() async throws {
        let fixture = try await makeVideoFixture(fileExtension: "mp4")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var profile = ConversionProfile.standard
        profile.videoQuality = .tinyFile
        let worker = ConversionWorker(executables: fixture.executables)
        var reachedDestinationValidation = false

        do {
            _ = try await worker.process(
                job: ConversionJob(
                    sourceURL: fixture.source,
                    mediaKind: .video,
                    profile: profile,
                    sameFormatPolicy: .replaceSource
                ),
                locations: fixture.locations,
                onUpdate: { update in
                    if update.state == .validatingDestination {
                        reachedDestinationValidation = true
                        do {
                            try Data("damaged replacement".utf8).write(to: fixture.source)
                        } catch {
                            XCTFail("Could not damage the test replacement: \(error)")
                        }
                    }
                }
            )
            XCTFail("A replacement that fails validation must restore the original")
        } catch {
            XCTAssertTrue(reachedDestinationValidation)
        }

        XCTAssertEqual(try Data(contentsOf: fixture.source), fixture.originalData)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: fixture.source.deletingLastPathComponent().path),
            ["sample.mp4"]
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Originals").path))
        try assertTemporaryStorageIsEmpty(fixture.locations.temporaryRoot)
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(result.archiveURL).path))
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

    private struct VideoFixture {
        let root: URL
        let source: URL
        let originalData: Data
        let executables: FFmpegExecutables
        let locations: ConversionLocations
    }

    private func makeVideoFixture(fileExtension: String = "webm") async throws -> VideoFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacConvertNoBackupTests-\(UUID().uuidString)", isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let source = sourceDirectory.appendingPathComponent("sample.\(fileExtension)")
        let executables = try testExecutables()
        let runner = FFmpegRunner(executables: executables)
        let encoding = fileExtension == "mp4"
            ? ["-c:v", "libx264", "-crf", "12", "-pix_fmt", "yuv420p"]
            : ["-c:v", "libvpx-vp9"]
        do {
            _ = try await runner.runFFmpeg(arguments: [
                "-hide_banner", "-v", "error", "-y",
                "-f", "lavfi", "-i", "testsrc2=size=96x54:rate=12:duration=0.5"
            ] + encoding + [source.path])
            return VideoFixture(
                root: root,
                source: source,
                originalData: try Data(contentsOf: source),
                executables: executables,
                locations: ConversionLocations(
                    temporaryRoot: root.appendingPathComponent("Temporary", isDirectory: true),
                    archiveRoot: nil,
                    outputMode: .besideSource,
                    outputRoot: root
                )
            )
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    private func assertTemporaryStorageIsEmpty(
        _ root: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty,
            "Completed, failed, and cancelled jobs must remove their working files",
            file: file,
            line: line
        )
    }

    private func makeStoppedModel(suite suffix: String) -> AppModel {
        let suiteName = "MacConvertTests.\(suffix).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AppSettings(defaults: defaults)
        settings.startImmediately = false
        return AppModel(settings: settings)
    }
}
