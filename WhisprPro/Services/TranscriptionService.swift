import Foundation
import SwiftData

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
        duration: TimeInterval
    ) -> Transcription {
        Transcription(title: title, sourceURL: sourceURL, language: language, modelName: modelName, duration: duration)
    }

    func enqueue(_ transcription: Transcription) async {
        modelContext.insert(transcription)
        try? modelContext.save()
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
        try? modelContext.save()

        if !pendingQueue.isEmpty {
            await processNextIfIdle()
        }
    }

    private func processTranscription(_ transcription: Transcription) async throws {
        transcription.status = .transcribing
        transcription.progress = 0.0
        try? modelContext.save()

        let tempDir = FileManager.default.temporaryDirectory
        let wavURL = tempDir.appendingPathComponent("\(transcription.id.uuidString).wav")

        if let sourceURL = transcription.sourceURL {
            try await AudioConverter.convertToWAV(input: sourceURL, output: wavURL)
        }

        let modelPath = modelManager.modelPath(name: transcription.modelName, kind: .whisper)
        try await whisperBridge.loadModel(path: modelPath)

        let segments = try await whisperBridge.transcribe(
            audioPath: wavURL,
            language: transcription.language,
            translate: false
        ) { progress in
            Task { @MainActor in
                transcription.progress = progress
            }
        }

        for whisperSeg in segments {
            let segment = Segment(startTime: whisperSeg.startTime, endTime: whisperSeg.endTime, text: whisperSeg.text)
            segment.transcription = transcription
            modelContext.insert(segment)
        }

        // Diarization (if model available)
        if modelManager.isModelDownloaded(name: "diarization-pyannote", kind: .diarization) {
            transcription.status = .diarizing
            try? modelContext.save()

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

        transcription.status = .completed
        transcription.progress = 1.0
        try? modelContext.save()
        try? FileManager.default.removeItem(at: wavURL)
    }

    func cancelCurrent() async {
        await whisperBridge.cancel()
    }
}
