import SwiftUI
import SwiftData
import AVFoundation

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("defaultLanguage") private var defaultLanguage = "auto"
    @AppStorage("defaultModel") private var defaultModel = "tiny"
    @AppStorage("defaultExportFormat") private var defaultExportFormat = "srt"
    @AppStorage("exportIncludeTimestamps") private var includeTimestamps = true
    @AppStorage("exportIncludeSpeakers") private var includeSpeakers = true
    @AppStorage("defaultAudioInput") private var defaultAudioInput = ""
    @State private var showModelImporter = false

    var body: some View {
        TabView {
            modelsTab
                .tabItem { Label("Models", systemImage: "cpu") }

            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            exportTab
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
        }
        .frame(width: 500, height: 350)
    }

    private var modelsTab: some View {
        VStack {
            ModelManagerView(viewModel: ModelManagerViewModel(modelContext: modelContext))

            Divider()

            Button("Import Custom Model...") {
                showModelImporter = true
            }
            .padding(.bottom, 8)
        }
        .fileImporter(
            isPresented: $showModelImporter,
            allowedContentTypes: [.init(filenameExtension: "bin")!],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                importCustomModel(url: url)
            }
        }
    }

    private func importCustomModel(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let manager = ModelManager()
        let destDir = manager.modelsDirectory(for: .whisper)
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let dest = destDir.appendingPathComponent(url.lastPathComponent)

        do {
            if FileManager.default.fileExists(atPath: dest.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)

            // Add to SwiftData
            let name = url.deletingPathExtension().lastPathComponent
            let size = (try? FileManager.default.attributesOfItem(atPath: dest.path(percentEncoded: false))[.size] as? Int64) ?? 0
            let model = MLModelInfo(name: name, kind: .whisper, size: size)
            model.isDownloaded = true
            model.localURL = dest
            modelContext.insert(model)
            try? modelContext.save()
        } catch {
            print("Failed to import model: \(error)")
        }
    }

    private var generalTab: some View {
        Form {
            Picker("Default Language", selection: $defaultLanguage) {
                Text("Auto-detect").tag("auto")
                Text("English").tag("en")
                Text("Italian").tag("it")
                Text("Spanish").tag("es")
                Text("French").tag("fr")
                Text("German").tag("de")
                Text("Portuguese").tag("pt")
                Text("Japanese").tag("ja")
                Text("Chinese").tag("zh")
                Text("Korean").tag("ko")
                Text("Russian").tag("ru")
                Text("Arabic").tag("ar")
                Text("Hindi").tag("hi")
                Text("Dutch").tag("nl")
                Text("Polish").tag("pl")
                Text("Turkish").tag("tr")
                Text("Swedish").tag("sv")
                Text("Ukrainian").tag("uk")
            }

            Picker("Default Model", selection: $defaultModel) {
                Text("tiny").tag("tiny")
                Text("base").tag("base")
                Text("small").tag("small")
                Text("medium").tag("medium")
                Text("large-v3").tag("large-v3")
                Text("large-v3-turbo").tag("large-v3-turbo")
            }

            Picker("Audio Input", selection: $defaultAudioInput) {
                Text("System Default").tag("")
                ForEach(availableInputDevices, id: \.uniqueID) { device in
                    Text(device.localizedName).tag(device.uniqueID)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var availableInputDevices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    private var exportTab: some View {
        Form {
            Picker("Default Format", selection: $defaultExportFormat) {
                Text("SRT").tag("srt")
                Text("VTT").tag("vtt")
                Text("Text").tag("txt")
                Text("JSON").tag("json")
                Text("PDF").tag("pdf")
            }
            Toggle("Include timestamps", isOn: $includeTimestamps)
            Toggle("Include speaker labels", isOn: $includeSpeakers)
        }
        .formStyle(.grouped)
        .padding()
    }
}
