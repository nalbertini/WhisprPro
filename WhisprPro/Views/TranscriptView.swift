import SwiftUI
import AppKit
import os

private let logger = Logger(subsystem: "com.whisprpro", category: "Export")

struct TranscriptView: View {
    let transcription: Transcription
    @Bindable var playerViewModel: AudioPlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(transcription.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 12) {
                    Label(formatDuration(transcription.duration), systemImage: "clock")
                    Label(transcription.language, systemImage: "globe")
                    Label(transcription.modelName, systemImage: "cpu")
                    if !transcription.speakers.isEmpty {
                        Label("\(transcription.speakers.count) speakers", systemImage: "person.2")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Menu("Export") {
                        Button("SRT (.srt)") { exportAs(.srt) }
                        Button("VTT (.vtt)") { exportAs(.vtt) }
                        Button("Text (.txt)") { exportAs(.txt) }
                        Button("JSON (.json)") { exportAs(.json) }
                        Button("PDF (.pdf)") { exportAs(.pdf) }
                    }
                    .fixedSize()

                    ShareLink(
                        item: transcription.title,
                        preview: SharePreview(transcription.title)
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .padding()

            Divider()

            // Audio player
            if let sourceURL = transcription.sourceURL {
                AudioPlayerView(viewModel: playerViewModel)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .onAppear {
                        playerViewModel.loadAudio(url: sourceURL)
                    }

                Divider()
            }

            // Segments
            if transcription.status == .completed {
                ScrollViewReader { proxy in
                    List {
                        ForEach(sortedSegments) { segment in
                            EditorView(
                                segment: segment,
                                isActive: isSegmentActive(segment),
                                onSeek: { time in
                                    playerViewModel.seek(to: time)
                                }
                            )
                            .id(segment.id)
                            .contextMenu {
                                segmentContextMenu(for: segment)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            } else if transcription.status == .transcribing || transcription.status == .diarizing {
                VStack(spacing: 12) {
                    ProgressView(value: transcription.progress)
                    Text(transcription.status == .transcribing ? "Transcribing..." : "Identifying speakers...")
                        .foregroundStyle(.secondary)
                    Text("\(Int(transcription.progress * 100))%")
                        .font(.title2)
                        .monospacedDigit()
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if transcription.status == .failed {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(transcription.errorMessage ?? "Transcription failed")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Waiting...")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var sortedSegments: [Segment] {
        transcription.segments.sorted { $0.startTime < $1.startTime }
    }

    private func isSegmentActive(_ segment: Segment) -> Bool {
        playerViewModel.currentTime >= segment.startTime &&
        playerViewModel.currentTime < segment.endTime
    }

    @ViewBuilder
    private func segmentContextMenu(for segment: Segment) -> some View {
        if let index = sortedSegments.firstIndex(where: { $0.id == segment.id }) {
            if index < sortedSegments.count - 1 {
                Button("Merge with Next") {
                    mergeSegments(segment, with: sortedSegments[index + 1])
                }
            }
            Button("Split at Midpoint") {
                splitSegment(segment)
            }
        }
    }

    private func mergeSegments(_ first: Segment, with second: Segment) {
        first.text = first.text + " " + second.text
        first.endTime = second.endTime
        first.isEdited = true
        if let context = second.transcription?.modelContext {
            context.delete(second)
        }
    }

    private func splitSegment(_ segment: Segment) {
        let text = segment.text
        let midIndex = text.index(text.startIndex, offsetBy: text.count / 2)
        // Find nearest space to split cleanly
        let splitIndex = text[..<midIndex].lastIndex(of: " ") ?? midIndex

        let firstText = String(text[..<splitIndex])
        let secondText = String(text[splitIndex...]).trimmingCharacters(in: .whitespaces)

        // Interpolate timestamp linearly
        let ratio = Double(text.distance(from: text.startIndex, to: splitIndex)) / Double(text.count)
        let splitTime = segment.startTime + (segment.endTime - segment.startTime) * ratio

        // Update existing segment
        segment.text = firstText
        segment.endTime = splitTime
        segment.isEdited = true

        // Create new segment
        let newSegment = Segment(startTime: splitTime, endTime: segment.endTime, text: secondText)
        newSegment.speaker = segment.speaker
        newSegment.transcription = segment.transcription
        newSegment.isEdited = true
        if let context = segment.transcription?.modelContext {
            context.insert(newSegment)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    enum ExportFormat { case srt, vtt, txt, json, pdf }

    private func exportAs(_ format: ExportFormat) {
        let segments: [ExportService.ExportSegment] = sortedSegments.map { seg in
            (seg.startTime, seg.endTime, seg.text, seg.speaker?.label)
        }

        let panel = NSSavePanel()
        switch format {
        case .srt: panel.allowedContentTypes = [.init(filenameExtension: "srt")!]
        case .vtt: panel.allowedContentTypes = [.init(filenameExtension: "vtt")!]
        case .txt: panel.allowedContentTypes = [.plainText]
        case .json: panel.allowedContentTypes = [.json]
        case .pdf: panel.allowedContentTypes = [.pdf]
        }
        panel.nameFieldStringValue = transcription.title

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let content: String
        var data: Data?

        switch format {
        case .srt: content = ExportService.toSRT(segments: segments)
        case .vtt: content = ExportService.toVTT(segments: segments)
        case .txt: content = ExportService.toTXT(segments: segments)
        case .json: content = ExportService.toJSON(
            title: transcription.title,
            language: transcription.language,
            segments: segments
        )
        case .pdf:
            data = ExportService.toPDF(
                title: transcription.title,
                language: transcription.language,
                duration: transcription.duration,
                segments: segments
            )
            content = ""
        }

        do {
            if let data {
                try data.write(to: url)
            } else {
                try content.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            logger.error("Export failed: \(error)")
        }
    }
}
