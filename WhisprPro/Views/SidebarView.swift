import SwiftUI
import SwiftData

struct SidebarView: View {
    @Query(sort: \Transcription.createdAt, order: .reverse)
    private var transcriptions: [Transcription]

    @Bindable var viewModel: TranscriptionViewModel

    var body: some View {
        VStack(spacing: 0) {
            List(filteredTranscriptions, selection: $viewModel.selectedTranscription) { transcription in
                TranscriptionRow(transcription: transcription)
                    .tag(transcription)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            viewModel.deleteTranscription(transcription)
                        }
                    }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search")

            Divider()

            VStack(spacing: 8) {
                Button {
                    viewModel.showFileImporter = true
                } label: {
                    Label("Import File", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.isRecordingMode = true
                } label: {
                    Label("Record", systemImage: "record.circle")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    NotificationCenter.default.post(name: .showYouTube, object: nil)
                } label: {
                    Label("YouTube", systemImage: "play.rectangle")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
    }

    private var filteredTranscriptions: [Transcription] {
        if viewModel.searchText.isEmpty {
            return transcriptions
        }
        return transcriptions.filter {
            $0.title.localizedCaseInsensitiveContains(viewModel.searchText)
        }
    }
}

struct TranscriptionRow: View {
    let transcription: Transcription

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(transcription.title)
                .font(.body)
                .lineLimit(1)

            HStack {
                statusIndicator
                Text(formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch transcription.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .transcribing, .diarizing:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("\(Int(transcription.progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private var formattedDuration: String {
        let minutes = Int(transcription.duration) / 60
        let seconds = Int(transcription.duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
