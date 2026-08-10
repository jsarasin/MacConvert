import SwiftUI

struct CustomEncodingView: View {
    let kind: CustomSheetKind
    let onCancel: () -> Void
    let onApply: () -> Void

    @State private var quality = 80.0
    @State private var effort = 6.0
    @State private var audioBitrate = 256
    @State private var preserveResolution = true
    @State private var preserveFrameRate = true
    @State private var preserveMetadata = true
    @State private var preserveAlpha = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))

            Form {
                Section("Quality") {
                    LabeledContent("Quality") {
                        Slider(value: $quality, in: 1...100, step: 1)
                            .frame(width: 240)
                        Text("\(Int(quality))")
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                    }

                    LabeledContent("Encoding effort") {
                        Slider(value: $effort, in: 1...10, step: 1)
                            .frame(width: 240)
                        Text("\(Int(effort))")
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                    }
                }

                if kind == .video {
                    Section("Video and Audio") {
                        Toggle("Preserve original resolution", isOn: $preserveResolution)
                        Toggle("Preserve original frame rate", isOn: $preserveFrameRate)
                        Picker("AAC bitrate", selection: $audioBitrate) {
                            Text("128 kbps").tag(128)
                            Text("192 kbps").tag(192)
                            Text("256 kbps").tag(256)
                            Text("320 kbps").tag(320)
                        }
                    }
                } else if kind == .picture {
                    Section("Picture") {
                        Toggle("Preserve alpha channel", isOn: $preserveAlpha)
                    }
                } else {
                    Section("Audio") {
                        Picker("Audio bitrate", selection: $audioBitrate) {
                            Text("128 kbps").tag(128)
                            Text("192 kbps").tag(192)
                            Text("256 kbps").tag(256)
                            Text("320 kbps").tag(320)
                        }
                    }
                }

                Section("Metadata") {
                    Toggle("Preserve supported metadata", isOn: $preserveMetadata)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Reset to Preserve Quality") {
                    quality = 80
                    effort = 6
                    audioBitrate = 256
                    preserveResolution = true
                    preserveFrameRate = true
                    preserveMetadata = true
                    preserveAlpha = true
                }

                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Apply", action: onApply)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: kind == .video ? 520 : 430)
    }

    private var title: String {
        switch kind {
        case .video: "Custom Video Encoding"
        case .picture: "Custom Picture Encoding"
        case .audio: "Custom Audio Encoding"
        }
    }
}

#if DEBUG
#Preview("Custom Video Encoding") {
    CustomEncodingView(kind: .video, onCancel: {}, onApply: {})
}

#Preview("Custom Picture Encoding") {
    CustomEncodingView(kind: .picture, onCancel: {}, onApply: {})
}

#Preview("Custom Audio Encoding") {
    CustomEncodingView(kind: .audio, onCancel: {}, onApply: {})
}
#endif
