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
    @State private var groupSegments = true
    @State private var showCaptions = false
    @State private var showYouTubeImport = false
    @State private var meetingDetector = MeetingDetectorService()

    // Design tokens
    private let textMuted = Color(red: 0.290, green: 0.290, blue: 0.306)       // #4A4A4E
    private let textTertiary = Color(red: 0.388, green: 0.388, blue: 0.400)    // #636366
    private let textPrimary = Color(red: 0.961, green: 0.961, blue: 0.969)     // #F5F5F7
    private let cardBackground = Color(red: 0.220, green: 0.220, blue: 0.228)  // #38383A
    private let accentRed = Color(red: 1.0, green: 0.271, blue: 0.227)         // #FF453A

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
            meetingDetector.startMonitoring()
        }
        .overlay(alignment: .top) {
            if let meeting = meetingDetector.detectedMeeting {
                meetingBanner(meeting: meeting)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: meetingDetector.detectedMeeting)
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
                        compactMode: compactMode,
                        groupSegments: groupSegments
                    )

                    if showInspector {
                        InspectorView(
                            transcription: transcription,
                            fontSize: $fontSize,
                            favoritesOnly: $favoritesOnly,
                            compactMode: $compactMode,
                            groupSegments: $groupSegments
                        )
                        .frame(minWidth: 220, idealWidth: 280, maxWidth: 400)
                    }
                }
            } else {
                HomeView(
                    onImport: { viewModel.showFileImporter = true },
                    onRecord: {
                        viewModel.recordingSourceMode = 0
                        viewModel.isRecordingMode = true
                    },
                    onYouTube: { showYouTubeImport = true },
                    onMeeting: {
                        viewModel.recordingSourceMode = 2
                        viewModel.isRecordingMode = true
                    },
                    onLiveCaptions: { showCaptions = true },
                    onSelectTranscription: { transcription in
                        viewModel.selectedTranscription = transcription
                    }
                )
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
            allowedContentTypes: [.audio, .movie, .init(filenameExtension: "whispr")!],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task {
                    for url in urls {
                        if url.pathExtension == "whispr" {
                            viewModel.importWhisprFile(url: url)
                        } else {
                            await viewModel.importFile(url: url)
                        }
                    }
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

    @ViewBuilder
    private func meetingBanner(meeting: MeetingDetectorService.DetectedMeeting) -> some View {
        HStack(spacing: 12) {
            Image(systemName: meeting.icon)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color(red: 0.039, green: 0.518, blue: 1.0))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(meeting.service) detected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.961, green: 0.961, blue: 0.969))
                Text("Record both sides of the conversation?")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.557, green: 0.557, blue: 0.576))
            }

            Spacer()

            Button {
                viewModel?.isRecordingMode = true
                meetingDetector.dismissCurrentMeeting()
            } label: {
                Text("Record Meeting")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color(red: 1.0, green: 0.271, blue: 0.227))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Button {
                meetingDetector.dismissCurrentMeeting()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.557, green: 0.557, blue: 0.576))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(red: 0.173, green: 0.173, blue: 0.180))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}
