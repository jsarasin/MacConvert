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

            if model.canShowOriginals {
                Button("Show Originals") { model.showOriginals() }
            }
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
