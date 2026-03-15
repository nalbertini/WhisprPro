import Testing
@testable import WhisprPro

@Suite("WhisperBridge Tests")
struct WhisperBridgeTests {
    @Test func segmentResultConversion() {
        let segment = WhisperSegment(startTime: 1.5, endTime: 3.2, text: "Hello world")
        #expect(segment.startTime == 1.5)
        #expect(segment.endTime == 3.2)
        #expect(segment.text == "Hello world")
    }

    @Test func bridgeInitWithInvalidPath() async {
        let bridge = WhisperBridge()
        do {
            try await bridge.loadModel(path: URL(filePath: "/nonexistent/model.bin"))
            Issue.record("Should have thrown")
        } catch {
            #expect(error is WhisperBridgeError)
        }
    }
}
