import Foundation
import SwiftData

enum TranscriptionStatus: String, Codable {
    case pending
    case transcribing
    case diarizing
    case completed
    case failed
}

@Model
final class Transcription {
    var id: UUID
    var title: String
    var sourceURL: URL?
    var language: String
    var modelName: String
    var duration: TimeInterval
    var createdAt: Date
    var status: TranscriptionStatus
    var progress: Double
    var errorMessage: String?
    var diarizationError: String?
    var translateToEnglish: Bool
    var timestampOffset: TimeInterval

    @Relationship(deleteRule: .cascade, inverse: \Segment.transcription)
    var segments: [Segment]

    @Relationship(deleteRule: .cascade, inverse: \Speaker.transcription)
    var speakers: [Speaker]

    init(
        title: String,
        sourceURL: URL? = nil,
        language: String,
        modelName: String,
        duration: TimeInterval
    ) {
        self.id = UUID()
        self.title = title
        self.sourceURL = sourceURL
        self.language = language
        self.modelName = modelName
        self.duration = duration
        self.createdAt = Date()
        self.status = .pending
        self.progress = 0.0
        self.segments = []
        self.speakers = []
        self.translateToEnglish = false
        self.timestampOffset = 0.0
    }
}
