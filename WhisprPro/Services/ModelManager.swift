import Foundation

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

    private let appSupportDir: URL

    init() {
        self.appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("WhisprPro")
    }

    func modelsDirectory(for kind: ModelKind) -> URL {
        appSupportDir.appendingPathComponent("Models/\(kind.rawValue)")
    }

    func modelPath(name: String, kind: ModelKind) -> URL {
        let filename = kind == .whisper ? "ggml-\(name).bin" : "\(name).mlmodel"
        return modelsDirectory(for: kind).appendingPathComponent(filename)
    }

    func isModelDownloaded(name: String, kind: ModelKind) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(name: name, kind: kind).path())
    }

    func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: modelsDirectory(for: .whisper), withIntermediateDirectories: true)
        try fm.createDirectory(at: modelsDirectory(for: .diarization), withIntermediateDirectories: true)
    }

    func downloadModel(definition: WhisperModelDefinition, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try ensureDirectoriesExist()
        let destination = modelPath(name: definition.name, kind: .whisper)
        let delegate = DownloadProgressDelegate(progressHandler: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (tempURL, response) = try await session.download(from: definition.downloadURL)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ModelManagerError.downloadFailed
        }
        if FileManager.default.fileExists(atPath: destination.path()) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        progress(1.0)
        return destination
    }

    func deleteModel(name: String, kind: ModelKind) throws {
        let path = modelPath(name: name, kind: kind)
        if FileManager.default.fileExists(atPath: path.path()) {
            try FileManager.default.removeItem(at: path)
        }
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progressHandler: (Double) -> Void
    init(progressHandler: @escaping (Double) -> Void) { self.progressHandler = progressHandler }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressHandler(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
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
