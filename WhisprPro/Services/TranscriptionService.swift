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
        if transcription.modelContext == nil {
            modelContext.insert(transcription)
        }
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

        let tempFile = tempDir.appendingPathComponent("\(transcription.id.uuidString).wav")
        // Always convert to 16kHz mono int16 PCM — even WAV files may be in wrong format
        try await AudioConverter.convertToWAV(input: sourceURL, output: tempFile)
        wavURL = tempFile

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

        // Filter and deduplicate segments
        var lastText = ""
        var repeatCount = 0

        for whisperSeg in segments {
            let text = whisperSeg.text.trimmingCharacters(in: .whitespaces)

            // Skip empty/noise segments
            if text.isEmpty || text.count < 2 ||
               text.contains("[SILENCE]") || text.contains("[BLANK_AUDIO]") ||
               text.contains("(silence)") || text.contains("[MUSIC") {
                continue
            }

            // Detect repeated hallucinations (same text 3+ times in a row)
            if text == lastText {
                repeatCount += 1
                if repeatCount >= 2 {
                    logger.debug("Skipping repeated hallucination: \(text)")
                    continue
                }
            } else {
                repeatCount = 0
            }
            lastText = text

            // Skip known hallucination patterns (very short repeated phrases)
            let lowerText = text.lowercased().trimmingCharacters(in: .punctuationCharacters)
            let hallucinations = [
                "grazie", "thanks", "thank you", "bye", "sottotitoli",
                "sottotitoli e revisione", "amara.org", "mohammedweb",
                "silenzio", "applausi", "musica",
            ]
            if hallucinations.contains(lowerText) {
                // Only skip if it's a standalone hallucination (very short segment)
                if whisperSeg.endTime - whisperSeg.startTime < 3.0 {
                    logger.debug("Skipping hallucination: \(text)")
                    continue
                }
            }

            let segment = Segment(startTime: whisperSeg.startTime, endTime: whisperSeg.endTime, text: text)
            segment.transcription = transcription
            modelContext.insert(segment)
        }

        // Diarization is available via "Auto Detect Speakers" button in the inspector

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
