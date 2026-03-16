import Foundation
import ScreenCaptureKit
import AVFoundation
import os

private let logger = Logger(subsystem: "com.whisprpro", category: "SystemAudio")

@Observable
final class SystemAudioService {
    var isRecording = false
    var elapsedTime: TimeInterval = 0

    private var stream: SCStream?
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
        SystemAudioService.appSupportDir.appendingPathComponent("Recordings")
    }()

    func startRecording() async throws {
        // Get available content
        let content = try await SCShareableContent.current

        // We need at least one display to capture system audio
        guard let display = content.displays.first else {
            throw SystemAudioError.noDisplayFound
        }

        // Configure to capture audio only (no video)
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true  // Don't capture our own audio
        config.sampleRate = 16000
        config.channelCount = 1

        // Don't capture video to save resources
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps minimum

        // Prepare output file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("\(UUID().uuidString).wav")
        tempFileURL = tempFile

        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        audioFile = try AVAudioFile(forWriting: tempFile, settings: fileSettings)

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)

        let output = SystemAudioStreamOutput(audioFile: audioFile!)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: DispatchQueue(label: "system-audio"))

        try await stream.startCapture()
        self.stream = stream

        isRecording = true
        elapsedTime = 0

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.elapsedTime += 1.0
        }

        logger.info("System audio recording started")
    }

    func stopRecording() async throws -> URL {
        timer?.invalidate()
        timer = nil

        if let stream {
            try await stream.stopCapture()
        }
        stream = nil
        audioFile = nil
        isRecording = false

        guard let tempFile = tempFileURL else {
            throw SystemAudioError.noRecording
        }

        let fm = FileManager.default
        try fm.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "SystemAudio_\(formatter.string(from: Date())).wav"
        let destination = recordingsDirectory.appendingPathComponent(filename)

        if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: tempFile, to: destination)
        tempFileURL = nil

        let fileSize = (try? fm.attributesOfItem(atPath: destination.path(percentEncoded: false))[.size] as? Int) ?? 0
        logger.info("System audio saved: \(fileSize) bytes")

        return destination
    }
}

private class SystemAudioStreamOutput: NSObject, SCStreamOutput {
    let audioFile: AVAudioFile

    init(audioFile: AVAudioFile) {
        self.audioFile = audioFile
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        guard let formatDesc = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return
        }

        guard let blockBuffer = sampleBuffer.dataBuffer else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let data = dataPointer else { return }

        // Convert to AVAudioPCMBuffer for writing
        let sampleRate = asbd.pointee.mSampleRate
        let channelCount = asbd.pointee.mChannelsPerFrame
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: AVAudioChannelCount(channelCount), interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        // Copy float data
        if let channelData = buffer.floatChannelData?[0] {
            data.withMemoryRebound(to: Float.self, capacity: frameCount) { floatPtr in
                channelData.update(from: floatPtr, count: frameCount)
            }
        }

        do {
            try audioFile.write(from: buffer)
        } catch {
            // Silently handle write errors during streaming
        }
    }
}

enum SystemAudioError: Error, LocalizedError {
    case noDisplayFound
    case noRecording
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplayFound: "No display found for system audio capture"
        case .noRecording: "No recording in progress"
        case .permissionDenied: "Screen Recording permission needed. Open System Settings → Privacy & Security → Screen Recording and enable WhisprPro."
        }
    }
}
