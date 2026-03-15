import SwiftUI

struct ModelManagerView: View {
    @Bindable var viewModel: ModelManagerViewModel

    var body: some View {
        List {
            Section("Whisper Models") {
                ForEach(viewModel.models.filter { $0.kind == .whisper }) { model in
                    modelRow(model)
                }
            }

            Section("Speaker Diarization") {
                ForEach(viewModel.models.filter { $0.kind == .diarization }) { model in
                    modelRow(model)
                }
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ model: MLModelInfo) -> some View {
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
            } else if viewModel.isDownloading(model) {
                VStack(alignment: .trailing, spacing: 2) {
                    ProgressView(value: viewModel.progress(for: model))
                        .frame(width: 120)
                    Text("\(Int(viewModel.progress(for: model) * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
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

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
