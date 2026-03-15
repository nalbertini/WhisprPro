import Foundation
import os

private let logger = Logger(subsystem: "com.whisprpro", category: "YouTube")

actor YouTubeService {
    enum YouTubeError: Error, LocalizedError {
        case invalidURL
        case downloadFailed(String)
        case ytDlpNotFound

        var errorDescription: String? {
            switch self {
            case .invalidURL: "Invalid YouTube URL"
            case .downloadFailed(let msg): "Download failed: \(msg)"
            case .ytDlpNotFound: "yt-dlp not found. Install it with: brew install yt-dlp"
            }
        }
    }

    /// Check if yt-dlp is installed
    static func isAvailable() -> Bool {
        let paths = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private static func ytDlpPath() -> String? {
        let paths = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Validate YouTube URL
    static func isYouTubeURL(_ string: String) -> Bool {
        let patterns = [
            "youtube.com/watch",
            "youtu.be/",
            "youtube.com/shorts/",
            "youtube.com/live/"
        ]
        return patterns.contains { string.contains($0) }
    }

    /// Get video title from URL
    func getTitle(url: String) async throws -> String {
        guard let ytDlp = Self.ytDlpPath() else {
            throw YouTubeError.ytDlpNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytDlp)
        process.arguments = ["--get-title", "--no-warnings", url]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let title = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "YouTube Video"

        return title
    }

    /// Download audio from YouTube URL, returns path to WAV file
    func downloadAudio(
        url: String,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> (audioURL: URL, title: String, duration: TimeInterval) {
        guard Self.isYouTubeURL(url) else {
            throw YouTubeError.invalidURL
        }

        guard let ytDlp = Self.ytDlpPath() else {
            throw YouTubeError.ytDlpNotFound
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisprpro-yt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let outputTemplate = tempDir.appendingPathComponent("%(title)s.%(ext)s").path(percentEncoded: false)

        logger.info("Downloading audio from: \(url)")
        progress("Fetching video info...")

        // Run yt-dlp on background thread with async continuation
        let exitCode = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: ytDlp)
                    proc.arguments = [
                        "-x",
                        "--audio-format", "wav",
                        "--audio-quality", "0",
                        "--no-playlist",
                        "--no-warnings",
                        "--newline",
                        "-o", outputTemplate,
                        url
                    ]

                    let outPipe = Pipe()
                    let errPipe = Pipe()
                    proc.standardOutput = outPipe
                    proc.standardError = errPipe

                    outPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty,
                              let line = String(data: data, encoding: .utf8)?
                                .trimmingCharacters(in: .whitespacesAndNewlines),
                              !line.isEmpty else { return }
                        if line.contains("[download]") && line.contains("%") {
                            progress(line)
                        } else if line.contains("[ExtractAudio]") {
                            progress("Converting to audio...")
                        }
                    }

                    proc.terminationHandler = { p in
                        outPipe.fileHandleForReading.readabilityHandler = nil
                        continuation.resume(returning: p.terminationStatus)
                    }

                    try proc.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        guard exitCode == 0 else {
            throw YouTubeError.downloadFailed("yt-dlp exited with code \(exitCode)")
        }

        // Find the downloaded file
        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        guard let audioFile = files.first(where: { $0.pathExtension.lowercased() == "wav" }) ?? files.first else {
            throw YouTubeError.downloadFailed("No audio file found after download")
        }

        // Get title from filename
        let title = audioFile.deletingPathExtension().lastPathComponent

        // Get duration
        let duration = (try? await AudioConverter.duration(of: audioFile)) ?? 0

        logger.info("Downloaded: \(title) (\(Int(duration))s)")
        progress("Download complete!")

        return (audioURL: audioFile, title: title, duration: duration)
    }
}
