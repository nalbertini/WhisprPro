import Foundation
import SwiftData
import SwiftUI
import os

private let logger = Logger(subsystem: "com.whisprpro", category: "Import")

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

    func importFile(url: URL, translateToEnglish: Bool = false) async {
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
                duration: duration,
                translateToEnglish: translateToEnglish
            )
            selectedTranscription = transcription
            Task {
                await transcriptionService.enqueue(transcription)
            }
        } catch {
            logger.error("Import failed: \(error)")
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
