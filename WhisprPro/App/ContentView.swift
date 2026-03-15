import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: TranscriptionViewModel?
    @State private var playerViewModel = AudioPlayerViewModel()

    var body: some View {
        Group {
            if let viewModel {
                mainContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = TranscriptionViewModel(modelContext: modelContext)
            }
        }
    }

    @ViewBuilder
    private func mainContent(viewModel: TranscriptionViewModel) -> some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .frame(minWidth: 220)
        } detail: {
            if let transcription = viewModel.selectedTranscription {
                TranscriptView(
                    transcription: transcription,
                    playerViewModel: playerViewModel
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundStyle(.quaternary)
                    Text("Select or import a transcription")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .fileImporter(
            isPresented: Binding(
                get: { viewModel.showFileImporter },
                set: { viewModel.showFileImporter = $0 }
            ),
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await viewModel.importFile(url: url) }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, AudioConverter.isSupported(url) else { return }
                Task { @MainActor in
                    await viewModel.importFile(url: url)
                }
            }
            return true
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showRecordingSheet },
            set: { viewModel.showRecordingSheet = $0 }
        )) {
            RecordingView(viewModel: RecordingViewModel()) { recordedURL in
                Task { await viewModel.importFile(url: recordedURL) }
            }
        }
    }
}
