#if DEBUG
import Foundation

@MainActor
enum PreviewFixtures {
    static func model(jobs: [ConversionJob] = []) -> AppModel {
        let defaults = UserDefaults(suiteName: "MacConvert.CanvasPreviews")!
        let settings = AppSettings(defaults: defaults)
        settings.startImmediately = false
        settings.archivePath = "/Users/Shared/MacConverted"
        settings.temporaryPath = "/Users/Shared/MacConverted/temp"

        let model = AppModel(settings: settings)
        model.ffmpegCatalog = catalog
        model.ffmpegStatus = "FFmpeg 8.1.2 • Bundled"
        model.hasAttemptedCatalogLoad = true
        model.jobs = jobs
        return model
    }

    static func dropTargetModel() -> AppModel {
        let model = model()
        model.isDropTargeted = true
        return model
    }

    static var catalog: FFmpegCatalog {
        FFmpegCatalog(
            version: "8.1.2",
            buildConfiguration: "Bundled local build with common video, picture, and audio formats",
            muxers: [
                FFmpegMuxer(id: "mp4", description: "MP4 (MPEG-4 Part 14)"),
                FFmpegMuxer(id: "mov", description: "QuickTime / MOV"),
                FFmpegMuxer(id: "matroska", description: "Matroska"),
                FFmpegMuxer(id: "webm", description: "WebM"),
                FFmpegMuxer(id: "ipod", description: "M4A audio"),
                FFmpegMuxer(id: "mp3", description: "MP3 audio"),
                FFmpegMuxer(id: "flac", description: "FLAC audio"),
                FFmpegMuxer(id: "ogg", description: "Ogg"),
                FFmpegMuxer(id: "opus", description: "Ogg Opus"),
                FFmpegMuxer(id: "wav", description: "WAV audio"),
                FFmpegMuxer(id: "caf", description: "Apple CAF"),
                FFmpegMuxer(id: "image2", description: "Image sequence"),
                FFmpegMuxer(id: "apng", description: "Animated PNG"),
                FFmpegMuxer(id: "gif", description: "Animated GIF"),
                FFmpegMuxer(id: "webp", description: "WebP")
            ],
            encoders: [
                encoder("libx264", "H.264", codec: "h264", kind: .video),
                encoder("libx265", "HEVC", codec: "hevc", kind: .video),
                encoder("libsvtav1", "AV1", codec: "av1", kind: .video),
                encoder("libvpx-vp9", "VP9", codec: "vp9", kind: .video),
                encoder("prores_ks", "Apple ProRes", codec: "prores", kind: .video),
                encoder("png", "PNG", codec: "png", kind: .video),
                encoder("apng", "Animated PNG", codec: "apng", kind: .video),
                encoder("gif", "GIF", codec: "gif", kind: .video),
                encoder("mjpeg", "JPEG", codec: "mjpeg", kind: .video),
                encoder("tiff", "TIFF", codec: "tiff", kind: .video),
                encoder("libwebp", "WebP", codec: "webp", kind: .video),
                encoder("aac", "AAC-LC", codec: "aac", kind: .audio),
                encoder("alac", "Apple Lossless", codec: "alac", kind: .audio),
                encoder("libopus", "Opus", codec: "opus", kind: .audio),
                encoder("libmp3lame", "MP3", codec: "mp3", kind: .audio),
                encoder("flac", "FLAC", codec: "flac", kind: .audio)
            ]
        )
    }

    static func job(
        named name: String,
        kind: MediaKind = .video,
        state: JobState,
        progress: Double? = nil,
        detail: String? = nil,
        size: Int64 = 1_536_000_000,
        warnings: [String] = []
    ) -> ConversionJob {
        var job = ConversionJob(
            sourceURL: URL(fileURLWithPath: "/Volumes/Media/\(name)"),
            mediaKind: kind,
            profile: .standard
        )
        job.sourceFileSizeBytes = size
        job.state = state
        job.progress = progress
        job.statusDetail = detail ?? state.displayName
        job.warnings = warnings
        if state == .successful || state == .successfulWithWarning {
            let basename = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
            let outputExtension: String
            switch kind {
            case .video: outputExtension = "mp4"
            case .picture: outputExtension = "png"
            case .audio: outputExtension = "m4a"
            case .unsupported: outputExtension = "output"
            }
            job.targetURL = URL(fileURLWithPath: "/Volumes/Media/\(basename).\(outputExtension)")
            job.archiveURL = URL(fileURLWithPath: "/Users/Shared/MacConverted/\(name)")
        }
        if !warnings.isEmpty {
            job.technicalLog = "The output was validated. Some source data could not be represented by the selected output format."
        }
        return job
    }

    static var representativeJobs: [ConversionJob] {
        [
            job(
                named: "Family Holiday.webm",
                state: .converting,
                progress: 0.46,
                detail: "Converting with FFmpeg",
                size: 4_160_000_000
            ),
            job(
                named: "Website Artwork.webp",
                kind: .picture,
                state: .successfulWithWarning,
                detail: "Successful with warning",
                size: 8_420_000,
                warnings: ["The source color profile was not included in the PNG output"]
            ),
            job(
                named: "Interview.flac",
                kind: .audio,
                state: .queued,
                detail: "Waiting to be inspected",
                size: 624_000_000
            ),
            job(
                named: "Already Converted.mp4",
                state: .failed,
                detail: "File is already in the selected output format",
                size: 1_240_000_000
            )
        ]
    }

    private static func encoder(
        _ id: String,
        _ description: String,
        codec: String,
        kind: EncoderMediaKind
    ) -> FFmpegEncoder {
        FFmpegEncoder(
            id: id,
            description: description,
            codecID: codec,
            mediaKind: kind,
            isHardwareAccelerated: false
        )
    }
}
#endif
