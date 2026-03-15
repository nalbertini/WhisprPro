import Testing
import Foundation
@testable import WhisprPro

@Suite("RecordingService Tests")
struct RecordingServiceTests {
    @Test func recordingsDirectory() {
        let service = RecordingService()
        let dir = service.recordingsDirectory
        #expect(dir.path().contains("WhisprPro/Recordings"))
    }

    @Test func initialState() {
        let service = RecordingService()
        #expect(service.isRecording == false)
        #expect(service.elapsedTime == 0)
    }
}
