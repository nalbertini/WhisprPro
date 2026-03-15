import Testing
import Foundation
@testable import WhisprPro

@Suite("AudioConverter Tests")
struct AudioConverterTests {
    @Test func supportedFormats() {
        let supported = AudioConverter.supportedExtensions
        #expect(supported.contains("mp3"))
        #expect(supported.contains("wav"))
        #expect(supported.contains("m4a"))
        #expect(supported.contains("mp4"))
        #expect(supported.contains("mov"))
        #expect(supported.contains("aac"))
        #expect(supported.contains("flac"))
        #expect(supported.contains("ogg"))
    }

    @Test func isSupportedFile() {
        #expect(AudioConverter.isSupported(URL(filePath: "/test/file.mp3")) == true)
        #expect(AudioConverter.isSupported(URL(filePath: "/test/file.txt")) == false)
    }
}
