import Foundation
import CoreML
import Accelerate

actor DiarizationService {
    static let speakerColors = [
        "#007AFF", "#FF9500", "#34C759", "#FF3B30",
        "#AF52DE", "#FF2D55", "#5AC8FA", "#FFCC00",
    ]

    /// Assign speaker indices to transcript segments based on a speaker timeline
    static func assignSpeakers(
        speakerTimeline: [(start: TimeInterval, end: TimeInterval, speakerIndex: Int)],
        segments: [(start: TimeInterval, end: TimeInterval)]
    ) -> [Int] {
        segments.map { seg in
            // Find the speaker timeline entry with maximum overlap
            var bestSpeaker = 0
            var bestOverlap: TimeInterval = 0

            for entry in speakerTimeline {
                let overlapStart = max(seg.start, entry.start)
                let overlapEnd = min(seg.end, entry.end)
                let overlap = max(0, overlapEnd - overlapStart)

                if overlap > bestOverlap {
                    bestOverlap = overlap
                    bestSpeaker = entry.speakerIndex
                }
            }

            return bestSpeaker
        }
    }

    /// Perform agglomerative clustering on embedding vectors
    static func agglomerativeClustering(
        embeddings: [[Float]],
        threshold: Float = 0.5
    ) -> [Int] {
        let n = embeddings.count
        guard n > 0 else { return [] }
        if n == 1 { return [0] }

        // Compute cosine distance matrix
        var distances = [[Float]](repeating: [Float](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in (i+1)..<n {
                let dist = cosineDistance(embeddings[i], embeddings[j])
                distances[i][j] = dist
                distances[j][i] = dist
            }
        }

        // Each point starts as its own cluster
        var clusterAssignment = Array(0..<n)
        var nextClusterID = n

        // Merge until no pair is below threshold
        while true {
            var minDist: Float = Float.infinity
            var mergeA = -1
            var mergeB = -1

            let activeClusters = Set(clusterAssignment)
            let clusterList = Array(activeClusters).sorted()

            for i in 0..<clusterList.count {
                for j in (i+1)..<clusterList.count {
                    let cA = clusterList[i]
                    let cB = clusterList[j]
                    let dist = averageLinkageDistance(
                        clusterA: cA, clusterB: cB,
                        assignments: clusterAssignment,
                        distances: distances
                    )
                    if dist < minDist {
                        minDist = dist
                        mergeA = cA
                        mergeB = cB
                    }
                }
            }

            if minDist > threshold || mergeA == -1 { break }

            // Merge clusterB into clusterA
            for i in 0..<n {
                if clusterAssignment[i] == mergeB {
                    clusterAssignment[i] = mergeA
                }
            }
        }

        // Renumber clusters to 0, 1, 2, ...
        let unique = Array(Set(clusterAssignment)).sorted()
        let mapping = Dictionary(uniqueKeysWithValues: unique.enumerated().map { ($1, $0) })
        return clusterAssignment.map { mapping[$0]! }
    }

    private static func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))

        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 1.0 }
        return 1.0 - (dotProduct / denom)
    }

    private static func averageLinkageDistance(
        clusterA: Int, clusterB: Int,
        assignments: [Int], distances: [[Float]]
    ) -> Float {
        var sum: Float = 0
        var count: Float = 0

        for i in 0..<assignments.count {
            guard assignments[i] == clusterA else { continue }
            for j in 0..<assignments.count {
                guard assignments[j] == clusterB else { continue }
                sum += distances[i][j]
                count += 1
            }
        }

        return count > 0 ? sum / count : Float.infinity
    }

    /// Run diarization on a transcription.
    /// Pipeline: load audio → split into windows → extract embeddings via Core ML → cluster → assign speakers.
    func diarize(
        audioURL: URL,
        segments: [Segment],
        modelURL: URL
    ) async throws -> [(speakerIndex: Int, segmentID: UUID)] {
        // Step 1: Load Core ML model
        let config = MLModelConfiguration()
        config.computeUnits = .all

        guard let model = try? MLModel(contentsOf: modelURL, configuration: config) else {
            throw DiarizationError.modelLoadFailed
        }

        // Step 2: Load audio as float array
        let audioData = try loadAudioAsFloats(url: audioURL)

        // Step 3: Split into overlapping windows and extract embeddings
        let windowSize = 16000 * 3  // 3-second windows at 16kHz
        let hopSize = 16000 * 1     // 1-second hop
        var windowEmbeddings: [(midTime: TimeInterval, embedding: [Float])] = []

        var offset = 0
        while offset + windowSize <= audioData.count {
            let window = Array(audioData[offset..<(offset + windowSize)])
            let midTime = Double(offset + windowSize / 2) / 16000.0

            // Create MLMultiArray input for Core ML model
            let inputArray = try MLMultiArray(shape: [1, NSNumber(value: windowSize)], dataType: .float32)
            for i in 0..<windowSize {
                inputArray[i] = NSNumber(value: window[i])
            }

            let inputFeatures = try MLDictionaryFeatureProvider(
                dictionary: ["audio": MLFeatureValue(multiArray: inputArray)]
            )
            let prediction = try model.prediction(from: inputFeatures)

            // Extract embedding vector from model output
            guard let embeddingValue = prediction.featureValue(for: "embedding"),
                  let embeddingArray = embeddingValue.multiArrayValue else {
                throw DiarizationError.processingFailed("Model output missing embedding")
            }

            var embedding = [Float](repeating: 0, count: embeddingArray.count)
            for i in 0..<embeddingArray.count {
                embedding[i] = embeddingArray[i].floatValue
            }

            windowEmbeddings.append((midTime: midTime, embedding: embedding))
            offset += hopSize
        }

        guard !windowEmbeddings.isEmpty else {
            throw DiarizationError.processingFailed("No audio windows to process")
        }

        // Step 4: Cluster embeddings
        let embeddings = windowEmbeddings.map(\.embedding)
        let clusterLabels = Self.agglomerativeClustering(embeddings: embeddings, threshold: 0.5)

        // Step 5: Build speaker timeline from clustered windows
        var speakerTimeline: [(start: TimeInterval, end: TimeInterval, speakerIndex: Int)] = []
        for (i, windowEmb) in windowEmbeddings.enumerated() {
            let start = max(0, windowEmb.midTime - 1.5)  // half window before midpoint
            let end = windowEmb.midTime + 1.5              // half window after midpoint
            speakerTimeline.append((start: start, end: end, speakerIndex: clusterLabels[i]))
        }

        // Step 6: Assign speakers to transcript segments
        let segmentRanges = segments.map { (start: $0.startTime, end: $0.endTime) }
        let assignments = Self.assignSpeakers(
            speakerTimeline: speakerTimeline,
            segments: segmentRanges
        )

        return zip(assignments, segments).map { (speakerIndex, segment) in
            (speakerIndex: speakerIndex, segmentID: segment.id)
        }
    }

    /// Load a WAV file as an array of Float samples
    private func loadAudioAsFloats(url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count > 44 else {
            throw DiarizationError.processingFailed("Audio file too small")
        }
        // Skip 44-byte WAV header (standard PCM format from AudioConverter)
        let pcmData = data.dropFirst(44)
        let sampleCount = pcmData.count / 2  // 16-bit samples
        var floats = [Float](repeating: 0, count: sampleCount)

        pcmData.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                floats[i] = Float(int16Buffer[i]) / 32768.0
            }
        }

        return floats
    }
}

enum DiarizationError: Error, LocalizedError {
    case modelLoadFailed
    case modelNotAvailable
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed: "Failed to load diarization model"
        case .modelNotAvailable: "Diarization model not available"
        case .processingFailed(let msg): "Diarization failed: \(msg)"
        }
    }
}
