import Foundation
import Observation

enum OutputDestinationMode: String, CaseIterable, Identifiable, Codable, Sendable {
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
    var backupOriginals: Bool { didSet { save() } }
    var removeOriginalAfterSuccess: Bool { didSet { save() } }
    var archivePath: String { didSet { save() } }
    var temporaryPath: String {
        FileManager.default.temporaryDirectory.appendingPathComponent("MacConvert", isDirectory: true).path
    }
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

        showAllSupportedFormats = defaults.bool(forKey: "showAllSupportedFormats")
        backupOriginals = defaults.bool(forKey: "backupOriginals")
        removeOriginalAfterSuccess = defaults.object(forKey: "removeOriginalAfterSuccess") as? Bool ?? true
        archivePath = defaults.string(forKey: "archivePath") ?? ""
        defaults.removeObject(forKey: "temporaryPath")
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

    func defaultsData(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func setDefaultsData(_ data: Data?, forKey key: String) {
        defaults.set(data, forKey: key)
    }

    func restoreLocationDefaults() {
        backupOriginals = false
        archivePath = ""
        outputDestinationMode = .besideSource
    }

    private func save() {
        defaults.set(showAllSupportedFormats, forKey: "showAllSupportedFormats")
        defaults.set(backupOriginals, forKey: "backupOriginals")
        defaults.set(removeOriginalAfterSuccess, forKey: "removeOriginalAfterSuccess")
        defaults.set(archivePath, forKey: "archivePath")
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
