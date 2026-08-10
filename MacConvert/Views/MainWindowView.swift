import SwiftUI

struct MainWindowView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            OutputProfileView(model: model)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            DropZoneView(model: model)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            JobHistoryView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            Divider()

            FooterView(model: model)
        }
        .frame(minWidth: 680, maxWidth: 680, minHeight: 520, maxHeight: .infinity)
        .task { await model.loadFFmpegCatalogIfNeeded() }
        .sheet(item: $model.presentedJob) { job in
            JobDetailsView(job: job)
        }
        .sheet(item: $model.customSheetKind) { kind in
            CustomEncodingView(
                kind: kind,
                onCancel: { model.cancelCustomSheet(kind) },
                onApply: { model.customSheetKind = nil }
            )
        }
        .sheet(isPresented: $model.isShowingFormatSupport) {
            FormatSupportView(model: model)
        }
    }
}

#if DEBUG
#Preview("Main Window") {
    MainWindowView(model: PreviewFixtures.model(jobs: PreviewFixtures.representativeJobs))
        .frame(width: 680, height: 720)
}
#endif
