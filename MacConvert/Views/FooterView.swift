import SwiftUI

struct FooterView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 14) {
            Text(summary)
                .foregroundStyle(.secondary)

            if model.hasQueuedJobs {
                Button {
                    model.startQueuedJobs()
                } label: {
                    Label("Start Queue", systemImage: "play.fill")
                }
            }

            Spacer()

            Button("Show Originals") { model.showOriginals() }
            Toggle(
                "Remove original after success",
                isOn: Binding(
                    get: { model.settings.removeOriginalAfterSuccess },
                    set: { model.settings.removeOriginalAfterSuccess = $0 }
                )
            )
                .toggleStyle(.checkbox)
                .help("Apply to files added after this setting changes")
            Button("Clear History") { model.clearHistory() }
                .disabled(model.finishedJobCount == 0)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private var summary: String {
        var parts = ["\(model.jobs.count) \(model.jobs.count == 1 ? "job" : "jobs")"]
        if model.activeJobCount > 0 { parts.append("\(model.activeJobCount) converting") }
        if model.warningJobCount > 0 { parts.append("\(model.warningJobCount) warnings") }
        return parts.joined(separator: " • ")
    }
}

#if DEBUG
#Preview("Footer") {
    FooterView(model: PreviewFixtures.model(jobs: PreviewFixtures.representativeJobs))
        .frame(width: 680)
}
#endif
