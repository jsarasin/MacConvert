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
        .alert(
            "Replace a File in the Same Format?",
            isPresented: sameFormatAlertIsPresented,
            presenting: model.sameFormatWarning
        ) { warning in
            Button("Skip All") {
                model.resolveSameFormatWarning(warning.id, decision: .skipAll)
            }
            Button("Replace All", role: .destructive) {
                model.resolveSameFormatWarning(warning.id, decision: .replaceAll)
            }
            Button("Skip this file", role: .cancel) {
                model.resolveSameFormatWarning(warning.id, decision: .skipThisFile)
            }
            Button("Replace this file", role: .destructive) {
                model.resolveSameFormatWarning(warning.id, decision: .replaceThisFile)
            }
        } message: { warning in
            Text(sameFormatWarningMessage(warning))
        }
    }

    private func sameFormatWarningMessage(_ warning: SameFormatWarning) -> String {
        let remaining = warning.remainingFileCount == 1
            ? "This is the only matching file in this batch."
            : "There are \(warning.remainingFileCount) matching files in this batch."
        let originalHandling = warning.backsUpOriginal
            ? "MacConvert will back up and verify the original before installing the replacement."
            : "The original will be deleted after the replacement is validated."
        return "“\(warning.sourceURL.lastPathComponent)” is already in \(warning.targetFormatName) format. Replacing it will re-encode the file using the selected quality. \(originalHandling) \(remaining)"
    }

    private var sameFormatAlertIsPresented: Binding<Bool> {
        Binding(
            get: { model.sameFormatWarning != nil },
            set: { _ in }
        )
    }
}

#if DEBUG
#Preview("Main Window") {
    MainWindowView(model: PreviewFixtures.model(jobs: PreviewFixtures.representativeJobs))
        .frame(width: 680, height: 720)
}
#endif
