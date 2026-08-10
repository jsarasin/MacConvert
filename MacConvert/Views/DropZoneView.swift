import SwiftUI

struct DropZoneView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(model.isDropTargeted ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text("Drop files here to convert")
                    .font(.subheadline.weight(.semibold))

                Text("Video, picture, and audio files supported by FFmpeg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Button("Add Files…") {
                model.openFilePanel()
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(model.isDropTargeted ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(model.isDropTargeted ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: model.isDropTargeted ? 2 : 1)
        )
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            model.addFiles(urls)
            return true
        } isTargeted: { targeted in
            model.isDropTargeted = targeted
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File conversion drop area")
        .accessibilityHint("Drop files here or use Add Files")
    }
}

#if DEBUG
#Preview("Drop Zone") {
    DropZoneView(model: PreviewFixtures.model())
        .frame(width: 656)
        .padding()
}

#Preview("Drop Target Active") {
    DropZoneView(model: PreviewFixtures.dropTargetModel())
        .frame(width: 656)
        .padding()
}
#endif
