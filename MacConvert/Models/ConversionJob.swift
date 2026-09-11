import Foundation

enum MediaKind: String, Codable, Hashable, Sendable {
    case video
    case picture
    case audio
    case unsupported
}

enum JobState: String, Codable, Hashable, Sendable {
    case queued
    case inspecting
    case awaitingFilename
    case copyingLocally
    case converting
    case validatingLocally
    case publishing
    case validatingDestination
    case archivingOriginal
    case removingSource
    case successful
    case successfulWithWarning
    case failed
    case cancelled

    var isActive: Bool {
        switch self {
        case .inspecting, .copyingLocally, .converting, .validatingLocally,
             .publishing, .validatingDestination, .archivingOriginal, .removingSource:
            true
        default:
            false
        }
    }

    var isFinished: Bool {
        switch self {
        case .successful, .successfulWithWarning, .failed, .cancelled: true
        default: false
        }
    }

    var displayName: String {
        switch self {
        case .queued: "Queued"
        case .inspecting: "Inspecting"
        case .awaitingFilename: "Waiting for a filename"
        case .copyingLocally: "Copying locally"
        case .converting: "Converting"
        case .validatingLocally: "Validating"
        case .publishing: "Publishing output"
        case .validatingDestination: "Checking destination"
        case .archivingOriginal: "Archiving original"
        case .removingSource: "Removing source"
        case .successful: "Successful"
        case .successfulWithWarning: "Successful with warning"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    var symbolName: String {
        switch self {
        case .successful: "checkmark.circle.fill"
        case .successfulWithWarning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        case .cancelled: "minus.circle.fill"
        case .queued: "clock"
        default: "arrow.triangle.2.circlepath"
        }
    }
}

enum SameFormatPolicy: String, Codable, Hashable, Sendable {
    case reject
    case replaceSource
}

struct ConversionJob: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let sourceURL: URL
    let mediaKind: MediaKind
    let profile: ConversionProfile
    let sameFormatPolicy: SameFormatPolicy
    let locations: ConversionLocations?
    let createdAt: Date
    var sourceFileSizeBytes: Int64?
    var targetURL: URL?
    var archiveURL: URL?
    var state: JobState
    var progress: Double?
    var statusDetail: String
    var warnings: [String]
    var technicalLog: String

    init(
        sourceURL: URL,
        mediaKind: MediaKind,
        profile: ConversionProfile,
        sameFormatPolicy: SameFormatPolicy = .reject,
        locations: ConversionLocations? = nil
    ) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.mediaKind = mediaKind
        self.profile = profile
        self.sameFormatPolicy = sameFormatPolicy
        self.locations = locations
        self.createdAt = Date()
        self.sourceFileSizeBytes = nil
        self.state = .queued
        self.statusDetail = "Waiting to be inspected"
        self.warnings = []
        self.technicalLog = ""
    }

    var profileSummary: String {
        switch mediaKind {
        case .video:
            "\(sourceURL.pathExtension.uppercased()) → \(profile.videoContainer.displayName) • \(profile.videoEncoder.displayName) • \(profile.audioEncoder.displayName) • \(profile.videoQuality.displayName)"
        case .picture:
            "\(sourceURL.pathExtension.uppercased()) → \(profile.pictureFormat.displayName) • \(profile.pictureQuality.displayName)"
        case .audio:
            "\(sourceURL.pathExtension.uppercased()) → \(profile.audioContainer.displayName) • \(profile.audioOutputEncoder.displayName) • \(profile.audioQuality.displayName)"
        case .unsupported:
            "Unsupported file"
        }
    }

    var sourceFileSizeDisplay: String {
        guard let sourceFileSizeBytes, sourceFileSizeBytes >= 0 else { return "Size unavailable" }
        let bytes = Double(sourceFileSizeBytes)
        if bytes >= 1_000_000_000 {
            return Self.formatted(bytes / 1_000_000_000, unit: "GB")
        }
        let megabytes = bytes / 1_000_000
        if megabytes < 0.01 { return "< 0.01 MB" }
        return Self.formatted(megabytes, unit: "MB")
    }

    private static func formatted(_ value: Double, unit: String) -> String {
        let decimals = value >= 100 ? 0 : value >= 10 ? 1 : 2
        let number = value.formatted(
            .number.precision(.fractionLength(0...decimals))
        )
        return "\(number) \(unit)"
    }
}
