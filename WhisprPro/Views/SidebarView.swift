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
                .background(Color(red: 0.227, green: 0.227, blue: 0.235))

            VStack(spacing: 4) {
                Button {
                    viewModel.showFileImporter = true
                } label: {
                    Label("Import File", systemImage: "doc.badge.plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(red: 0.776, green: 0.776, blue: 0.800))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(red: 0.220, green: 0.220, blue: 0.228))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.isRecordingMode = true
                } label: {
                    Label("Record", systemImage: "record.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(red: 1.0, green: 0.271, blue: 0.227))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(red: 0.220, green: 0.220, blue: 0.228))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button {
                    NotificationCenter.default.post(name: .showYouTube, object: nil)
                } label: {
                    Label("YouTube", systemImage: "play.rectangle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(red: 1.0, green: 0.271, blue: 0.227))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(red: 0.220, green: 0.220, blue: 0.228))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
        }
        .background(Color(red: 0.173, green: 0.173, blue: 0.180))
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
        VStack(alignment: .leading, spacing: 3) {
            Text(transcription.title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(red: 0.961, green: 0.961, blue: 0.969))
                .lineLimit(1)

            HStack(spacing: 6) {
                statusIndicator
                Text(formattedDuration)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.388, green: 0.388, blue: 0.400))
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch transcription.status {
        case .completed:
            Circle()
                .fill(Color(red: 0.188, green: 0.820, blue: 0.345))
                .frame(width: 7, height: 7)
        case .transcribing, .diarizing:
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(red: 1.0, green: 0.624, blue: 0.039))
                    .frame(width: 7, height: 7)
                Text("\(Int(transcription.progress * 100))%")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 0.557, green: 0.557, blue: 0.576))
            }
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color(red: 1.0, green: 0.271, blue: 0.227))
                .font(.system(size: 10))
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(Color(red: 0.557, green: 0.557, blue: 0.576))
                .font(.system(size: 10))
        }
    }

    private var formattedDuration: String {
        let minutes = Int(transcription.duration) / 60
        let seconds = Int(transcription.duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
