import SwiftUI

struct JobHistoryView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.selectedJobID) {
            ForEach(model.jobs) { job in
                JobRowView(
                    job: job,
                    onRetry: { model.retry(job.id) },
                    onCancel: { model.cancel(job.id) }
                )
                .tag(job.id)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture()
                        .onEnded { model.selectedJobID = job.id }
                )
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded { model.inspect(job) }
                )
                .contextMenu {
                    let locations = FinderService.existingLocations(for: job)
                    Button("Inspect") { model.inspect(job) }
                    if !locations.isEmpty {
                        Divider()
                    }
                    if let originalURL = locations.original {
                        Button("Show Original") { FinderService.reveal(originalURL) }
                    }
                    if let replacementURL = locations.replacement {
                        Button("Show Replacement") { FinderService.reveal(replacementURL) }
                    }
                    if (job.state == .failed || job.state == .cancelled) || !job.state.isFinished {
                        Divider()
                    }
                    if job.state == .failed || job.state == .cancelled {
                        Button("Retry") { model.retry(job.id) }
                    }
                    if !job.state.isFinished {
                        Button("Cancel") { model.cancel(job.id) }
                    }
                }
            }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .overlay {
            if model.jobs.isEmpty {
                ContentUnavailableView(
                    "No Jobs",
                    systemImage: "tray",
                    description: Text("Conversion jobs will display here.")
                )
            }
        }
        .accessibilityLabel("Conversion job history")
    }
}

#if DEBUG
#Preview("Job History") {
    JobHistoryView(model: PreviewFixtures.model(jobs: PreviewFixtures.representativeJobs))
        .frame(width: 680, height: 390)
}

#Preview("Empty Job History") {
    JobHistoryView(model: PreviewFixtures.model())
        .frame(width: 680, height: 390)
}
#endif
