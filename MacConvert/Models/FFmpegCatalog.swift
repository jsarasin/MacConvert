import Foundation

struct FFmpegMuxer: Hashable, Identifiable, Sendable {
    let id: String
    let description: String
}

struct FFmpegEncoder: Hashable, Identifiable, Sendable {
    let id: String
    let description: String
    let codecID: String
    let mediaKind: EncoderMediaKind
    let isHardwareAccelerated: Bool
}

struct FFmpegCatalog: Sendable {
    let version: String
    let buildConfiguration: String
    let muxers: [FFmpegMuxer]
    let encoders: [FFmpegEncoder]

    static let empty = FFmpegCatalog(version: "", buildConfiguration: "", muxers: [], encoders: [])

    var muxerIDs: Set<String> { Set(muxers.map(\.id)) }
}

enum FFmpegCatalogParser {
    static func parseMuxers(_ output: String) -> [FFmpegMuxer] {
        var results: [FFmpegMuxer] = []

        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard fields.count == 3, fields[0].contains("E") else { continue }

            let description = String(fields[2])
            for name in fields[1].split(separator: ",") {
                results.append(FFmpegMuxer(id: String(name), description: description))
            }
        }

        return unique(results).sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    static func parseEncoders(_ output: String) -> [FFmpegEncoder] {
        var results: [FFmpegEncoder] = []

        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard fields.count == 3 else { continue }

            let flags = fields[0]
            let mediaKind: EncoderMediaKind
            if flags.first == "V" {
                mediaKind = .video
            } else if flags.first == "A" {
                mediaKind = .audio
            } else {
                continue
            }

            let id = String(fields[1])
            let description = String(fields[2])
            results.append(
                FFmpegEncoder(
                    id: id,
                    description: description,
                    codecID: codecID(from: description, fallback: id),
                    mediaKind: mediaKind,
                    isHardwareAccelerated: description.localizedCaseInsensitiveContains("hardware")
                )
            )
        }

        return unique(results).sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    static func parseVersion(_ output: String) -> String {
        guard let firstLine = output.split(whereSeparator: \.isNewline).first else { return "Unknown" }
        let words = firstLine.split(whereSeparator: \.isWhitespace)
        guard let versionIndex = words.firstIndex(of: "version"), words.indices.contains(versionIndex + 1) else {
            return String(firstLine)
        }
        return String(words[versionIndex + 1])
    }

    private static func codecID(from description: String, fallback: String) -> String {
        guard let marker = description.range(of: "(codec "),
              let end = description[marker.upperBound...].firstIndex(of: ")") else {
            return fallback
        }
        return String(description[marker.upperBound..<end])
    }

    private static func unique<T: Identifiable & Hashable>(_ values: [T]) -> [T] where T.ID: Hashable {
        var seen: Set<T.ID> = []
        return values.filter { seen.insert($0.id).inserted }
    }
}

enum FFmpegCompatibility {
    static let popularContainerIDs: Set<String> = ["mp4", "mov", "matroska", "webm"]
    static let popularAudioContainerIDs: Set<String> = ["ipod", "mp3", "flac", "ogg", "opus", "wav", "caf"]
    static let audioContainerIDs: Set<String> = popularAudioContainerIDs.union([
        "adts", "ac3", "eac3", "aiff", "amr", "au", "matroska", "webm", "w64"
    ])
    static let popularVideoCodecIDs: Set<String> = ["h264", "hevc", "av1", "vp9", "prores"]
    static let popularAudioCodecIDs: Set<String> = ["aac", "opus", "mp3", "flac", "alac"]

    static func supports(containerID: String, codecID: String, mediaKind: EncoderMediaKind) -> Bool {
        switch containerID {
        case "mp4":
            return mediaKind == .video
                ? ["h264", "hevc", "av1", "mpeg4"].contains(codecID)
                : ["aac", "alac", "mp3", "ac3", "eac3"].contains(codecID)
        case "mov":
            return mediaKind == .video
                ? ["h264", "hevc", "av1", "prores", "mpeg4"].contains(codecID)
                : ["aac", "alac", "mp3", "pcm_s16le", "pcm_s24le", "ac3"].contains(codecID)
        case "webm":
            return mediaKind == .video
                ? ["vp8", "vp9", "av1"].contains(codecID)
                : ["opus", "vorbis"].contains(codecID)
        case "matroska":
            return true
        case "ipod":
            return mediaKind == .audio && ["aac", "alac"].contains(codecID)
        case "mp3":
            return mediaKind == .audio && codecID == "mp3"
        case "flac":
            return mediaKind == .audio && codecID == "flac"
        case "ogg":
            return mediaKind == .audio && ["opus", "vorbis", "flac"].contains(codecID)
        case "opus":
            return mediaKind == .audio && codecID == "opus"
        case "wav":
            return mediaKind == .audio && (codecID.hasPrefix("pcm_") || ["mp3", "aac"].contains(codecID))
        case "caf":
            return mediaKind == .audio && (codecID.hasPrefix("pcm_") || ["aac", "alac"].contains(codecID))
        default:
            return true
        }
    }
}
