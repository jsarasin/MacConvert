import Foundation

struct ProcessResult: Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

enum FFmpegRunnerError: LocalizedError {
    case missingBundledExecutable(String)
    case executableNotFoundInPath(String, path: String)
    case invalidCustomExecutable(String, path: String)
    case versionMismatch(ffmpeg: String, ffprobe: String)
    case launchFailed(String)
    case commandFailed(executable: String, exitCode: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .missingBundledExecutable(let name):
            "The bundled \(name) executable could not be found. Reinstall MacConvert."
        case .executableNotFoundInPath(let name, let path):
            "Could not find an executable named \(name) in $PATH (\(path))."
        case .invalidCustomExecutable(let name, let path):
            path.isEmpty
                ? "Choose a custom \(name) executable."
                : "The selected \(name) path is not an executable file: \(path)"
        case .versionMismatch(let ffmpeg, let ffprobe):
            "The selected tools do not match: FFmpeg is \(ffmpeg), but ffprobe is \(ffprobe). Choose tools from the same build."
        case .launchFailed(let message):
            "FFmpeg could not be launched: \(message)"
        case .commandFailed(let executable, let exitCode, let message):
            "\(executable) stopped with status \(exitCode): \(message)"
        }
    }
}

struct FFmpegExecutables: Sendable {
    let ffmpeg: URL
    let ffprobe: URL

    static func bundled(in bundle: Bundle = .main) throws -> FFmpegExecutables {
        FFmpegExecutables(
            ffmpeg: try locateBundled("ffmpeg", in: bundle),
            ffprobe: try locateBundled("ffprobe", in: bundle)
        )
    }

    static func inPath(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> FFmpegExecutables {
        let path = environment["PATH"] ?? ""
        return FFmpegExecutables(
            ffmpeg: try locateInPath("ffmpeg", path: path),
            ffprobe: try locateInPath("ffprobe", path: path)
        )
    }

    static func custom(ffmpegPath: String, ffprobePath: String) throws -> FFmpegExecutables {
        FFmpegExecutables(
            ffmpeg: try validateCustom("ffmpeg", path: ffmpegPath),
            ffprobe: try validateCustom("ffprobe", path: ffprobePath)
        )
    }

    private static func locateBundled(_ name: String, in bundle: Bundle) throws -> URL {
        let candidates = [
            bundle.executableURL?.deletingLastPathComponent().appendingPathComponent(name),
            bundle.url(forAuxiliaryExecutable: name),
            bundle.resourceURL?.appendingPathComponent("Tools/\(name)")
        ].compactMap { $0 }

        guard let executable = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw FFmpegRunnerError.missingBundledExecutable(name)
        }
        return executable.resolvingSymlinksInPath()
    }

    private static func locateInPath(_ name: String, path: String) throws -> URL {
        for directory in path.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = URL(fileURLWithPath: String(directory), isDirectory: true).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate.resolvingSymlinksInPath()
            }
        }
        throw FFmpegRunnerError.executableNotFoundInPath(name, path: path)
    }

    private static func validateCustom(_ name: String, path: String) throws -> URL {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath).standardizedFileURL
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              FileManager.default.isExecutableFile(atPath: url.path) else {
            throw FFmpegRunnerError.invalidCustomExecutable(name, path: path)
        }
        return url.resolvingSymlinksInPath()
    }
}

actor FFmpegRunner {
    private let executables: FFmpegExecutables

    init(executables: FFmpegExecutables) {
        self.executables = executables
    }

    func discoverCatalog() throws -> FFmpegCatalog {
        let versionResult = try run(executables.ffmpeg, arguments: ["-hide_banner", "-version"])
        let probeVersionResult = try run(executables.ffprobe, arguments: ["-hide_banner", "-version"])
        let ffmpegVersion = FFmpegCatalogParser.parseVersion(versionResult.standardOutput)
        let ffprobeVersion = FFmpegCatalogParser.parseVersion(probeVersionResult.standardOutput)
        guard ffmpegVersion == ffprobeVersion else {
            throw FFmpegRunnerError.versionMismatch(ffmpeg: ffmpegVersion, ffprobe: ffprobeVersion)
        }
        let muxerResult = try run(executables.ffmpeg, arguments: ["-hide_banner", "-muxers"])
        let encoderResult = try run(executables.ffmpeg, arguments: ["-hide_banner", "-encoders"])
        let buildResult = try run(executables.ffmpeg, arguments: ["-hide_banner", "-buildconf"])

        return FFmpegCatalog(
            version: ffmpegVersion,
            buildConfiguration: buildResult.standardOutput,
            muxers: FFmpegCatalogParser.parseMuxers(muxerResult.standardOutput),
            encoders: FFmpegCatalogParser.parseEncoders(encoderResult.standardOutput)
        )
    }

    func runFFprobe(arguments: [String]) throws -> ProcessResult {
        try run(executables.ffprobe, arguments: arguments)
    }

    func runFFmpeg(arguments: [String]) throws -> ProcessResult {
        try run(executables.ffmpeg, arguments: arguments)
    }

    private func run(_ executable: URL, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw FFmpegRunnerError.launchFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let error = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let result = ProcessResult(exitCode: process.terminationStatus, standardOutput: output, standardError: error)

        guard result.exitCode == 0 else {
            throw FFmpegRunnerError.commandFailed(
                executable: executable.lastPathComponent,
                exitCode: result.exitCode,
                message: error.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result
    }
}
