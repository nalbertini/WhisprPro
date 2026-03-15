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
    @State private var showAIActions = false

    // Design tokens
    private let textPrimary = Color(red: 0.961, green: 0.961, blue: 0.969)     // #F5F5F7
    private let textSecondary = Color(red: 0.898, green: 0.898, blue: 0.918)   // #E5E5EA
    private let textTertiary = Color(red: 0.557, green: 0.557, blue: 0.576)    // #8E8E93
    private let textQuaternary = Color(red: 0.388, green: 0.388, blue: 0.400)  // #636366
    private let accentBlue = Color(red: 0.039, green: 0.518, blue: 1.0)        // #0A84FF
    private let accentRed = Color(red: 1.0, green: 0.271, blue: 0.227)         // #FF453A
    private let accentGreen = Color(red: 0.188, green: 0.820, blue: 0.345)     // #30D158
    private let accentPurple = Color(red: 0.749, green: 0.353, blue: 0.949)    // #BF5AF2
    private let cardBackground = Color(red: 0.220, green: 0.220, blue: 0.228)  // #38383A
    private let borderColor = Color(red: 0.227, green: 0.227, blue: 0.235)     // #3A3A3C

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Copy buttons
                Button {
                    copyTranscript()
                } label: {
                    Label("Copy Transcript", systemImage: "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(cardBackground)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button {
                    copyForAI()
                } label: {
                    Label("Copy for AI", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accentPurple)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(cardBackground)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(accentPurple.opacity(0.133), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Divider()
                    .background(borderColor)

                // Model & Language
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Model & Language")

                    DesignInfoRow(label: "Model", value: transcription.modelName)
                    DesignInfoRow(label: "Language", value: languageDisplayName(transcription.language))
                }

                Divider()
                    .background(borderColor)

                // Properties
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Properties")

                    DesignInfoRow(label: "Duration", value: formatDuration(transcription.duration), monoValue: true)
                    DesignInfoRow(label: "Created", value: formatDate(transcription.createdAt))
                    if transcription.updatedAt != transcription.createdAt {
                        DesignInfoRow(label: "Updated", value: formatDate(transcription.updatedAt))
                    }
                }

                // Transcription Details (only when completed)
                if transcription.status == .completed {
                    Divider()
                        .background(borderColor)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Transcription Details")

                        if transcription.transcribeTime > 0 {
                            DesignInfoRow(label: "Transcribe Time", value: formatTranscribeTime(transcription.transcribeTime), monoValue: true)

                            let speed = transcription.duration / max(transcription.transcribeTime, 0.01)
                            HStack {
                                Text("Speed")
                                    .font(.system(size: 13))
                                    .foregroundStyle(textTertiary)
                                Spacer()
                                Text(String(format: "%.1fx", speed))
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(accentGreen)
                            }
                        }

                        if !transcription.detectedLanguage.isEmpty {
                            DesignInfoRow(label: "Detected Language", value: languageDisplayName(transcription.detectedLanguage))
                        }

                        DesignInfoRow(label: "Characters", value: "\(totalCharacters)", monoValue: true)
                        DesignInfoRow(label: "Words", value: "\(totalWords)", monoValue: true)
                        DesignInfoRow(label: "Segments", value: "\(transcription.segments.count)", monoValue: true)
                    }

                    Divider()
                        .background(borderColor)

                    // Display options
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Display")

                        HStack {
                            Text("Font Size")
                                .font(.system(size: 13))
                                .foregroundStyle(textTertiary)
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

                        DesignToggle("Favorites Only", isOn: $favoritesOnly)
                        DesignToggle("Compact Mode", isOn: $compactMode)
                        DesignToggle("Group Segments", isOn: $groupSegments)
                    }

                    Divider()
                        .background(borderColor)

                    // People
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "People")

                        if transcription.speakers.isEmpty {
                            Text("No speakers detected")
                                .font(.system(size: 12))
                                .foregroundStyle(textQuaternary)
                        } else {
                            ForEach(transcription.speakers) { speaker in
                                HStack(spacing: 8) {
                                    // Speaker dot
                                    Circle()
                                        .fill(Color(hex: speaker.color) ?? .blue)
                                        .frame(width: 10, height: 10)

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
                                    .font(.system(size: 13))

                                    Spacer()

                                    Text("\(speaker.segments.count)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(textQuaternary)
                                        .frame(width: 20, alignment: .trailing)
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        // Auto-detect speakers
                        HStack {
                            Stepper("Speakers: \(expectedSpeakers)", value: $expectedSpeakers, in: 2...8)
                                .font(.system(size: 12))
                                .foregroundStyle(textSecondary)
                        }

                        Button {
                            autoDetectSpeakers()
                        } label: {
                            Label("Auto Detect Speakers", systemImage: "person.2.wave.2")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(accentBlue)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDetectingSpeakers)

                        if isDetectingSpeakers {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text(diarizationStatus)
                                    .font(.system(size: 11))
                                    .foregroundStyle(textTertiary)
                            }
                        }

                        // Add speaker button
                        Button {
                            addSpeaker()
                        } label: {
                            Label("Add Speaker", systemImage: "person.badge.plus")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(cardBackground)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()
                        .background(borderColor)

                    // Actions
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Actions")

                        Button {
                            showAIActions = true
                        } label: {
                            Label("AI Assistant", systemImage: "sparkles")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(accentPurple)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(accentPurple.opacity(0.133))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(accentPurple.opacity(0.133), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)

                        Button("Remove Fillers") {
                            removeFillerWords()
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(cardBackground)
                        .cornerRadius(6)
                        .buttonStyle(.plain)

                        HStack {
                            Text("Time Offset")
                                .font(.system(size: 13))
                                .foregroundStyle(textTertiary)
                            Spacer()
                            TextField("0", value: $transcription.timestampOffset, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }
                }

                Spacer()
            }
            .padding(16)
        }
        .background(Color(red: 0.173, green: 0.173, blue: 0.180)) // #2C2C2E
        .sheet(isPresented: $showAIActions) {
            AIActionView(transcription: transcription)
        }
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
                let _ = try await service.assignSpeakers(
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

// MARK: - Design Sub-components

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(red: 0.388, green: 0.388, blue: 0.400))
            .kerning(0.55) // ~0.05em at 11px
    }
}

private struct DesignInfoRow: View {
    let label: String
    let value: String
    var monoValue: Bool = false

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.557, green: 0.557, blue: 0.576))
            Spacer()
            Text(value)
                .font(monoValue ? .system(size: 13, design: .monospaced) : .system(size: 13))
                .foregroundStyle(Color(red: 0.898, green: 0.898, blue: 0.918))
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct DesignToggle: View {
    let label: String
    @Binding var isOn: Bool

    init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.557, green: 0.557, blue: 0.576))
            Spacer()
            // Custom toggle
            ZStack {
                Capsule()
                    .fill(isOn ? Color(red: 0.188, green: 0.820, blue: 0.345) : Color(red: 0.227, green: 0.227, blue: 0.235))
                    .frame(width: 36, height: 20)
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .offset(x: isOn ? 8 : -8)
                    .animation(.easeInOut(duration: 0.15), value: isOn)
            }
            .onTapGesture { isOn.toggle() }
        }
    }
}
