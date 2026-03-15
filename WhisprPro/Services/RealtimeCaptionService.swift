import Foundation
import AVFoundation
import os

private let logger = Logger(subsystem: "com.whisprpro", category: "RealtimeCaptions")

@Observable
final class RealtimeCaptionService {
    var isActive = false
    var currentText = ""
    var segments: [(time: Date, text: String)] = []

    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var audioBuffer: [Float] = []
    private let whisperBridge = WhisperBridge()
    private let modelManager = ModelManager()
    private var processingTask: Task<Void, Never>?

    // Buffer 8 seconds of audio, process every 4 seconds with 4s overlap
    private let sampleRate: Double = 16000
    private let windowDuration: Double = 8.0
    private let processingInterval: Double = 4.0

    var language: String = "auto"

    /// Patterns that indicate noise/silence, not real speech
    private static let noisePatterns: [String] = [
        "[MUSIC", "[BLANK_AUDIO]", "[SILENCE]", "(silence)", "(music)",
        "[laughter]", "[applause]", "[noise]", "[звук", "[музыка",
        "[놀", "[音楽",
    ]

    private static func isNoise(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count < 3 { return true }
        // Check if text is mostly brackets/tags
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") { return true }
        if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") { return true }
        for pattern in noisePatterns {
            if trimmed.localizedCaseInsensitiveContains(pattern) { return true }
        }
        return false
    }

    func start(modelName: String = "tiny") async throws {
        // Load model
        let modelPath = modelManager.modelPath(name: modelName, kind: .whisper)
        let exists = modelManager.isModelDownloaded(name: modelName, kind: .whisper)
        logger.info("Model \(modelName) path: \(modelPath.path(percentEncoded: false)), exists: \(exists)")
        guard exists else {
            throw RealtimeCaptionError.modelNotDownloaded
        }
        try await whisperBridge.loadModel(path: modelPath)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw RealtimeCaptionError.audioSetupFailed
        }

        guard let audioConverter = AVAudioConverter(from: inputFormat, to: processingFormat) else {
            throw RealtimeCaptionError.audioSetupFailed
        }
        self.converter = audioConverter

        audioBuffer.removeAll()
        segments.removeAll()
        currentText = ""

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * processingFormat.sampleRate / inputFormat.sampleRate
            )
            guard frameCapacity > 0,
                  let convertedBuffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCapacity) else {
                return
            }

            var error: NSError?
            audioConverter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil, let channelData = convertedBuffer.floatChannelData?[0] {
                let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(convertedBuffer.frameLength)))
                self.audioBuffer.append(contentsOf: samples)
            }
        }

        try engine.start()
        self.audioEngine = engine
        isActive = true

        logger.info("Realtime captions started with model: \(modelName)")

        // Start processing loop
        processingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.processingInterval ?? 3.0))
                await self?.processCurrentBuffer()
            }
        }
    }

    func stop() {
        processingTask?.cancel()
        processingTask = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        converter = nil

        isActive = false
        logger.info("Realtime captions stopped")
    }

    private func processCurrentBuffer() async {
        let windowSamples = Int(sampleRate * windowDuration)

        guard audioBuffer.count >= windowSamples else { return }

        // Take the last windowDuration seconds of audio
        let window = Array(audioBuffer.suffix(windowSamples))

        // Trim buffer to keep only overlap
        let overlapSamples = Int(sampleRate * (windowDuration - processingInterval))
        if audioBuffer.count > overlapSamples {
            audioBuffer = Array(audioBuffer.suffix(overlapSamples))
        }

        // VAD: Skip if audio energy is too low (silence)
        let energy = window.reduce(Float(0)) { $0 + $1 * $1 } / Float(window.count)
        let rms = sqrt(energy)
        if rms < 0.001 {
            logger.debug("Skipping silent window (RMS: \(rms))")
            return
        }

        // Write to temp WAV file for whisper
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("realtime_\(UUID().uuidString).wav")

        do {
            try writeWAV(samples: window, to: tempURL)

            let result = try await whisperBridge.transcribe(
                audioPath: tempURL,
                language: language,
                translate: false
            ) { _ in }

            // Filter out noise/silence segments
            let cleanSegments = result.filter { !Self.isNoise($0.text) }
            let text = cleanSegments.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)

            // Skip empty or exact duplicates
            let isDuplicate = text == currentText || segments.last?.text == text

            if !text.isEmpty && !isDuplicate {
                await MainActor.run {
                    currentText = text
                    segments.append((time: Date(), text: text))
                    if segments.count > 50 {
                        segments.removeFirst()
                    }
                }
            }

            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            logger.error("Realtime transcription error: \(error)")
        }
    }

    private func writeWAV(samples: [Float], to url: URL) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return }

        // Write as int16 PCM WAV (what whisper expects)
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let file = try AVAudioFile(forWriting: url, settings: fileSettings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channelData = buffer.floatChannelData![0]
        for i in 0..<samples.count {
            channelData[i] = samples[i]
        }
        try file.write(from: buffer)
    }
}

enum RealtimeCaptionError: Error, LocalizedError {
    case modelNotDownloaded
    case audioSetupFailed

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded: "Please download a Whisper model first"
        case .audioSetupFailed: "Failed to setup audio capture"
        }
    }
}
