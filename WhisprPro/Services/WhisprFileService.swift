import Foundation
import os

private let logger = Logger(subsystem: "com.whisprpro", category: "WhisprFile")

struct WhisprFileService {

    // MARK: - Export

    struct WhisprTranscript: Codable {
        let version: Int
        let title: String
        let language: String
        let modelName: String
        let duration: TimeInterval
        let createdAt: Date
        let segments: [WhisprSegment]
        let speakers: [WhisprSpeaker]
    }

    struct WhisprSegment: Codable {
        let startTime: TimeInterval
        let endTime: TimeInterval
        let text: String
        let isEdited: Bool
        let isStarred: Bool
        let speakerLabel: String?
    }

    struct WhisprSpeaker: Codable {
        let label: String
        let color: String
    }

    /// Export a transcription to .whispr format (ZIP containing JSON + audio)
    static func exportWhispr(transcription: Transcription) throws -> URL {
        let sortedSegments = transcription.segments.sorted { $0.startTime < $1.startTime }

        let transcript = WhisprTranscript(
            version: 1,
            title: transcription.title,
            language: transcription.language,
            modelName: transcription.modelName,
            duration: transcription.duration,
            createdAt: transcription.createdAt,
            segments: sortedSegments.map { seg in
                WhisprSegment(
                    startTime: seg.startTime,
                    endTime: seg.endTime,
                    text: seg.text,
                    isEdited: seg.isEdited,
                    isStarred: seg.isStarred,
                    speakerLabel: seg.speaker?.label
                )
            },
            speakers: transcription.speakers.map { speaker in
                WhisprSpeaker(label: speaker.label, color: speaker.color)
            }
        )

        // Create temp directory for packaging
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("whispr-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Write JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(transcript)
        try jsonData.write(to: tempDir.appendingPathComponent("transcript.json"))

        // Copy audio if available
        if let sourceURL = transcription.sourceURL,
           FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)) {
            let audioExt = sourceURL.pathExtension
            try FileManager.default.copyItem(
                at: sourceURL,
                to: tempDir.appendingPathComponent("audio.\(audioExt)")
            )
        }

        // Create ZIP using NSFileCoordinator
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(transcription.title).whispr")

        // Remove existing file
        try? FileManager.default.removeItem(at: outputURL)

        let coordinator = NSFileCoordinator()
        var error: NSError?
        var resultURL: URL?

        coordinator.coordinate(readingItemAt: tempDir, options: .forUploading, error: &error) { zippedURL in
            do {
                try FileManager.default.copyItem(at: zippedURL, to: outputURL)
                resultURL = outputURL
            } catch {
                logger.error("Failed to create whispr file: \(error)")
            }
        }

        // Cleanup temp dir
        try? FileManager.default.removeItem(at: tempDir)

        if let error {
            throw error
        }

        guard let url = resultURL else {
            throw WhisprFileError.exportFailed
        }

        logger.info("Exported .whispr: \(url.lastPathComponent)")
        return url
    }

    // MARK: - Import

    /// Import a .whispr file, returns the transcript data and optional audio URL
    static func importWhispr(url: URL) throws -> (transcript: WhisprTranscript, audioURL: URL?) {
        // Unzip the .whispr file
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("whispr-import-\(UUID().uuidString)")

        // First copy and rename to .zip for extraction
        let zipCopy = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).zip")
        try FileManager.default.copyItem(at: url, to: zipCopy)

        // Use Process to unzip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipCopy.path(percentEncoded: false), "-d", tempDir.path(percentEncoded: false)]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(at: zipCopy)

        // Read transcript.json
        let jsonURL = tempDir.appendingPathComponent("transcript.json")
        guard FileManager.default.fileExists(atPath: jsonURL.path(percentEncoded: false)) else {
            try? FileManager.default.removeItem(at: tempDir)
            throw WhisprFileError.invalidFormat
        }

        let jsonData = try Data(contentsOf: jsonURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let transcript = try decoder.decode(WhisprTranscript.self, from: jsonData)

        // Find audio file
        let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let audioFile = contents.first { $0.lastPathComponent.hasPrefix("audio.") }

        // Copy audio to permanent location if found
        var permanentAudioURL: URL?
        if let audioFile {
            let recordingsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("WhisprPro/Recordings")
            try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
            let destURL = recordingsDir.appendingPathComponent("imported_\(transcript.title).\(audioFile.pathExtension)")
            if FileManager.default.fileExists(atPath: destURL.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: audioFile, to: destURL)
            permanentAudioURL = destURL
        }

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)

        logger.info("Imported .whispr: \(transcript.title)")
        return (transcript, permanentAudioURL)
    }
}

enum WhisprFileError: Error, LocalizedError {
    case exportFailed
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .exportFailed: "Failed to create .whispr file"
        case .invalidFormat: "Invalid .whispr file format"
        }
    }
}
