import SwiftUI
import SwiftData

@main
struct WhisprProApp: App {
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
}
