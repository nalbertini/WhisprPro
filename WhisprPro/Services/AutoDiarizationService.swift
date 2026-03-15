import Foundation
import Speech
import os

private let logger = Logger(subsystem: "com.whisprpro", category: "AutoDiarization")

actor AutoDiarizationService {

    /// Analyze audio and assign speakers to existing segments based on voice pitch clustering
    func assignSpeakers(
        audioURL: URL,
        segments: [Segment],
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> Int {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized ||
              SFSpeechRecognizer.authorizationStatus() == .notDetermined else {
            throw AutoDiarizationError.permissionDenied
        }

        // Request authorization if needed
        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard authorized else {
            throw AutoDiarizationError.permissionDenied
        }

        progress("Analyzing voice patterns...")
        logger.info("Starting auto-diarization for \(segments.count) segments")

        // Extract average pitch per segment using SFSpeechRecognizer
        guard let recognizer = SFSpeechRecognizer() else {
            throw AutoDiarizationError.recognizerNotAvailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false

        // Run recognition to get voice analytics
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result, result.isFinal {
                    continuation.resume(returning: result)
                }
            }
        }

        progress("Extracting voice features...")

        // Extract pitch values from voice analytics per transcription segment
        var segmentPitches: [(segmentIndex: Int, avgPitch: Double)] = []

        let appleSegments = result.bestTranscription.segments

        for (i, segment) in segments.enumerated() {
            // Find matching Apple segments by timestamp overlap
            let matchingAppleSegs = appleSegments.filter { appleSeg in
                let appleStart = appleSeg.timestamp
                let appleEnd = appleStart + appleSeg.duration
                let overlapStart = max(segment.startTime, appleStart)
                let overlapEnd = min(segment.endTime, appleEnd)
                return overlapEnd > overlapStart
            }

            // Get average pitch from matching segments
            var pitchSum: Double = 0
            var pitchCount = 0

            for appleSeg in matchingAppleSegs {
                if let voiceAnalytics = appleSeg.voiceAnalytics {
                    let pitchValues = voiceAnalytics.pitch.acousticFeatureValuePerFrame
                    for value in pitchValues {
                        pitchSum += value
                        pitchCount += 1
                    }
                }
            }

            if pitchCount > 0 {
                segmentPitches.append((segmentIndex: i, avgPitch: pitchSum / Double(pitchCount)))
            }
        }

        guard !segmentPitches.isEmpty else {
            logger.warning("No voice analytics data available")
            throw AutoDiarizationError.noVoiceData
        }

        progress("Clustering speakers...")

        // Simple clustering: split by pitch into groups using k-means with k=2 initially
        // Find natural pitch boundary
        let pitches = segmentPitches.map(\.avgPitch).sorted()
        let medianPitch = pitches[pitches.count / 2]

        // Find largest gap in sorted pitches to determine speaker boundary
        var maxGap: Double = 0
        var gapIndex = pitches.count / 2
        for i in 1..<pitches.count {
            let gap = pitches[i] - pitches[i-1]
            if gap > maxGap {
                maxGap = gap
                gapIndex = i
            }
        }

        // If the gap is significant (>15% of range), use it as boundary
        let range = pitches.last! - pitches.first!
        let threshold: Double
        if range > 0 && maxGap > range * 0.15 {
            threshold = (pitches[gapIndex - 1] + pitches[gapIndex]) / 2
        } else {
            threshold = medianPitch
        }

        // Assign speakers based on pitch
        let speakerColors = ["#007AFF", "#FF9500", "#34C759", "#FF3B30"]
        var speakerCount = 0
        var speakerMap: [Int: Speaker] = [:] // 0 or 1 -> Speaker

        for sp in segmentPitches {
            let group = sp.avgPitch < threshold ? 0 : 1
            let segment = segments[sp.segmentIndex]

            if speakerMap[group] == nil {
                speakerCount += 1
                let speaker = Speaker(
                    label: "Speaker \(speakerCount)",
                    color: speakerColors[(speakerCount - 1) % speakerColors.count]
                )
                speaker.transcription = segment.transcription
                if let context = segment.transcription?.modelContext {
                    context.insert(speaker)
                }
                speakerMap[group] = speaker
            }

            segment.speaker = speakerMap[group]
        }

        logger.info("Auto-diarization complete: \(speakerCount) speakers detected")
        progress("Done! \(speakerCount) speakers detected")

        return speakerCount
    }
}

enum AutoDiarizationError: Error, LocalizedError {
    case permissionDenied
    case recognizerNotAvailable
    case noVoiceData

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Speech recognition permission required. Enable it in System Settings > Privacy & Security > Speech Recognition"
        case .recognizerNotAvailable: "Speech recognizer not available"
        case .noVoiceData: "Could not extract voice data for speaker detection"
        }
    }
}
