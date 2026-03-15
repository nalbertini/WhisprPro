import SwiftUI
import AppKit
import os

private let logger = Logger(subsystem: "com.whisprpro", category: "Export")

struct TranscriptContentView: View {
    @Bindable var transcription: Transcription
    @Bindable var playerViewModel: AudioPlayerViewModel
    var fontSize: Double = 15
    var favoritesOnly: Bool = false
    var compactMode: Bool = false
    var groupSegments: Bool = false
    @State private var searchText = ""
    @State private var searchResultCount = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(transcription.title)
                        .font(.headline)
                    HStack(spacing: 8) {
                        Label(formatDuration(transcription.duration), systemImage: "clock")
                        Label(transcription.language, systemImage: "globe")
                        Label(transcription.modelName, systemImage: "cpu")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Menu("Export") {
                    Button("WhisprPro (.whispr)") { exportAsWhispr() }
                    Divider()
                    Button("SRT (.srt)") { exportAs(.srt) }
                    Button("VTT (.vtt)") { exportAs(.vtt) }
                    Button("Text (.txt)") { exportAs(.txt) }
                    Button("JSON (.json)") { exportAs(.json) }
                    Button("PDF (.pdf)") { exportAs(.pdf) }
                    Button("CSV (.csv)") { exportAs(.csv) }
                    Button("Markdown (.md)") { exportAs(.md) }
                    Button("HTML (.html)") { exportAs(.html) }
                    Button("Word (.docx)") { exportAs(.docx) }
                }
                .fixedSize()

                ShareLink(
                    item: transcription.title,
                    preview: SharePreview(transcription.title)
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            // Search bar
            if transcription.status == .completed {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search transcript...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Text("\(searchResultCount) found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(.bar)

                Divider()
            }

            // Transcript content
            if transcription.status == .completed {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredSegments) { segment in
                                EditorView(
                                    segment: segment,
                                    isActive: isSegmentActive(segment),
                                    searchText: searchText,
                                    timestampOffset: transcription.timestampOffset,
                                    compactMode: compactMode,
                                    fontSize: fontSize,
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
                        .padding(.horizontal)
                    }
                    .onChange(of: searchText) {
                        searchResultCount = filteredSegments.count
                    }
                }
            } else if transcription.status == .transcribing || transcription.status == .diarizing {
                VStack(spacing: 12) {
                    ProgressView(value: transcription.progress)
                        .frame(width: 200)
                    Text(transcription.status == .transcribing ? "Transcribing..." : "Identifying speakers...")
                        .foregroundStyle(.secondary)
                    Text("\(Int(transcription.progress * 100))%")
                        .font(.title2)
                        .monospacedDigit()
                }
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

            // Player fixed at bottom
            if let sourceURL = transcription.sourceURL {
                Divider()
                let ext = sourceURL.pathExtension.lowercased()
                if ext == "mp4" || ext == "mov" || ext == "m4v" {
                    VideoPlayerView(
                        url: sourceURL,
                        playerViewModel: playerViewModel,
                        subtitles: sortedSegments.map { ($0.startTime, $0.endTime, $0.text) }
                    )
                } else {
                    AudioPlayerView(viewModel: playerViewModel)
                        .onAppear {
                            playerViewModel.loadAudio(url: sourceURL)
                        }
                }
            }
        }
    }

    private var sortedSegments: [Segment] {
        transcription.segments.sorted { $0.startTime < $1.startTime }
    }

    private var filteredSegments: [Segment] {
        var result = sortedSegments

        // Group short consecutive segments into paragraphs
        if groupSegments && !result.isEmpty {
            var grouped: [Segment] = []
            var current = result[0]

            for i in 1..<result.count {
                let next = result[i]
                let gap = next.startTime - current.endTime
                let sameSpeaker = current.speaker?.id == next.speaker?.id
                let currentShort = current.text.count < 80

                // Merge if: same speaker (or no speakers), gap < 2s, current text is short
                if sameSpeaker && gap < 2.0 && currentShort {
                    current.text = current.text + " " + next.text
                    current.endTime = next.endTime
                    if next.isStarred { current.isStarred = true }
                } else {
                    grouped.append(current)
                    current = next
                }
            }
            grouped.append(current)
            result = grouped
        }

        if favoritesOnly {
            result = result.filter { $0.isStarred }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.text.localizedCaseInsensitiveContains(searchText) ||
                ($0.speaker?.label.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        return result
    }

    private func isSegmentActive(_ segment: Segment) -> Bool {
        playerViewModel.currentTime >= segment.startTime &&
        playerViewModel.currentTime < segment.endTime
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
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

        // After existing merge/split buttons, add:
        if !transcription.speakers.isEmpty {
            Divider()
            Menu("Assign Speaker") {
                Button("None") {
                    segment.speaker = nil
                }
                Divider()
                ForEach(transcription.speakers) { speaker in
                    Button {
                        segment.speaker = speaker
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(hex: speaker.color) ?? .blue)
                                .frame(width: 8, height: 8)
                            Text(speaker.label)
                        }
                    }
                }
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
        let splitIndex = text[..<midIndex].lastIndex(of: " ") ?? midIndex

        let firstText = String(text[..<splitIndex])
        let secondText = String(text[splitIndex...]).trimmingCharacters(in: .whitespaces)

        let ratio = Double(text.distance(from: text.startIndex, to: splitIndex)) / Double(text.count)
        let splitTime = segment.startTime + (segment.endTime - segment.startTime) * ratio

        segment.text = firstText
        segment.endTime = splitTime
        segment.isEdited = true

        let newSegment = Segment(startTime: splitTime, endTime: segment.endTime, text: secondText)
        newSegment.speaker = segment.speaker
        newSegment.transcription = segment.transcription
        newSegment.isEdited = true
        if let context = segment.transcription?.modelContext {
            context.insert(newSegment)
        }
    }

    // MARK: - Export

    private func exportAsWhispr() {
        do {
            let whisprURL = try WhisprFileService.exportWhispr(transcription: transcription)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.init(filenameExtension: "whispr")!]
            panel.nameFieldStringValue = transcription.title
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.copyItem(at: whisprURL, to: url)
        } catch {
            logger.error("Export .whispr failed: \(error)")
        }
    }

    enum ExportFormat { case srt, vtt, txt, json, pdf, csv, md, html, docx }

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
        case .csv: panel.allowedContentTypes = [.commaSeparatedText]
        case .md: panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        case .html: panel.allowedContentTypes = [.html]
        case .docx: panel.allowedContentTypes = [.init(filenameExtension: "docx")!]
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
        case .csv: content = ExportService.toCSV(segments: segments)
        case .md: content = ExportService.toMarkdown(
            title: transcription.title,
            language: transcription.language,
            duration: transcription.duration,
            segments: segments
        )
        case .html: content = ExportService.toHTML(
            title: transcription.title,
            language: transcription.language,
            duration: transcription.duration,
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
        case .docx:
            data = ExportService.toDOCX(
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
