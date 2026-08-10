import SwiftUI

struct JobDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    let job: ConversionJob

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: job.state.symbolName)
                    .font(.title2)
                VStack(alignment: .leading) {
                    Text(job.sourceURL.lastPathComponent)
                        .font(.title2.weight(.semibold))
                    Text(job.state.displayName)
                        .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Profile")
                        .foregroundStyle(.secondary)
                    Text(job.profileSummary)
                        .textSelection(.enabled)
                }

                pathRow("Input", url: job.sourceURL)
                if let targetURL = job.targetURL { pathRow("Output", url: targetURL) }
                if let archiveURL = job.archiveURL { pathRow("Original", url: archiveURL) }
            }

            if !job.warnings.isEmpty {
                GroupBox("Warnings") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(job.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !job.technicalLog.isEmpty {
                DisclosureGroup("Technical Details") {
                    ScrollView {
                        Text(job.technicalLog)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 170)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 330)
    }

    @ViewBuilder
    private func pathRow(_ label: String, url: URL) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Button(url.path) { FinderService.reveal(url) }
                .buttonStyle(.link)
                .lineLimit(1)
                .help("Show in Finder")
        }
    }
}

#if DEBUG
#Preview("Job Details with Warning") {
    JobDetailsView(
        job: PreviewFixtures.job(
            named: "Website Artwork.webp",
            kind: .picture,
            state: .successfulWithWarning,
            detail: "Successful with warning",
            size: 8_420_000,
            warnings: ["The source color profile was not included in the PNG output"]
        )
    )
}
#endif
