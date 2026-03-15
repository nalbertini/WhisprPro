import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.whisprpro", category: "TranscriptionService")

actor TranscriptionService {
    private let modelContext: ModelContext
    private let whisperBridge = WhisperBridge()
    private let modelManager = ModelManager()
    private var isProcessing = false
    private var pendingQueue: [Transcription] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    nonisolated func createTranscription(
        title: String,
        sourceURL: URL?,
        language: String,
        modelName: String,
        duration: TimeInterval,
        translateToEnglish: Bool = false
    ) -> Transcription {
        let t = Transcription(title: title, sourceURL: sourceURL, language: language, modelName: modelName, duration: duration)
        t.translateToEnglish = translateToEnglish
        return t
    }

    func enqueue(_ transcription: Transcription) async {
        modelContext.insert(transcription)
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save context: \(error)")
        }
        pendingQueue.append(transcription)
        await processNextIfIdle()
    }

    private func processNextIfIdle() async {
        guard !isProcessing, let transcription = pendingQueue.first else { return }
        pendingQueue.removeFirst()
        isProcessing = true

        do {
            try await processTranscription(transcription)
        } catch {
            transcription.status = .failed
            transcription.errorMessage = error.localizedDescription
        }

        isProcessing = false
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save context: \(error)")
        }

        if !pendingQueue.isEmpty {
            await processNextIfIdle()
        }
    }

    private func processTranscription(_ transcription: Transcription) async throws {
        transcription.status = .transcribing
        transcription.progress = 0.0
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save context: \(error)")
        }

        let tempDir = FileManager.default.temporaryDirectory
        let wavURL: URL

        guard let sourceURL = transcription.sourceURL else {
            throw AudioConverterError.fileNotFound
        }

        // Start accessing security-scoped resource if needed
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        logger.info("Source: \(sourceURL.path(percentEncoded: false)), exists: \(FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)))")

        if sourceURL.pathExtension.lowercased() == "wav" {
            // Recording output is already WAV — use directly or copy to temp
            let tempFile = tempDir.appendingPathComponent("\(transcription.id.uuidString).wav")
            try FileManager.default.copyItem(at: sourceURL, to: tempFile)
            wavURL = tempFile
        } else {
            let tempFile = tempDir.appendingPathComponent("\(transcription.id.uuidString).wav")
            try await AudioConverter.convertToWAV(input: sourceURL, output: tempFile)
            wavURL = tempFile
        }

        let modelPath = modelManager.modelPath(name: transcription.modelName, kind: .whisper)
        logger.info("Model path: \(modelPath.path(percentEncoded: false)), exists: \(FileManager.default.fileExists(atPath: modelPath.path(percentEncoded: false)))")
        try await whisperBridge.loadModel(path: modelPath)

        let transcribeStart = Date()

        let segments = try await whisperBridge.transcribe(
            audioPath: wavURL,
            language: transcription.language,
            translate: transcription.translateToEnglish
        ) { progress in
            Task { @MainActor in
                transcription.progress = progress
            }
        }

        for whisperSeg in segments {
            let text = whisperSeg.text
            // Skip silence/noise segments
            if text.trimmingCharacters(in: .whitespaces).isEmpty ||
               text.contains("[SILENCE]") ||
               text.contains("[BLANK_AUDIO]") ||
               text.contains("(silence)") ||
               text.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                continue
            }
            let segment = Segment(startTime: whisperSeg.startTime, endTime: whisperSeg.endTime, text: text)
            segment.transcription = transcription
            modelContext.insert(segment)
        }

        // Diarization (if model available)
        if modelManager.isModelDownloaded(name: "diarization-pyannote", kind: .diarization) {
            transcription.status = .diarizing
            do {
                try modelContext.save()
            } catch {
                logger.error("Failed to save context: \(error)")
            }

            let diarizationService = DiarizationService()
            let diarizationModelPath = modelManager.modelPath(name: "diarization-pyannote", kind: .diarization)
            do {
                let results = try await diarizationService.diarize(
                    audioURL: wavURL,
                    segments: transcription.segments,
                    modelURL: diarizationModelPath
                )
                let speakerCount = Set(results.map(\.speakerIndex)).count
                var speakers: [Int: Speaker] = [:]
                for i in 0..<speakerCount {
                    let speaker = Speaker(
                        label: "Speaker \(i + 1)",
                        color: DiarizationService.speakerColors[i % DiarizationService.speakerColors.count]
                    )
                    speaker.transcription = transcription
                    modelContext.insert(speaker)
                    speakers[i] = speaker
                }
                for result in results {
                    if let segment = transcription.segments.first(where: { $0.id == result.segmentID }) {
                        segment.speaker = speakers[result.speakerIndex]
                    }
                }
            } catch {
                transcription.diarizationError = error.localizedDescription
            }
        }

        transcription.transcribeTime = Date().timeIntervalSince(transcribeStart)
        transcription.updatedAt = Date()
        transcription.status = .completed
        transcription.progress = 1.0
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save context: \(error)")
        }
        try? FileManager.default.removeItem(at: wavURL)
    }

    func cancelCurrent() async {
        await whisperBridge.cancel()
    }
}
