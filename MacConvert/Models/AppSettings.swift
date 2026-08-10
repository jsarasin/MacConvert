import Foundation
import Observation

enum OutputDestinationMode: String, CaseIterable, Identifiable, Sendable {
    case besideSource
    case chosenFolder

    var id: Self { self }
    var displayName: String { self == .besideSource ? "Beside Source" : "Chosen Folder" }
}

enum FFmpegSourceMode: String, CaseIterable, Identifiable, Sendable {
    case bundled
    case path
    case custom

    var id: Self { self }

    var displayName: String {
        switch self {
        case .bundled: "Bundled (Recommended)"
        case .path: "Search $PATH"
        case .custom: "Custom Locations"
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var showAllSupportedFormats: Bool { didSet { save() } }
    var archivePath: String { didSet { save() } }
    var temporaryPath: String { didSet { save() } }
    var outputPath: String { didSet { save() } }
    var outputDestinationMode: OutputDestinationMode { didSet { save() } }
    var startImmediately: Bool { didSet { save() } }
    var continueAfterFailure: Bool { didSet { save() } }
    var preventSleep: Bool { didSet { save() } }
    var notifyWhenFinished: Bool { didSet { save() } }
    var rememberHistory: Bool { didSet { save() } }
    var confirmCancellation: Bool { didSet { save() } }
    var maximumConcurrentJobs: Int { didSet { save() } }
    var ffmpegSourceMode: FFmpegSourceMode { didSet { save() } }
    var customFFmpegPath: String { didSet { save() } }
    var customFFprobePath: String { didSet { save() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let defaultArchive = URL(fileURLWithPath: home).appendingPathComponent("MacConverted").path
        let defaultTemporary = URL(fileURLWithPath: defaultArchive).appendingPathComponent("temp").path

        showAllSupportedFormats = defaults.bool(forKey: "showAllSupportedFormats")
        archivePath = defaults.string(forKey: "archivePath") ?? defaultArchive
        temporaryPath = defaults.string(forKey: "temporaryPath") ?? defaultTemporary
        outputPath = defaults.string(forKey: "outputPath") ?? home
        outputDestinationMode = OutputDestinationMode(rawValue: defaults.string(forKey: "outputDestinationMode") ?? "") ?? .besideSource
        startImmediately = defaults.object(forKey: "startImmediately") as? Bool ?? true
        continueAfterFailure = defaults.object(forKey: "continueAfterFailure") as? Bool ?? true
        preventSleep = defaults.object(forKey: "preventSleep") as? Bool ?? true
        notifyWhenFinished = defaults.object(forKey: "notifyWhenFinished") as? Bool ?? true
        rememberHistory = defaults.object(forKey: "rememberHistory") as? Bool ?? true
        confirmCancellation = defaults.object(forKey: "confirmCancellation") as? Bool ?? true
        maximumConcurrentJobs = max(1, defaults.integer(forKey: "maximumConcurrentJobs"))
        ffmpegSourceMode = FFmpegSourceMode(rawValue: defaults.string(forKey: "ffmpegSourceMode") ?? "") ?? .bundled
        customFFmpegPath = defaults.string(forKey: "customFFmpegPath") ?? ""
        customFFprobePath = defaults.string(forKey: "customFFprobePath") ?? ""
    }

    func restoreLocationDefaults() {
        let archive = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("MacConverted")
        archivePath = archive.path
        temporaryPath = archive.appendingPathComponent("temp").path
        outputDestinationMode = .besideSource
    }

    private func save() {
        defaults.set(showAllSupportedFormats, forKey: "showAllSupportedFormats")
        defaults.set(archivePath, forKey: "archivePath")
        defaults.set(temporaryPath, forKey: "temporaryPath")
        defaults.set(outputPath, forKey: "outputPath")
        defaults.set(outputDestinationMode.rawValue, forKey: "outputDestinationMode")
        defaults.set(startImmediately, forKey: "startImmediately")
        defaults.set(continueAfterFailure, forKey: "continueAfterFailure")
        defaults.set(preventSleep, forKey: "preventSleep")
        defaults.set(notifyWhenFinished, forKey: "notifyWhenFinished")
        defaults.set(rememberHistory, forKey: "rememberHistory")
        defaults.set(confirmCancellation, forKey: "confirmCancellation")
        defaults.set(maximumConcurrentJobs, forKey: "maximumConcurrentJobs")
        defaults.set(ffmpegSourceMode.rawValue, forKey: "ffmpegSourceMode")
        defaults.set(customFFmpegPath, forKey: "customFFmpegPath")
        defaults.set(customFFprobePath, forKey: "customFFprobePath")
    }
}
