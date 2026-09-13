import AppKit
import SwiftUI

@MainActor
final class MacConvertApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else {
            return
        }
        NSApplication.shared.applicationIconImage = icon
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
@MainActor
struct MacConvertApp: App {
    @NSApplicationDelegateAdaptor(MacConvertApplicationDelegate.self) private var applicationDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            MainWindowView(model: model)
                .onDisappear {
                    NSApplication.shared.terminate(nil)
                }
        }
        .defaultSize(width: 680, height: 680)
        .windowResizability(.contentSize)
        .commands {
            MacConvertCommands(model: model)
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

@MainActor
private struct MacConvertCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Files…") { model.openFilePanel() }
                .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(after: .toolbar) {
            Toggle(
                "Show All Supported Formats",
                isOn: Binding(
                    get: { model.settings.showAllSupportedFormats },
                    set: {
                        model.settings.showAllSupportedFormats = $0
                        model.supportedFormatsSettingChanged()
                    }
                )
            )
            Button("Show FFmpeg Format Support") { model.isShowingFormatSupport = true }
            Divider()
            Button("Show Temporary") { model.showTemporary() }
            Button("Show Originals") { model.showOriginals() }
            Button("Show Job Details") { model.inspectSelectedJob() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(model.selectedJob == nil)
        }

        CommandMenu("Job") {
            Button("Inspect") { model.inspectSelectedJob() }
                .disabled(model.selectedJob == nil)
            Button("Retry") { model.retrySelectedJob() }
                .disabled(model.selectedJob.map { $0.state != .failed && $0.state != .cancelled } ?? true)
            Button("Cancel") { model.cancelSelectedJob() }
                .disabled(model.selectedJob.map(\.state.isFinished) ?? true)
        }
    }
}
