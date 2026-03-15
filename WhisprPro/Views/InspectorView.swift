import SwiftUI
import AppKit

struct InspectorView: View {
    @Bindable var transcription: Transcription
    @Binding var fontSize: Double
    @Binding var favoritesOnly: Bool
    @Binding var compactMode: Bool
    @Binding var groupSegments: Bool

    @State private var isDetectingSpeakers = false
    @State private var diarizationStatus = ""
    @State private var expectedSpeakers = 2

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Copy buttons
                Button {
                    copyTranscript()
                } label: {
                    Label("Copy Transcript", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    copyForAI()
                } label: {
                    Label("Copy for AI", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Divider()

                // Model & Language
                VStack(alignment: .leading, spacing: 10) {
                    Text("Model & Language")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    InfoRow(icon: "cpu", label: "Model", value: transcription.modelName)
                    InfoRow(icon: "globe", label: "Language", value: languageDisplayName(transcription.language))
                }

                Divider()

                // Properties
                VStack(alignment: .leading, spacing: 10) {
                    Text("Properties")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    InfoRow(icon: "waveform", label: "Audio Duration", value: formatDuration(transcription.duration))
                    InfoRow(icon: "calendar", label: "Created", value: formatDate(transcription.createdAt))
                    if transcription.updatedAt != transcription.createdAt {
                        InfoRow(icon: "calendar.badge.clock", label: "Updated", value: formatDate(transcription.updatedAt))
                    }
                }

                // Transcription Details (only when completed)
                if transcription.status == .completed {
                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Transcription Details")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        if transcription.transcribeTime > 0 {
                            InfoRow(icon: "stopwatch", label: "Transcribe Time", value: formatTranscribeTime(transcription.transcribeTime))

                            let speed = transcription.duration / max(transcription.transcribeTime, 0.01)
                            InfoRow(icon: "gauge.with.needle", label: "Speed", value: String(format: "%.1fx realtime", speed))
                        }

                        if !transcription.detectedLanguage.isEmpty {
                            InfoRow(icon: "globe.americas", label: "Detected Language", value: languageDisplayName(transcription.detectedLanguage))
                        }

                        InfoRow(icon: "textformat.abc", label: "Characters", value: "\(totalCharacters)")
                        InfoRow(icon: "text.alignleft", label: "Words", value: "\(totalWords)")
                        InfoRow(icon: "list.bullet", label: "Segments", value: "\(transcription.segments.count)")
                    }

                    Divider()

                    // Display options
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Display")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Font Size")
                                .font(.body)
                            Spacer()
                            Picker("", selection: $fontSize) {
                                Text("13").tag(13.0)
                                Text("15").tag(15.0)
                                Text("18").tag(18.0)
                                Text("22").tag(22.0)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 70)
                        }

                        Toggle("Favorites Only", isOn: $favoritesOnly)
                        Toggle("Compact Mode", isOn: $compactMode)
                        Toggle("Group Segments", isOn: $groupSegments)
                    }

                    Divider()

                    // People
                    VStack(alignment: .leading, spacing: 8) {
                        Text("People")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        if transcription.speakers.isEmpty {
                            Text("No speakers detected")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(transcription.speakers) { speaker in
                                HStack(spacing: 10) {
                                    ColorPicker("", selection: Binding(
                                        get: { Color(hex: speaker.color) ?? .blue },
                                        set: { speaker.color = $0.hexString }
                                    ))
                                    .labelsHidden()
                                    .frame(width: 20, height: 20)

                                    TextField("Speaker", text: Binding(
                                        get: { speaker.label },
                                        set: { speaker.label = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body)

                                    Spacer()

                                    Text("\(speaker.segments.count)")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 20, alignment: .trailing)
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        // Auto-detect speakers
                        HStack {
                            Stepper("Speakers: \(expectedSpeakers)", value: $expectedSpeakers, in: 2...8)
                                .font(.caption)
                        }

                        Button {
                            autoDetectSpeakers()
                        } label: {
                            Label("Auto Detect Speakers", systemImage: "person.2.wave.2")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isDetectingSpeakers)

                        if isDetectingSpeakers {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text(diarizationStatus)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Add speaker button
                        Button {
                            addSpeaker()
                        } label: {
                            Label("Add Speaker", systemImage: "person.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Divider()

                    // Actions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Actions")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        Button("Remove Fillers") {
                            removeFillerWords()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        HStack {
                            Text("Time Offset")
                                .font(.body)
                            Spacer()
                            TextField("0", value: $transcription.timestampOffset, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                .font(.caption)
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .background(.bar)
    }

    // MARK: - Computed

    private var totalCharacters: Int {
        transcription.segments.reduce(0) { $0 + $1.text.count }
    }

    private var totalWords: Int {
        transcription.segments.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }

    // MARK: - Formatting

    private func formatDuration(_ d: TimeInterval) -> String {
        let m = Int(d) / 60
        let s = Int(d) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func formatTranscribeTime(_ t: TimeInterval) -> String {
        if t < 1 { return "< 1s" }
        let m = Int(t) / 60
        let s = Int(t) % 60
        if m > 0 { return String(format: "%d:%02d", m, s) }
        return String(format: "00:%02d", s)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func languageDisplayName(_ code: String) -> String {
        if code == "auto" { return "Auto Detect" }
        return Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code
    }

    // MARK: - Actions

    private func copyTranscript() {
        let segments = transcription.segments.sorted { $0.startTime < $1.startTime }
        let text = segments.map { seg in
            var line = ""
            if let speaker = seg.speaker {
                line += "\(speaker.label): "
            }
            line += seg.text
            return line
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyForAI() {
        let segments = transcription.segments.sorted { $0.startTime < $1.startTime }

        var text = "# Transcript: \(transcription.title)\n"
        text += "- Duration: \(formatDuration(transcription.duration))\n"
        text += "- Language: \(languageDisplayName(transcription.language))\n"
        text += "- Model: \(transcription.modelName)\n"
        if !transcription.speakers.isEmpty {
            text += "- Speakers: \(transcription.speakers.map(\.label).joined(separator: ", "))\n"
        }
        text += "\n---\n\n"

        for seg in segments {
            let timestamp = formatTranscribeTime(seg.startTime)
            if let speaker = seg.speaker {
                text += "[\(timestamp)] **\(speaker.label):** \(seg.text)\n\n"
            } else {
                text += "[\(timestamp)] \(seg.text)\n\n"
            }
        }

        text += "---\n"
        text += "Words: \(totalWords) | Characters: \(totalCharacters) | Segments: \(segments.count)\n"

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func addSpeaker() {
        let count = transcription.speakers.count + 1
        let colors = ["#007AFF", "#FF9500", "#34C759", "#FF3B30", "#AF52DE", "#FF2D55", "#5AC8FA", "#FFCC00"]
        let speaker = Speaker(
            label: "Speaker \(count)",
            color: colors[(count - 1) % colors.count]
        )
        speaker.transcription = transcription
        // We need modelContext to insert - get it from the transcription
        if let context = transcription.modelContext {
            context.insert(speaker)
        }
    }

    private func autoDetectSpeakers() {
        guard let sourceURL = transcription.sourceURL else { return }
        isDetectingSpeakers = true
        diarizationStatus = "Starting..."

        Task {
            let service = AutoDiarizationService()
            do {
                let count = try await service.assignSpeakers(
                    audioURL: sourceURL,
                    segments: transcription.segments.sorted { $0.startTime < $1.startTime },
                    numSpeakers: expectedSpeakers,
                    progress: { status in
                        Task { @MainActor in
                            diarizationStatus = status
                        }
                    }
                )
                await MainActor.run {
                    isDetectingSpeakers = false
                    diarizationStatus = ""
                }
            } catch {
                await MainActor.run {
                    isDetectingSpeakers = false
                    diarizationStatus = error.localizedDescription
                }
            }
        }
    }

    private func removeFillerWords() {
        for segment in transcription.segments {
            let cleaned = FillerWordService.removeFillersFrom(segment.text)
            if cleaned != segment.text {
                segment.text = cleaned
                segment.isEdited = true
            }
        }
    }
}

// MARK: - InfoRow

private struct InfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
