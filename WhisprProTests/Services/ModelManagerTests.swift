import Testing
import Foundation
@testable import WhisprPro

@Suite("ModelManager Tests")
struct ModelManagerTests {
    @Test func modelsDirectory() {
        let manager = ModelManager()
        let whisperDir = manager.modelsDirectory(for: .whisper)
        #expect(whisperDir.path().contains("WhisprPro/Models/whisper"))
        let diarizationDir = manager.modelsDirectory(for: .diarization)
        #expect(diarizationDir.path().contains("WhisprPro/Models/diarization"))
    }

    @Test func availableWhisperModels() {
        let models = ModelManager.availableWhisperModels
        #expect(models.count == 6)
        #expect(models.first?.name == "tiny")
        #expect(models.last?.name == "large-v3-turbo")
    }

    @Test func modelPath() {
        let manager = ModelManager()
        let path = manager.modelPath(name: "tiny", kind: .whisper)
        #expect(path.lastPathComponent == "ggml-tiny.bin")
    }

    @Test func isModelDownloaded() {
        let manager = ModelManager()
        let result = manager.isModelDownloaded(name: "nonexistent", kind: .whisper)
        #expect(result == false)
    }
}
