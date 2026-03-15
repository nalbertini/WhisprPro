import SwiftUI
import SwiftData
import UniformTypeIdentifiers

extension Notification.Name {
    static let importFile = Notification.Name("importFile")
    static let newRecording = Notification.Name("newRecording")
    static let toggleInspector = Notification.Name("toggleInspector")
    static let showLiveCaptions = Notification.Name("showLiveCaptions")
    static let showYouTube = Notification.Name("showYouTube")
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: TranscriptionViewModel?
    @State private var playerViewModel = AudioPlayerViewModel()
    @State private var showInspector = true
    @State private var fontSize: Double = 15
    @State private var favoritesOnly = false
    @State private var compactMode = false
    @State private var showCaptions = false
    @State private var showYouTubeImport = false

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
            if viewModel.isRecordingMode {
                InlineRecordingView(viewModel: viewModel, playerViewModel: playerViewModel)
            } else if let transcription = viewModel.selectedTranscription {
                HSplitView {
                    TranscriptContentView(
                        transcription: transcription,
                        playerViewModel: playerViewModel,
                        fontSize: fontSize,
                        favoritesOnly: favoritesOnly,
                        compactMode: compactMode
                    )

                    if showInspector {
                        InspectorView(
                            transcription: transcription,
                            fontSize: $fontSize,
                            favoritesOnly: $favoritesOnly,
                            compactMode: $compactMode
                        )
                        .frame(minWidth: 220, idealWidth: 280, maxWidth: 400)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundStyle(.quaternary)
                    Text("Select a transcription or start recording")
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            viewModel.showFileImporter = true
                        } label: {
                            Label("Import File", systemImage: "doc.badge.plus")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            viewModel.isRecordingMode = true
                        } label: {
                            Label("Record", systemImage: "record.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 550)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation { showInspector.toggle() }
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle Inspector")
            }
        }
        .fileImporter(
            isPresented: Binding(
                get: { viewModel.showFileImporter },
                set: { viewModel.showFileImporter = $0 }
            ),
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task {
                    await viewModel.importFiles(urls: urls)
                }
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
        .onReceive(NotificationCenter.default.publisher(for: .importFile)) { _ in
            viewModel.showFileImporter = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newRecording)) { _ in
            viewModel.isRecordingMode = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { _ in
            withAnimation { showInspector.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showLiveCaptions)) { _ in
            showCaptions = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showYouTube)) { _ in
            showYouTubeImport = true
        }
        .sheet(isPresented: $showCaptions) {
            RealtimeCaptionView()
        }
        .sheet(isPresented: $showYouTubeImport) {
            YouTubeImportView { audioURL, title, duration in
                Task {
                    let transcription = viewModel.transcriptionService.createTranscription(
                        title: title,
                        sourceURL: audioURL,
                        language: "auto",
                        modelName: UserDefaults.standard.string(forKey: "defaultModel") ?? "tiny",
                        duration: duration
                    )
                    viewModel.selectedTranscription = transcription
                    await viewModel.transcriptionService.enqueue(transcription)
                }
            }
        }
    }
}
