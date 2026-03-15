import SwiftUI
import SwiftData

@main
struct WhisprProApp: App {
    @State private var menuBarManager = MenuBarManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Transcription.self,
            Segment.self,
            Speaker.self,
            MLModelInfo.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    setupMenuBar()
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandMenu("Transcription") {
                Button("Import File...") {
                    NotificationCenter.default.post(name: .importFile, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("New Recording") {
                    NotificationCenter.default.post(name: .newRecording, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("YouTube Video...") {
                    NotificationCenter.default.post(name: .showYouTube, object: nil)
                }
                .keyboardShortcut("y", modifiers: [.command, .shift])

                Divider()

                Button("Live Captions") {
                    NotificationCenter.default.post(name: .showLiveCaptions, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Button("Toggle Inspector") {
                    NotificationCenter.default.post(name: .toggleInspector, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
        }
        .modelContainer(sharedModelContainer)
    }

    private func setupMenuBar() {
        menuBarManager.setup()
        let menuView = MenuBarView(
            onImport: {
                menuBarManager.closePopover()
                NotificationCenter.default.post(name: .importFile, object: nil)
                NSApp.activate(ignoringOtherApps: true)
            },
            onRecord: {
                menuBarManager.closePopover()
                NotificationCenter.default.post(name: .newRecording, object: nil)
                NSApp.activate(ignoringOtherApps: true)
            },
            onOpenMain: {
                menuBarManager.closePopover()
                NSApp.activate(ignoringOtherApps: true)
            }
        )
        .modelContainer(sharedModelContainer)
        menuBarManager.setContentView(menuView)
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "whisprpro" else { return }

        if url.host == "import", let fileParam = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "file" })?.value,
           let fileURL = URL(string: fileParam) {
            // Import the file via notification
            NotificationCenter.default.post(name: .importFile, object: fileURL)
        }

        // Also check App Group shared folder for pending imports
        if let sharedDir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.whisprpro"
        )?.appendingPathComponent("SharedFiles") {
            let markerURL = sharedDir.appendingPathComponent(".pending-import")
            if let path = try? String(contentsOf: markerURL, encoding: .utf8) {
                let fileURL = URL(filePath: path.trimmingCharacters(in: .whitespacesAndNewlines))
                NotificationCenter.default.post(name: .importFile, object: fileURL)
                try? FileManager.default.removeItem(at: markerURL)
            }
        }
    }
}
