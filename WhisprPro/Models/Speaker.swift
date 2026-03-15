import Foundation
import SwiftData

@Model
final class Speaker {
    var id: UUID
    var label: String
    var color: String
    var transcription: Transcription?

    @Relationship(inverse: \Segment.speaker)
    var segments: [Segment]

    init(label: String, color: String) {
        self.id = UUID()
        self.label = label
        self.color = color
        self.segments = []
    }
}
