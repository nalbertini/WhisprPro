import Testing
import Foundation
@testable import WhisprPro

@Suite("ExportService Tests")
struct ExportServiceTests {
    private func makeSampleSegments() -> [(start: TimeInterval, end: TimeInterval, text: String, speaker: String?)] {
        [
            (0.0, 2.5, "Hello world", "Speaker 1"),
            (2.5, 5.0, "How are you", "Speaker 2"),
            (5.0, 8.0, "I am fine", "Speaker 1"),
        ]
    }

    @Test func exportSRT() {
        let segments = makeSampleSegments()
        let srt = ExportService.toSRT(segments: segments)

        #expect(srt.contains("1\n00:00:00,000 --> 00:00:02,500"))
        #expect(srt.contains("[Speaker 1] Hello world"))
        #expect(srt.contains("2\n00:00:02,500 --> 00:00:05,000"))
    }

    @Test func exportVTT() {
        let segments = makeSampleSegments()
        let vtt = ExportService.toVTT(segments: segments)

        #expect(vtt.hasPrefix("WEBVTT"))
        #expect(vtt.contains("00:00:00.000 --> 00:00:02.500"))
    }

    @Test func exportTXT() {
        let segments = makeSampleSegments()
        let txt = ExportService.toTXT(segments: segments, includeSpeakers: true, includeTimestamps: true)

        #expect(txt.contains("[00:00:00] Speaker 1: Hello world"))
    }

    @Test func exportJSON() throws {
        let segments = makeSampleSegments()
        let json = ExportService.toJSON(
            title: "Test",
            language: "en",
            segments: segments
        )
        #expect(json.contains("\"title\":\"Test\""))
        #expect(json.contains("\"text\":\"Hello world\""))
    }
}
