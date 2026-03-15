import Foundation
import SwiftData

@Model
final class Segment {
    var id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var isEdited: Bool = false
    var isStarred: Bool = false
    var transcription: Transcription?
    var speaker: Speaker?

    init(startTime: TimeInterval, endTime: TimeInterval, text: String) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.isEdited = false
        self.isStarred = false
    }
}
