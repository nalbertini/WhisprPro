import Foundation
import AVFoundation

enum AudioConverterError: Error, LocalizedError {
    case unsupportedFormat(String)
    case conversionFailed(String)
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): "Unsupported audio format: \(ext)"
        case .conversionFailed(let msg): "Audio conversion failed: \(msg)"
        case .fileNotFound: "Audio file not found"
        }
    }
}

struct AudioConverter {
    static let supportedExtensions: Set<String> = [
        "mp3", "wav", "m4a", "mp4", "mov", "aac", "flac", "ogg"
    ]

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func convertToWAV(input: URL, output: URL) async throws {
        guard FileManager.default.fileExists(atPath: input.path()) else {
            throw AudioConverterError.fileNotFound
        }
        guard isSupported(input) else {
            throw AudioConverterError.unsupportedFormat(input.pathExtension)
        }

        let asset = AVURLAsset(url: input)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioConverterError.conversionFailed("No audio track found")
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        guard let reader = try? AVAssetReader(asset: asset) else {
            throw AudioConverterError.conversionFailed("Cannot create asset reader")
        }
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(readerOutput)

        guard let writer = try? AVAssetWriter(outputURL: output, fileType: .wav) else {
            throw AudioConverterError.conversionFailed("Cannot create asset writer")
        }
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writer.add(writerInput)

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        await withCheckedContinuation { continuation in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio-converter")) {
                while writerInput.isReadyForMoreMediaData {
                    guard let buffer = readerOutput.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        writer.finishWriting { continuation.resume() }
                        return
                    }
                    writerInput.append(buffer)
                }
            }
        }

        guard writer.status == .completed else {
            throw AudioConverterError.conversionFailed(writer.error?.localizedDescription ?? "Unknown error")
        }
    }

    static func duration(of url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return duration.seconds
    }
}
