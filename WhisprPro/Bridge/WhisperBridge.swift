import Foundation
import WhisperCpp

struct WhisperSegment {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

enum WhisperBridgeError: Error, LocalizedError {
    case modelLoadFailed
    case transcriptionFailed
    case noModelLoaded
    case cancelled

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed: "Failed to load Whisper model"
        case .transcriptionFailed: "Transcription failed"
        case .noModelLoaded: "No model loaded"
        case .cancelled: "Transcription cancelled"
        }
    }
}

actor WhisperBridge {
    private var context: OpaquePointer?
    private var isCancelled = false

    func loadModel(path: URL) throws {
        if let ctx = context {
            wrapper_free(ctx)
        }
        guard let ctx = wrapper_init(path.path()) else {
            throw WhisperBridgeError.modelLoadFailed
        }
        self.context = ctx
    }

    func transcribe(
        audioPath: URL,
        language: String = "auto",
        translate: Bool = false,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [WhisperSegment] {
        guard let ctx = context else {
            throw WhisperBridgeError.noModelLoaded
        }

        isCancelled = false
        let audioPathStr = audioPath.path()
        let languageStr = language

        let result = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let progressCallback: wrapper_progress_callback = { progressValue, userData in
                    guard let ptr = userData else { return }
                    let callback = Unmanaged<ProgressCallbackBox>.fromOpaque(ptr).takeUnretainedValue()
                    callback.callback(Double(progressValue))
                }

                let box = ProgressCallbackBox(callback: progress)
                let boxPtr = Unmanaged.passRetained(box).toOpaque()

                let res = wrapper_transcribe(ctx, audioPathStr, languageStr, translate, progressCallback, boxPtr)

                Unmanaged<ProgressCallbackBox>.fromOpaque(boxPtr).release()
                continuation.resume(returning: res)
            }
        }

        if isCancelled { throw WhisperBridgeError.cancelled }
        guard result == 0 else { throw WhisperBridgeError.transcriptionFailed }

        let segmentCount = wrapper_get_segment_count(ctx)
        var segments: [WhisperSegment] = []
        for i in 0..<segmentCount {
            let seg = wrapper_get_segment(ctx, Int32(i))
            let text = String(cString: seg.text)
            segments.append(WhisperSegment(
                startTime: Double(seg.start_ms) / 1000.0,
                endTime: Double(seg.end_ms) / 1000.0,
                text: text.trimmingCharacters(in: .whitespaces)
            ))
        }
        return segments
    }

    func cancel() { isCancelled = true }

    deinit {
        if let ctx = context { wrapper_free(ctx) }
    }
}

private final class ProgressCallbackBox: @unchecked Sendable {
    let callback: (Double) -> Void
    init(callback: @escaping (Double) -> Void) { self.callback = callback }
}
