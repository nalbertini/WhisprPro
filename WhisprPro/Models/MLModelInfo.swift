import Foundation
import SwiftData

enum ModelKind: String, Codable {
    case whisper
    case diarization
}

@Model
final class MLModelInfo {
    var name: String
    var kind: ModelKind
    var size: Int64
    var isDownloaded: Bool
    var localURL: URL?
    @Transient var downloadProgress: Double = 0.0

    init(name: String, kind: ModelKind, size: Int64) {
        self.name = name
        self.kind = kind
        self.size = size
        self.isDownloaded = false
    }
}
