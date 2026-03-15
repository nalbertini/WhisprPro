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
    var isRecordingMode = false

    private let modelContext: ModelContext
    private(set) var transcriptionService: TranscriptionService

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.transcriptionService = TranscriptionService(modelContext: modelContext)
    }

    func importFiles(urls: [URL]) async {
        for url in urls {
            await importFile(url: url)
        }
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

    func importWhisprFile(url: URL) {
        do {
            let (transcript, audioURL) = try WhisprFileService.importWhispr(url: url)

            let transcription = Transcription(
                title: transcript.title,
                sourceURL: audioURL,
                language: transcript.language,
                modelName: transcript.modelName,
                duration: transcript.duration
            )
            transcription.createdAt = transcript.createdAt
            transcription.status = .completed
            transcription.progress = 1.0
            modelContext.insert(transcription)

            // Create speakers
            var speakerMap: [String: Speaker] = [:]
            for sp in transcript.speakers {
                let speaker = Speaker(label: sp.label, color: sp.color)
                speaker.transcription = transcription
                modelContext.insert(speaker)
                speakerMap[sp.label] = speaker
            }

            // Create segments
            for seg in transcript.segments {
                let segment = Segment(startTime: seg.startTime, endTime: seg.endTime, text: seg.text)
                segment.isEdited = seg.isEdited
                segment.isStarred = seg.isStarred
                segment.transcription = transcription
                if let label = seg.speakerLabel {
                    segment.speaker = speakerMap[label]
                }
                modelContext.insert(segment)
            }

            do {
                try modelContext.save()
            } catch {
                print("Failed to save imported transcription: \(error)")
            }

            selectedTranscription = transcription
        } catch {
            print("Import .whispr failed: \(error)")
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
