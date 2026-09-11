import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    private var settings: AppSettings { model.settings }

    var body: some View {
        TabView {
            LocationsSettingsView(settings: settings)
                .tabItem { Label("Locations", systemImage: "folder") }

            ConversionSettingsView(model: model)
                .tabItem { Label("Conversion", systemImage: "slider.horizontal.3") }

            GeneralSettingsView(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }

            AdvancedSettingsView(model: model, settings: settings)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 620, height: 440)
    }
}

private struct LocationsSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var locationError: String?

    var body: some View {
        Form {
            Section("Converted Output") {
                Picker("Destination", selection: $settings.outputDestinationMode) {
                    ForEach(OutputDestinationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                if settings.outputDestinationMode == .chosenFolder {
                    locationRow(title: "Output folder", path: settings.outputPath) {
                        chooseFolder(currentPath: settings.outputPath) { settings.outputPath = $0 }
                    }
                }
            }

            Section("Original Files") {
                Toggle("Keep a backup of original files", isOn: $settings.backupOriginals)
                Text(settings.backupOriginals
                     ? "Originals are copied to the backup folder before the source files are deleted."
                     : "Source files are deleted after their converted replacements are validated. No backup is kept.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if settings.backupOriginals {
                    locationRow(title: "Backup folder", path: settings.archivePath) {
                        chooseFolder(currentPath: settings.archivePath, requireLocal: true) { settings.archivePath = $0 }
                    }
                    if settings.archivePath.isEmpty {
                        Text("Choose a local backup folder before adding files.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Temporary Files") {
                LabeledContent("Working folder", value: "Provided by macOS")
                Text("MacConvert uses the system temporary folder and removes working files after each job.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let locationError {
                Text(locationError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Folder selection error: \(locationError)")
            }

            HStack {
                Spacer()
                Button("Restore Defaults") {
                    settings.restoreLocationDefaults()
                    locationError = nil
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func locationRow(title: String, path: String, choose: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            HStack {
                Text(path.isEmpty ? "No folder selected" : path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 280, alignment: .trailing)
                Button("Show") { FinderService.reveal(URL(fileURLWithPath: path, isDirectory: true)) }
                    .disabled(path.isEmpty || !FileManager.default.fileExists(atPath: path))
                Button("Choose…", action: choose)
            }
        }
    }

    private func chooseFolder(currentPath: String, requireLocal: Bool = false, onChoose: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Choose Folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if !currentPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: currentPath, isDirectory: true)
        }
        if panel.runModal() == .OK, let url = panel.url {
            if requireLocal {
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isWritableKey, .volumeIsLocalKey]),
                      values.isDirectory == true, values.isWritable == true, values.volumeIsLocal == true else {
                    locationError = "Choose a writable folder on a local disk for original backups."
                    return
                }
            }
            locationError = nil
            onChoose(url.path)
        }
    }
}

private struct ConversionSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Default Profile") {
                LabeledContent("Video") {
                    Text("\(model.selectedVideoContainer.displayName) • \(model.selectedVideoEncoder.displayName) • \(model.selectedAudioEncoder.displayName) • \(model.selectedVideoQuality.displayName)")
                }
                LabeledContent("Picture") {
                    Text("\(model.selectedPictureFormat.displayName) • \(model.selectedPictureQuality.displayName)")
                }
                LabeledContent("Audio") {
                    Text("\(model.selectedAudioContainer.displayName) • \(model.selectedAudioOutputEncoder.displayName) • \(model.selectedAudioQuality.displayName)")
                }
            }

            Section {
                Toggle("Preserve supported metadata", isOn: .constant(true))
                Toggle("Preserve chapters and subtitles", isOn: .constant(true))
                Toggle("Preserve color profiles and transparency", isOn: .constant(true))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Toggle("Start jobs immediately after files are added", isOn: $settings.startImmediately)
            Toggle("Continue after an individual job fails", isOn: $settings.continueAfterFailure)
            Toggle("Prevent the Mac from sleeping during conversion", isOn: $settings.preventSleep)
            Toggle("Notify me when the queue finishes", isOn: $settings.notifyWhenFinished)
            Toggle("Remember job history between launches", isOn: $settings.rememberHistory)
            Toggle("Confirm before cancelling an active conversion", isOn: $settings.confirmCancellation)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct AdvancedSettingsView: View {
    @Bindable var model: AppModel
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Stepper("Maximum simultaneous conversions: \(settings.maximumConcurrentJobs)", value: $settings.maximumConcurrentJobs, in: 1...8)

            Section("FFmpeg") {
                Picker("Source", selection: $settings.ffmpegSourceMode) {
                    ForEach(FFmpegSourceMode.allCases) { source in
                        Text(source.displayName).tag(source)
                    }
                }
                .onChange(of: settings.ffmpegSourceMode) { _, _ in
                    model.ffmpegSourceChanged()
                }

                if settings.ffmpegSourceMode == .path {
                    LabeledContent("Search path") {
                        Text(model.inheritedSearchPath.isEmpty ? "PATH is empty" : model.inheritedSearchPath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Text("MacConvert searches the PATH environment it inherited when the app launched.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if settings.ffmpegSourceMode == .custom {
                    executableLocationRow(
                        title: "FFmpeg",
                        path: $settings.customFFmpegPath,
                        choose: { model.chooseCustomExecutable(.ffmpeg) }
                    )
                    executableLocationRow(
                        title: "ffprobe",
                        path: $settings.customFFprobePath,
                        choose: { model.chooseCustomExecutable(.ffprobe) }
                    )
                    Button("Validate Custom Tools") {
                        model.ffmpegSourceChanged()
                    }
                    .disabled(settings.customFFmpegPath.isEmpty || settings.customFFprobePath.isEmpty || model.isDiscoveringFormats)
                }

                LabeledContent("Status") {
                    Text(model.ffmpegStatus)
                        .foregroundStyle(.secondary)
                }
                if let url = model.activeFFmpegURL {
                    LabeledContent("Active FFmpeg") {
                        Text(url.path)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                if let url = model.activeFFprobeURL {
                    LabeledContent("Active ffprobe") {
                        Text(url.path)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                LabeledContent("Supported output containers") {
                    Text("\(model.ffmpegCatalog.muxers.count)").foregroundStyle(.secondary)
                }
                LabeledContent("Supported encoders") {
                    Text("\(model.ffmpegCatalog.encoders.count)").foregroundStyle(.secondary)
                }
                if model.isUsingNonRedistributableFFmpeg {
                    Label(
                        "This FFmpeg build is for local use only and must not be distributed with the app.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
                if let error = model.ffmpegError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Refresh Supported Formats") {
                        Task { await model.refreshFFmpegCatalog() }
                    }
                    .disabled(model.isDiscoveringFormats)
                    Button("Show Format Support") { model.isShowingFormatSupport = true }
                        .disabled(model.ffmpegCatalog.version.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func executableLocationRow(
        title: String,
        path: Binding<String>,
        choose: @escaping () -> Void
    ) -> some View {
        LabeledContent(title) {
            HStack {
                TextField("Executable path", text: path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { model.ffmpegSourceChanged() }
                Button("Choose…", action: choose)
            }
        }
    }
}

#if DEBUG
#Preview("Settings") {
    SettingsView(model: PreviewFixtures.model())
}

#Preview("Locations Settings") {
    LocationsSettingsView(settings: PreviewFixtures.model().settings)
        .frame(width: 620, height: 440)
}

#Preview("Conversion Settings") {
    ConversionSettingsView(model: PreviewFixtures.model())
        .frame(width: 620, height: 440)
}

#Preview("General Settings") {
    GeneralSettingsView(settings: PreviewFixtures.model().settings)
        .frame(width: 620, height: 440)
}

#Preview("Advanced Settings") {
    AdvancedSettingsView(
        model: PreviewFixtures.model(),
        settings: PreviewFixtures.model().settings
    )
        .frame(width: 620, height: 440)
}
#endif
