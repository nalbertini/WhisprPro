import Foundation
import AVFoundation
import ScreenCaptureKit
import os

private let logger = Logger(subsystem: "com.whisprpro", category: "MixedAudio")

@Observable
final class MixedAudioService {
    var isRecording = false
    var elapsedTime: TimeInterval = 0
    var audioLevel: Float = 0
    var systemAudioAvailable = false

    private var micEngine: AVAudioEngine?
    private var micConverter: AVAudioConverter?
    private var systemStream: SCStream?
    private var audioFile: AVAudioFile?
    private var timer: Timer?
    private var tempFileURL: URL?

    // Buffers for mixing
    private var micBuffer: [Float] = []
    private var systemBuffer: [Float] = []
    private let sampleRate: Double = 16000
    private let bufferLock = NSLock()

    private static let appSupportDir: URL = {
        guard let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory not available")
        }
        return url.appendingPathComponent("WhisprPro")
    }()

    let recordingsDirectory: URL = {
        MixedAudioService.appSupportDir.appendingPathComponent("Recordings")
    }()

    func startRecording() async throws {
        // Setup output file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("\(UUID().uuidString).wav")
        tempFileURL = tempFile

        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        audioFile = try AVAudioFile(forWriting: tempFile, settings: fileSettings)

        // Start mic capture
        try startMicCapture()

        // Try system audio — fall back to mic-only if denied
        do {
            try await startSystemCapture()
            systemAudioAvailable = true
            logger.info("Mixed recording: mic + system audio")
        } catch {
            systemAudioAvailable = false
            logger.warning("System audio unavailable — recording mic only. Grant Screen Recording in System Settings for full meeting capture.")
        }

        isRecording = true
        elapsedTime = 0

        // Timer must be on main thread
        await MainActor.run {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.elapsedTime += 1.0
            }
        }

        // Start mixing loop on main thread too
        await MainActor.run {
            startMixingLoop()
        }

        logger.info("Mixed recording started (mic + system, systemAudio: \(self.systemAudioAvailable))")
    }

    private func startMicCapture() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { throw MixedAudioError.setupFailed }

        guard let converter = AVAudioConverter(from: inputFormat, to: processingFormat) else {
            throw MixedAudioError.setupFailed
        }
        micConverter = converter

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Calculate level
            if let data = buffer.floatChannelData?[0] {
                let count = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<count { sum += abs(data[i]) }
                self.audioLevel = sum / Float(max(count, 1))
            }

            // Convert to 16kHz mono
            let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * processingFormat.sampleRate / inputFormat.sampleRate)
            guard frameCapacity > 0,
                  let convertedBuffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCapacity) else { return }

            var error: NSError?
            var hasData = true
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if hasData {
                    hasData = false
                    outStatus.pointee = .haveData
                    return buffer
                }
                outStatus.pointee = .noDataNow
                return nil
            }

            if error == nil, let channelData = convertedBuffer.floatChannelData?[0] {
                let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(convertedBuffer.frameLength)))
                self.bufferLock.lock()
                self.micBuffer.append(contentsOf: samples)
                self.bufferLock.unlock()
            }
        }

        try engine.start()
        micEngine = engine
    }

    private func startSystemCapture() async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw MixedAudioError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(sampleRate)
        config.channelCount = 1
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let output = SystemAudioOutput { [weak self] samples in
            self?.bufferLock.lock()
            self?.systemBuffer.append(contentsOf: samples)
            self?.bufferLock.unlock()
        }
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: DispatchQueue(label: "system-audio-mix"))
        try await stream.startCapture()
        systemStream = stream
    }

    private func startMixingLoop() {
        // Mix and write every 0.5 seconds
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self, self.isRecording else {
                timer.invalidate()
                return
            }
            self.mixAndWrite()
        }
    }

    private func mixAndWrite() {
        bufferLock.lock()
        let mic = micBuffer
        let sys = systemBuffer
        micBuffer.removeAll(keepingCapacity: true)
        systemBuffer.removeAll(keepingCapacity: true)
        bufferLock.unlock()

        guard !mic.isEmpty || !sys.isEmpty else { return }

        // Mix: take the longer buffer, add the shorter one
        let length = max(mic.count, sys.count)
        var mixed = [Float](repeating: 0, count: length)

        for i in 0..<length {
            let m: Float = i < mic.count ? mic[i] : 0
            let s: Float = i < sys.count ? sys[i] : 0
            mixed[i] = min(max((m + s) * 0.8, -1.0), 1.0) // Mix with slight attenuation
        }

        // Write to file
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(mixed.count)) else { return }

        buffer.frameLength = AVAudioFrameCount(mixed.count)
        if let channelData = buffer.floatChannelData?[0] {
            for i in 0..<mixed.count {
                channelData[i] = mixed[i]
            }
        }

        // Apply gain boost
        if let data = buffer.floatChannelData?[0] {
            let count = Int(buffer.frameLength)
            let gain: Float = 2.0
            for i in 0..<count {
                data[i] = min(max(data[i] * gain, -1.0), 1.0)
            }
        }

        do {
            try audioFile?.write(from: buffer)
        } catch {
            logger.error("Write error: \(error)")
        }
    }

    func stopRecording() async throws -> URL {
        timer?.invalidate()
        timer = nil

        micEngine?.inputNode.removeTap(onBus: 0)
        micEngine?.stop()
        micEngine = nil
        micConverter = nil

        if let stream = systemStream {
            try await stream.stopCapture()
        }
        systemStream = nil

        // Write remaining buffers
        mixAndWrite()
        audioFile = nil
        isRecording = false

        guard let tempFile = tempFileURL else {
            throw MixedAudioError.noRecording
        }

        let fm = FileManager.default
        try fm.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "Meeting_\(formatter.string(from: Date())).wav"
        let destination = recordingsDirectory.appendingPathComponent(filename)

        if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: tempFile, to: destination)
        tempFileURL = nil

        logger.info("Mixed recording saved: \(destination.lastPathComponent)")
        return destination
    }
}

private class SystemAudioOutput: NSObject, SCStreamOutput {
    let handler: ([Float]) -> Void

    init(handler: @escaping ([Float]) -> Void) {
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let blockBuffer = sampleBuffer.dataBuffer else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let data = dataPointer else { return }
        let frameCount = length / MemoryLayout<Float>.size

        var samples = [Float](repeating: 0, count: frameCount)
        data.withMemoryRebound(to: Float.self, capacity: frameCount) { floatPtr in
            for i in 0..<frameCount { samples[i] = floatPtr[i] }
        }

        handler(samples)
    }
}

enum MixedAudioError: Error, LocalizedError {
    case setupFailed
    case noDisplay
    case noRecording

    var errorDescription: String? {
        switch self {
        case .setupFailed: "Failed to setup audio capture"
        case .noDisplay: "No display found for system audio"
        case .noRecording: "No recording in progress"
        }
    }
}
