import Foundation
import os

private let logger = Logger(subsystem: "com.whisprpro", category: "ModelManager")

struct WhisperModelDefinition {
    let name: String
    let size: Int64
    let downloadURL: URL
}

final class ModelManager: Sendable {
    static let availableWhisperModels: [WhisperModelDefinition] = [
        WhisperModelDefinition(name: "tiny", size: 75_000_000, downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin")!),
        WhisperModelDefinition(name: "base", size: 142_000_000, downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!),
        WhisperModelDefinition(name: "small", size: 466_000_000, downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")!),
        WhisperModelDefinition(name: "medium", size: 1_500_000_000, downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!),
        WhisperModelDefinition(name: "large-v3", size: 2_900_000_000, downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!),
        WhisperModelDefinition(name: "large-v3-turbo", size: 1_600_000_000, downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!),
    ]

    private static let appSupportDir: URL = {
        guard let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory not available")
        }
        return url.appendingPathComponent("WhisprPro")
    }()

    init() {}

    func modelsDirectory(for kind: ModelKind) -> URL {
        Self.appSupportDir.appendingPathComponent("Models/\(kind.rawValue)")
    }

    func modelPath(name: String, kind: ModelKind) -> URL {
        let filename = kind == .whisper ? "ggml-\(name).bin" : "\(name).mlmodel"
        return modelsDirectory(for: kind).appendingPathComponent(filename)
    }

    func isModelDownloaded(name: String, kind: ModelKind) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(name: name, kind: kind).path(percentEncoded: false))
    }

    func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: modelsDirectory(for: .whisper), withIntermediateDirectories: true)
        try fm.createDirectory(at: modelsDirectory(for: .diarization), withIntermediateDirectories: true)
    }

    func downloadModel(definition: WhisperModelDefinition, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try ensureDirectoriesExist()
        let destination = modelPath(name: definition.name, kind: .whisper)

        let delegate = DownloadDelegate(progressHandler: progress)
        let (fileURL, _) = try await delegate.download(from: definition.downloadURL)

        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: fileURL, to: destination)
        progress(1.0)
        return destination
    }

    func deleteModel(name: String, kind: ModelKind) throws {
        let path = modelPath(name: name, kind: kind)
        if FileManager.default.fileExists(atPath: path.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: path)
        }
    }
}


private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progressHandler: (Double) -> Void
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var tempFileURL: URL?

    init(progressHandler: @escaping (Double) -> Void) {
        self.progressHandler = progressHandler
    }

    func download(from url: URL) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Move to a temp location that won't be deleted when this method returns
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".bin")
        do {
            try FileManager.default.moveItem(at: location, to: tempFile)
            tempFileURL = tempFile
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
        } else if let tempFileURL, let response = task.response {
            continuation?.resume(returning: (tempFileURL, response))
        } else {
            continuation?.resume(throwing: ModelManagerError.downloadFailed)
        }
        continuation = nil
    }
}

enum ModelManagerError: Error, LocalizedError {
    case downloadFailed
    case modelNotFound
    var errorDescription: String? {
        switch self {
        case .downloadFailed: "Failed to download model"
        case .modelNotFound: "Model file not found"
        }
    }
}
