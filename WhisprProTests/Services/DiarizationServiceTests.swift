import Testing
import Foundation
@testable import WhisprPro

@Suite("DiarizationService Tests")
struct DiarizationServiceTests {
    @Test func assignSpeakersToSegments() {
        let speakerTimeline: [(start: TimeInterval, end: TimeInterval, speakerIndex: Int)] = [
            (0.0, 3.0, 0),
            (3.0, 6.0, 1),
            (6.0, 9.0, 0),
        ]

        let segments = [
            (start: 0.5, end: 2.5),
            (start: 3.5, end: 5.5),
            (start: 6.5, end: 8.5),
        ]

        let assignments = DiarizationService.assignSpeakers(
            speakerTimeline: speakerTimeline,
            segments: segments
        )

        #expect(assignments.count == 3)
        #expect(assignments[0] == 0)
        #expect(assignments[1] == 1)
        #expect(assignments[2] == 0)
    }

    @Test func speakerColors() {
        let colors = DiarizationService.speakerColors
        #expect(colors.count >= 6)
        #expect(colors[0].hasPrefix("#"))
    }
}
