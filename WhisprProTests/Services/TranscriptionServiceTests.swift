import Testing
import SwiftData
import Foundation
@testable import WhisprPro

@Suite("TranscriptionService Tests")
struct TranscriptionServiceTests {
    @Test func createTranscriptionFromFile() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Transcription.self, Segment.self, Speaker.self, MLModelInfo.self, configurations: config)
        let context = ModelContext(container)
        let service = TranscriptionService(modelContext: context)
        let transcription = service.createTranscription(title: "Test File", sourceURL: URL(filePath: "/tmp/test.mp3"), language: "en", modelName: "tiny", duration: 60.0)
        #expect(transcription.title == "Test File")
        #expect(transcription.status == .pending)
        #expect(transcription.language == "en")
    }

    @Test func enqueueSetsStatusToPending() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Transcription.self, Segment.self, Speaker.self, MLModelInfo.self, configurations: config)
        let context = ModelContext(container)
        let service = TranscriptionService(modelContext: context)
        let transcription = service.createTranscription(title: "Queue Test", sourceURL: nil, language: "en", modelName: "tiny", duration: 30.0)
        #expect(transcription.status == .pending)
    }
}
