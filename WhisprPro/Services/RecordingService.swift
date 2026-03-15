import Foundation
import AVFoundation
import os

private let logger = Logger(subsystem: "com.whisprpro", category: "Recording")

@Observable
final class RecordingService {
    var isRecording = false
    var isPaused = false
    var elapsedTime: TimeInterval = 0
    var audioLevel: Float = 0

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var timer: Timer?
    private var tempFileURL: URL?

    private static let appSupportDir: URL = {
        guard let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory not available")
        }
        return url.appendingPathComponent("WhisprPro")
    }()

    let recordingsDirectory: URL = {
        RecordingService.appSupportDir.appendingPathComponent("Recordings")
    }()

    func availableInputDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    func startRecording(deviceID: String? = nil) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz mono PCM (what whisper.cpp expects)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw RecordingError.deviceNotAvailable
        }

        // Create converter from mic format to 16kHz mono
        guard let audioConverter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw RecordingError.deviceNotAvailable
        }
        self.converter = audioConverter

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("\(UUID().uuidString).wav")
        tempFileURL = tempFile

        let audioFile = try AVAudioFile(forWriting: tempFile, settings: outputFormat.settings)
        self.audioFile = audioFile

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, !self.isPaused else { return }

            // Calculate audio level from input buffer
            if let channelData = buffer.floatChannelData?[0] {
                let frameLength = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frameLength {
                    sum += abs(channelData[i])
                }
                self.audioLevel = sum / Float(max(frameLength, 1))
            }

            // Convert to 16kHz mono and write
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * outputFormat.sampleRate / inputFormat.sampleRate
            )
            guard frameCapacity > 0,
                  let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
                return
            }

            var error: NSError?
            audioConverter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if let error {
                logger.error("Conversion error: \(error)")
                return
            }

            do {
                try audioFile.write(from: convertedBuffer)
            } catch {
                logger.error("Error writing audio: \(error)")
            }
        }

        try engine.start()
        self.audioEngine = engine
        isRecording = true
        isPaused = false
        elapsedTime = 0

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, !self.isPaused else { return }
            self.elapsedTime += 1.0
        }

        logger.info("Recording started - input: \(inputFormat.sampleRate)Hz \(inputFormat.channelCount)ch → output: 16000Hz 1ch")
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    func stopRecording() throws -> URL {
        timer?.invalidate()
        timer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        converter = nil

        isRecording = false
        isPaused = false

        guard let tempFile = tempFileURL else {
            throw RecordingError.noRecording
        }

        // Verify file has content
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempFile.path())[.size] as? Int) ?? 0
        logger.info("Recording stopped - file size: \(fileSize) bytes")

        let fm = FileManager.default
        try fm.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "Recording_\(formatter.string(from: Date())).wav"
        let destination = recordingsDirectory.appendingPathComponent(filename)

        if fm.fileExists(atPath: destination.path()) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: tempFile, to: destination)
        tempFileURL = nil

        return destination
    }
}

enum RecordingError: Error, LocalizedError {
    case noRecording
    case deviceNotAvailable

    var errorDescription: String? {
        switch self {
        case .noRecording: "No recording in progress"
        case .deviceNotAvailable: "Audio input device not available"
        }
    }
}
