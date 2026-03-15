import Foundation
import AVFoundation
import Accelerate
import os

private let logger = Logger(subsystem: "com.whisprpro", category: "AutoDiarization")

actor AutoDiarizationService {

    /// Analyze audio and assign speakers to existing segments based on voice characteristics
    func assignSpeakers(
        audioURL: URL,
        segments: [Segment],
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> Int {
        guard !segments.isEmpty else { return 0 }

        progress("Loading audio...")
        logger.info("Starting auto-diarization for \(segments.count) segments")

        // Load audio as float samples
        let audioFile = try AVAudioFile(forReading: audioURL)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: audioFile.fileFormat.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AutoDiarizationError.audioLoadFailed
        }

        let frameCount = AVAudioFrameCount(audioFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AutoDiarizationError.audioLoadFailed
        }
        try audioFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData?[0] else {
            throw AutoDiarizationError.audioLoadFailed
        }

        let sampleRate = Float(audioFile.fileFormat.sampleRate)
        let totalSamples = Int(buffer.frameLength)

        progress("Analyzing voice patterns...")

        // Extract features per segment: average energy + zero-crossing rate + spectral centroid
        var segmentFeatures: [(index: Int, energy: Float, zcr: Float, spectralCentroid: Float)] = []

        for (i, segment) in segments.enumerated() {
            let startSample = min(Int(Float(segment.startTime) * sampleRate), totalSamples - 1)
            let endSample = min(Int(Float(segment.endTime) * sampleRate), totalSamples)
            let count = max(endSample - startSample, 1)

            // RMS energy
            var rms: Float = 0
            vDSP_rmsqv(channelData.advanced(by: startSample), 1, &rms, vDSP_Length(count))

            // Zero-crossing rate (correlates with pitch)
            var zcr: Float = 0
            for j in (startSample + 1)..<endSample {
                if (channelData[j] >= 0) != (channelData[j - 1] >= 0) {
                    zcr += 1
                }
            }
            zcr /= Float(count)

            // Spectral centroid estimate via autocorrelation-based pitch
            let frameSize = min(2048, count)
            var autocorr = [Float](repeating: 0, count: frameSize)
            let segPtr = channelData.advanced(by: startSample)
            vDSP_conv(segPtr, 1, segPtr, 1, &autocorr, 1, vDSP_Length(frameSize), vDSP_Length(frameSize))

            // Find first peak after zero-crossing in autocorrelation (fundamental period)
            var pitchEstimate: Float = 0
            let minLag = Int(sampleRate / 500)  // Max 500 Hz
            let maxLag = min(Int(sampleRate / 80), frameSize - 1)  // Min 80 Hz
            if maxLag > minLag {
                var maxVal: Float = 0
                var maxIdx: vDSP_Length = 0
                vDSP_maxvi(autocorr, 1, &maxVal, &maxIdx, vDSP_Length(maxLag - minLag))
                let lag = Int(maxIdx) + minLag
                if lag > 0 {
                    pitchEstimate = sampleRate / Float(lag)
                }
            }

            segmentFeatures.append((index: i, energy: rms, zcr: zcr, spectralCentroid: pitchEstimate))
        }

        progress("Clustering speakers...")

        // Normalize features
        let energies = segmentFeatures.map(\.energy)
        let zcrs = segmentFeatures.map(\.zcr)
        let pitches = segmentFeatures.map(\.spectralCentroid)

        let eMin = energies.min() ?? 0, eMax = max(energies.max() ?? 1, eMin + 0.001)
        let zMin = zcrs.min() ?? 0, zMax = max(zcrs.max() ?? 1, zMin + 0.001)
        let pMin = pitches.min() ?? 0, pMax = max(pitches.max() ?? 1, pMin + 0.001)

        // Create normalized feature vectors [energy, zcr, pitch]
        var featureVectors: [[Float]] = []
        for f in segmentFeatures {
            featureVectors.append([
                (f.energy - eMin) / (eMax - eMin),
                (f.zcr - zMin) / (zMax - zMin),
                (f.spectralCentroid - pMin) / (pMax - pMin) * 2.0  // Weight pitch higher
            ])
        }

        // K-means clustering with k=2
        let assignments = kMeansClustering(vectors: featureVectors, k: 2)

        // Create speakers and assign
        let speakerColors = ["#007AFF", "#FF9500", "#34C759", "#FF3B30"]
        var speakerMap: [Int: Speaker] = [:]
        var speakerCount = 0

        for (i, cluster) in assignments.enumerated() {
            let segment = segments[segmentFeatures[i].index]

            if speakerMap[cluster] == nil {
                speakerCount += 1
                let speaker = Speaker(
                    label: "Speaker \(speakerCount)",
                    color: speakerColors[(speakerCount - 1) % speakerColors.count]
                )
                speaker.transcription = segment.transcription
                if let context = segment.transcription?.modelContext {
                    context.insert(speaker)
                }
                speakerMap[cluster] = speaker
            }

            segment.speaker = speakerMap[cluster]
        }

        logger.info("Auto-diarization complete: \(speakerCount) speakers detected")
        progress("Done! \(speakerCount) speakers detected")

        return speakerCount
    }

    /// Simple k-means clustering
    private func kMeansClustering(vectors: [[Float]], k: Int, maxIterations: Int = 20) -> [Int] {
        let n = vectors.count
        guard n > 1, let dim = vectors.first?.count else { return Array(repeating: 0, count: n) }

        // Initialize centroids with first and last (sorted by first feature)
        let sorted = vectors.enumerated().sorted { $0.element[0] < $1.element[0] }
        var centroids: [[Float]] = [
            sorted.first!.element,
            sorted.last!.element
        ]

        var assignments = [Int](repeating: 0, count: n)

        for _ in 0..<maxIterations {
            // Assign each point to nearest centroid
            var changed = false
            for i in 0..<n {
                var bestCluster = 0
                var bestDist: Float = .infinity
                for c in 0..<k {
                    var dist: Float = 0
                    for d in 0..<dim {
                        let diff = vectors[i][d] - centroids[c][d]
                        dist += diff * diff
                    }
                    if dist < bestDist {
                        bestDist = dist
                        bestCluster = c
                    }
                }
                if assignments[i] != bestCluster {
                    assignments[i] = bestCluster
                    changed = true
                }
            }

            if !changed { break }

            // Update centroids
            for c in 0..<k {
                var sum = [Float](repeating: 0, count: dim)
                var count: Float = 0
                for i in 0..<n {
                    if assignments[i] == c {
                        for d in 0..<dim {
                            sum[d] += vectors[i][d]
                        }
                        count += 1
                    }
                }
                if count > 0 {
                    centroids[c] = sum.map { $0 / count }
                }
            }
        }

        return assignments
    }
}

enum AutoDiarizationError: Error, LocalizedError {
    case audioLoadFailed
    case noVoiceData

    var errorDescription: String? {
        switch self {
        case .audioLoadFailed: "Failed to load audio file for analysis"
        case .noVoiceData: "Could not extract voice data for speaker detection"
        }
    }
}
