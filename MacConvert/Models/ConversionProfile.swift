import Foundation

enum EncoderMediaKind: String, Codable, Hashable, Sendable {
    case video
    case audio
}

struct ContainerOption: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let fileExtension: String
    let isPopular: Bool

    static let mp4 = ContainerOption(id: "mp4", displayName: "MP4", fileExtension: "mp4", isPopular: true)
    static let mov = ContainerOption(id: "mov", displayName: "MOV", fileExtension: "mov", isPopular: true)
    static let matroska = ContainerOption(id: "matroska", displayName: "Matroska (MKV)", fileExtension: "mkv", isPopular: true)
    static let webM = ContainerOption(id: "webm", displayName: "WebM", fileExtension: "webm", isPopular: true)
    static let m4a = ContainerOption(id: "ipod", displayName: "M4A", fileExtension: "m4a", isPopular: true)
    static let mp3 = ContainerOption(id: "mp3", displayName: "MP3", fileExtension: "mp3", isPopular: true)
    static let flac = ContainerOption(id: "flac", displayName: "FLAC", fileExtension: "flac", isPopular: true)
    static let ogg = ContainerOption(id: "ogg", displayName: "Ogg", fileExtension: "ogg", isPopular: true)
    static let opus = ContainerOption(id: "opus", displayName: "Opus", fileExtension: "opus", isPopular: true)
    static let wav = ContainerOption(id: "wav", displayName: "WAV", fileExtension: "wav", isPopular: true)
    static let caf = ContainerOption(id: "caf", displayName: "CAF", fileExtension: "caf", isPopular: true)
}

struct EncoderOption: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let codecID: String
    let mediaKind: EncoderMediaKind
    let isPopular: Bool
    let isHardwareAccelerated: Bool

    static let h264 = EncoderOption(
        id: "ffmpeg_default_h264",
        displayName: "H.264 (FFmpeg Default)",
        codecID: "h264",
        mediaKind: .video,
        isPopular: true,
        isHardwareAccelerated: false
    )
    static let aac = EncoderOption(
        id: "aac",
        displayName: "AAC-LC",
        codecID: "aac",
        mediaKind: .audio,
        isPopular: true,
        isHardwareAccelerated: false
    )
}

struct PictureFormatOption: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let stillExtension: String
    let animatedExtension: String?
    let ffmpegMuxerID: String?
    let isPopular: Bool

    var supportsAnimation: Bool { animatedExtension != nil }

    func fileExtension(isAnimated: Bool) -> String {
        if isAnimated, let animatedExtension { return animatedExtension }
        return stillExtension
    }

    static let pngAPNG = PictureFormatOption(
        id: "png_apng",
        displayName: "PNG / APNG",
        stillExtension: "png",
        animatedExtension: "apng",
        ffmpegMuxerID: nil,
        isPopular: true
    )
    static let gif = PictureFormatOption(
        id: "gif",
        displayName: "GIF",
        stillExtension: "gif",
        animatedExtension: "gif",
        ffmpegMuxerID: "gif",
        isPopular: true
    )
    static let jpeg = PictureFormatOption(
        id: "image2_jpeg",
        displayName: "JPEG",
        stillExtension: "jpg",
        animatedExtension: nil,
        ffmpegMuxerID: "image2",
        isPopular: true
    )
    static let webP = PictureFormatOption(
        id: "webp",
        displayName: "WebP",
        stillExtension: "webp",
        animatedExtension: "webp",
        ffmpegMuxerID: "webp",
        isPopular: true
    )
    static let tiff = PictureFormatOption(
        id: "image2_tiff",
        displayName: "TIFF",
        stillExtension: "tiff",
        animatedExtension: nil,
        ffmpegMuxerID: "image2",
        isPopular: true
    )
}

enum QualityPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case preserveQuality
    case smallFile
    case tinyFile
    case custom

    var id: Self { self }

    var displayName: String {
        switch self {
        case .preserveQuality: "Preserve Quality"
        case .smallFile: "Small File"
        case .tinyFile: "Tiny File"
        case .custom: "Custom…"
        }
    }
}

struct ConversionProfile: Codable, Hashable, Sendable {
    var videoContainer: ContainerOption
    var videoEncoder: EncoderOption
    var audioEncoder: EncoderOption
    var videoQuality: QualityPreset
    var pictureFormat: PictureFormatOption
    var pictureQuality: QualityPreset
    var audioContainer: ContainerOption
    var audioOutputEncoder: EncoderOption
    var audioQuality: QualityPreset

    static let standard = ConversionProfile(
        videoContainer: .mp4,
        videoEncoder: .h264,
        audioEncoder: .aac,
        videoQuality: .preserveQuality,
        pictureFormat: .pngAPNG,
        pictureQuality: .preserveQuality,
        audioContainer: .m4a,
        audioOutputEncoder: .aac,
        audioQuality: .preserveQuality
    )
}
