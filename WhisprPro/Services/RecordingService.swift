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
        let format = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        )!

        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("\(UUID().uuidString).wav")
        tempFileURL = tempFile

        let audioFile = try AVAudioFile(
            forWriting: tempFile,
            settings: format.settings
        )
        self.audioFile = audioFile

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputNode.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            guard let self, !self.isPaused else { return }

            // Calculate audio level
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0
            if let data = channelData {
                for i in 0..<frameLength {
                    sum += abs(data[i])
                }
            }
            self.audioLevel = sum / Float(frameLength)

            // Write to file (convert format if needed)
            do {
                try audioFile.write(from: buffer)
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

        isRecording = false
        isPaused = false

        // Move to permanent storage
        guard let tempFile = tempFileURL else {
            throw RecordingError.noRecording
        }

        let fm = FileManager.default
        try fm.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "Recording_\(formatter.string(from: Date())).wav"
        let destination = recordingsDirectory.appendingPathComponent(filename)

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
