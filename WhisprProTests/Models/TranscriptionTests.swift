import Testing
import SwiftData
@testable import WhisprPro

@Suite("Transcription Model Tests")
struct TranscriptionTests {
    @Test func createTranscription() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Transcription.self, Segment.self, Speaker.self, configurations: config)
        let context = ModelContext(container)
        let transcription = Transcription(title: "Test Recording", language: "en", modelName: "tiny", duration: 120.0)
        context.insert(transcription)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<Transcription>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Test Recording")
        #expect(fetched.first?.status == .pending)
        #expect(fetched.first?.segments.isEmpty == true)
    }

    @Test func statusTransitions() {
        let t = Transcription(title: "Test", language: "en", modelName: "tiny", duration: 60)
        #expect(t.status == .pending)
        t.status = .transcribing
        #expect(t.status == .transcribing)
        t.status = .completed
        #expect(t.status == .completed)
    }
}
