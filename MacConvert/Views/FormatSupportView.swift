import SwiftUI

struct FormatSupportView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FFmpeg Format Support").font(.title2).fontWeight(.semibold)
                    Text(model.ffmpegStatus).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") { Task { await model.refreshFFmpegCatalog() } }
                    .disabled(model.isDiscoveringFormats)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            TabView {
                supportList(
                    model.ffmpegCatalog.muxers.map { ($0.id, $0.description) },
                    emptyText: "No output containers were reported."
                )
                .tabItem { Label("Containers", systemImage: "shippingbox") }

                supportList(
                    model.ffmpegCatalog.encoders.filter { $0.mediaKind == .video }.map { ($0.id, $0.description) },
                    emptyText: "No video encoders were reported."
                )
                .tabItem { Label("Video", systemImage: "film") }

                supportList(
                    model.ffmpegCatalog.encoders.filter { $0.mediaKind == .audio }.map { ($0.id, $0.description) },
                    emptyText: "No audio encoders were reported."
                )
                .tabItem { Label("Audio", systemImage: "waveform") }

                ScrollView {
                    Text(model.ffmpegCatalog.buildConfiguration)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .tabItem { Label("Build", systemImage: "hammer") }
            }
            .padding()
        }
        .frame(width: 720, height: 520)
    }

    private func supportList(_ values: [(String, String)], emptyText: String) -> some View {
        Group {
            if values.isEmpty {
                ContentUnavailableView(emptyText, systemImage: "questionmark.folder")
            } else {
                List(values, id: \.0) { value in
                    LabeledContent(value.0) { Text(value.1).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Format Support") {
    FormatSupportView(model: PreviewFixtures.model())
}
#endif
