import Foundation
import SwiftData
import SwiftUI

@Observable
final class TranscriptionViewModel {
    var selectedTranscription: Transcription?
    var searchText = ""
    var showRecordingSheet = false
    var showFileImporter = false

    private let modelContext: ModelContext
    private(set) var transcriptionService: TranscriptionService

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.transcriptionService = TranscriptionService(modelContext: modelContext)
    }

    func importFile(url: URL) async {
        let title = url.deletingPathExtension().lastPathComponent
        let defaultLanguage = UserDefaults.standard.string(forKey: "defaultLanguage") ?? "auto"
        let defaultModel = UserDefaults.standard.string(forKey: "defaultModel") ?? "tiny"
        do {
            let duration = try await AudioConverter.duration(of: url)
            let transcription = transcriptionService.createTranscription(
                title: title,
                sourceURL: url,
                language: defaultLanguage,
                modelName: defaultModel,
                duration: duration
            )
            selectedTranscription = transcription
            Task {
                await transcriptionService.enqueue(transcription)
            }
        } catch {
            print("Import failed: \(error)")
        }
    }

    func deleteTranscription(_ transcription: Transcription) {
        if selectedTranscription == transcription {
            selectedTranscription = nil
        }
        modelContext.delete(transcription)
        try? modelContext.save()
    }
}
