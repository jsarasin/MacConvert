import SwiftUI

struct OutputProfileView: View {
    @Bindable var model: AppModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 5) {
                videoSection
                Divider()
                pictureSection
                Divider()
                audioSection
            }
        } label: {
            HStack(spacing: 8) {
                Text("Output formats")
                Spacer(minLength: 8)
                ffmpegStatus
            }
            .frame(maxWidth: .infinity)
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Output formats")
    }

    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            profileLabel("Video", systemImage: "film")

            HStack(alignment: .top, spacing: 8) {
                pickerField("Container", width: 100) {
                    Picker(
                        "Container",
                        selection: Binding(
                            get: { model.selectedVideoContainer },
                            set: { model.chooseVideoContainer($0) }
                        )
                    ) {
                        ForEach(model.availableVideoContainers) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .disabled(model.isDiscoveringFormats || model.availableVideoContainers.isEmpty)
                }

                if !model.selectedVideoContainer.isAnimatedImageTarget {
                    pickerField("Video Encoding", width: 185) {
                    Picker("Video Encoding", selection: $model.selectedVideoEncoder) {
                        ForEach(model.availableVideoEncoders) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .disabled(model.isDiscoveringFormats || model.availableVideoEncoders.isEmpty)
                    }
                }

                if model.selectedVideoContainer.supportsAudio {
                    pickerField("Audio Encoding", width: 135) {
                    Picker("Audio Encoding", selection: $model.selectedAudioEncoder) {
                        ForEach(model.availableAudioEncoders) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .disabled(model.isDiscoveringFormats || model.availableAudioEncoders.isEmpty)
                    }
                }

                pickerField("Quality", width: 150) {
                    Picker(
                        "Quality",
                        selection: Binding(
                            get: { model.selectedVideoQuality },
                            set: { model.chooseVideoQuality($0) }
                        )
                    ) {
                        ForEach(QualityPreset.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                }

                if model.selectedVideoContainer.isAnimatedImageTarget {
                    Toggle("Loop animation", isOn: $model.loopAnimation)
                        .toggleStyle(.checkbox)
                        .frame(minWidth: 125, alignment: .leading)
                        .padding(.top, 15)
                        .help("Loop indefinitely when enabled; otherwise play once")
                }
            }
        }
    }

    private var pictureSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            profileLabel("Picture", systemImage: "photo")

            HStack(alignment: .top, spacing: 8) {
                pickerField("Output Format", width: 125) {
                    Picker("Output Format", selection: $model.selectedPictureFormat) {
                        ForEach(model.availablePictureFormats) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .disabled(model.isDiscoveringFormats || model.availablePictureFormats.isEmpty)
                }

                pickerField("Quality", width: 140) {
                    Picker(
                        "Quality",
                        selection: Binding(
                            get: { model.selectedPictureQuality },
                            set: { model.choosePictureQuality($0) }
                        )
                    ) {
                        ForEach(QualityPreset.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                }
            }
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            profileLabel("Audio", systemImage: "waveform")

            HStack(alignment: .top, spacing: 8) {
                pickerField("Container", width: 90) {
                    Picker(
                        "Container",
                        selection: Binding(
                            get: { model.selectedAudioContainer },
                            set: { model.chooseAudioContainer($0) }
                        )
                    ) {
                        ForEach(model.availableAudioContainers) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .disabled(model.isDiscoveringFormats || model.availableAudioContainers.isEmpty)
                }

                pickerField("Audio Encoding", width: 140) {
                    Picker("Audio Encoding", selection: $model.selectedAudioOutputEncoder) {
                        ForEach(model.availableAudioOutputEncoders) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .disabled(model.isDiscoveringFormats || model.availableAudioOutputEncoders.isEmpty)
                }

                pickerField("Quality", width: 140) {
                    Picker(
                        "Quality",
                        selection: Binding(
                            get: { model.selectedAudioQuality },
                            set: { model.chooseAudioQuality($0) }
                        )
                    ) {
                        ForEach(QualityPreset.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                }
            }
        }
    }

    private func profileLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
    }

    private func pickerField<Content: View>(
        _ title: String,
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
                .labelsHidden()
                .frame(minWidth: width, maxWidth: width, alignment: .leading)
        }
        .frame(minWidth: width, maxWidth: width, alignment: .leading)
    }

    private var ffmpegStatus: some View {
        HStack(spacing: 5) {
            if model.isDiscoveringFormats {
                ProgressView()
                    .controlSize(.small)
            } else if model.ffmpegError != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Text(model.ffmpegStatus)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(model.ffmpegStatus)
            if model.ffmpegError != nil {
                Button("Retry") { Task { await model.refreshFFmpegCatalog() } }
                    .buttonStyle(.link)
            }
        }
        .font(.caption)
    }
}

#if DEBUG
#Preview("Output Formats") {
    OutputProfileView(model: PreviewFixtures.model())
        .frame(width: 656)
        .padding()
}
#endif
