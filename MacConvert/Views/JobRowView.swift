import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct JobRowView: View {
    let job: ConversionJob
    let onRetry: () -> Void
    let onCancel: () -> Void
    let onProceed: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: sourceIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(job.sourceURL.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(job.sourceFileSizeDisplay)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel("Original size \(job.sourceFileSizeDisplay)")
                }

                Text(job.profileSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ForEach(job.informationalNotes, id: \.self) { note in
                    Label(note, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if job.state == .awaitingConfirmation {
                    Label(job.confirmationMessage ?? "Confirmation is required before conversion", systemImage: job.state.symbolName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Proceed with conversion", action: onProceed)
                            .buttonStyle(.borderedProminent)
                        Button("Cancel Job", role: .cancel, action: onCancel)
                            .buttonStyle(.bordered)
                    }
                }

                if job.state.isActive {
                    if let progress = job.progress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .accessibilityValue(Text("\(Int(progress * 100)) percent"))
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Label(job.statusDetail.isEmpty ? job.state.displayName : job.statusDetail, systemImage: job.state.symbolName)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if job.state == .failed || job.state == .cancelled {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Retry")
                    .accessibilityLabel("Retry \(job.sourceURL.lastPathComponent)")
                }

                if !job.state.isFinished && job.state != .awaitingConfirmation {
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Cancel")
                    .accessibilityLabel("Cancel \(job.sourceURL.lastPathComponent)")
                }
            }
            .font(.title3)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .contain)
    }

    private var statusColor: Color {
        switch job.state {
        case .successful: .green
        case .successfulWithWarning: .orange
        case .failed: .red
        case .cancelled: .secondary
        default: .accentColor
        }
    }

    private var sourceIcon: NSImage {
        let fileManager = FileManager.default
        if job.state.isFinished,
           let archiveURL = job.archiveURL,
           fileManager.fileExists(atPath: archiveURL.path) {
            return NSWorkspace.shared.icon(forFile: archiveURL.path)
        }
        if fileManager.fileExists(atPath: job.sourceURL.path) {
            return NSWorkspace.shared.icon(forFile: job.sourceURL.path)
        }
        if let archiveURL = job.archiveURL,
           fileManager.fileExists(atPath: archiveURL.path) {
            return NSWorkspace.shared.icon(forFile: archiveURL.path)
        }
        if let contentType = UTType(filenameExtension: job.sourceURL.pathExtension) {
            return NSWorkspace.shared.icon(for: contentType)
        }
        return NSWorkspace.shared.icon(forFile: job.sourceURL.path)
    }
}

#if DEBUG
#Preview("Converting Job Row") {
    JobRowView(
        job: PreviewFixtures.job(
            named: "Family Holiday.webm",
            state: .converting,
            progress: 0.46,
            detail: "Converting with FFmpeg",
            size: 4_160_000_000
        ),
        onRetry: {},
        onCancel: {},
        onProceed: {}
    )
    .frame(width: 640)
    .padding()
}

#Preview("Warning Job Row") {
    JobRowView(
        job: PreviewFixtures.job(
            named: "Website Artwork.webp",
            kind: .picture,
            state: .successfulWithWarning,
            detail: "Successful with warning",
            size: 8_420_000,
            warnings: ["The source color profile was not included"]
        ),
        onRetry: {},
        onCancel: {},
        onProceed: {}
    )
    .frame(width: 640)
    .padding()
}

#Preview("Failed Job Row") {
    JobRowView(
        job: PreviewFixtures.job(
            named: "Already Converted.mp4",
            state: .failed,
            detail: "File is already in the selected output format"
        ),
        onRetry: {},
        onCancel: {},
        onProceed: {}
    )
    .frame(width: 640)
    .padding()
}
#endif
