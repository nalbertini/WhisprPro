import SwiftUI

struct ModelManagerView: View {
    @Bindable var viewModel: ModelManagerViewModel

    var body: some View {
        List(viewModel.models) { model in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name)
                        .fontWeight(.semibold)
                    Text(formatSize(model.size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.isDownloaded {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Delete", role: .destructive) {
                            viewModel.deleteModel(model)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .font(.caption)
                    }
                } else if model.downloadProgress > 0 && model.downloadProgress < 1 {
                    ProgressView(value: model.downloadProgress)
                        .frame(width: 100)
                } else {
                    Button("Download") {
                        Task { await viewModel.downloadModel(model) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
