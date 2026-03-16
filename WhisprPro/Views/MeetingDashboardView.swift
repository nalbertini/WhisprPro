import SwiftUI
import AppKit

struct MeetingDashboardView: View {
    @Bindable var viewModel: TranscriptionViewModel
    @State private var mixedAudioService = MixedAudioService()
    @State private var captionService = RealtimeCaptionService()
    @State private var selectedDeviceID: String?
    @State private var errorMessage: String?
    @State private var speakers: [MeetingSpeaker] = []
    @State private var actionItems: [String] = []
    @State private var isExtracting = false
    @State private var meetingLanguage = "it"

    struct MeetingSpeaker: Identifiable {
        let id = UUID()
        var name: String
        var color: Color
        var segmentCount: Int = 0
    }

    private let textPrimary = Color(red: 0.961, green: 0.961, blue: 0.969)
    private let textSecondary = Color(red: 0.898, green: 0.898, blue: 0.918)
    private let textTertiary = Color(red: 0.557, green: 0.557, blue: 0.576)
    private let textQuaternary = Color(red: 0.388, green: 0.388, blue: 0.400)
    private let accentRed = Color(red: 1.0, green: 0.271, blue: 0.227)
    private let accentBlue = Color(red: 0.039, green: 0.518, blue: 1.0)
    private let accentGreen = Color(red: 0.188, green: 0.820, blue: 0.345)
    private let cardBackground = Color(red: 0.173, green: 0.173, blue: 0.180)
    private let borderColor = Color(red: 0.227, green: 0.227, blue: 0.235)

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                // Recording indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(mixedAudioService.isRecording ? accentRed : .gray)
                        .frame(width: 10, height: 10)
                    Text("Meeting")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(textPrimary)
                }

                // Timer
                Text(formatTime(mixedAudioService.elapsedTime))
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(mixedAudioService.isRecording ? textPrimary : textQuaternary)

                Spacer()

                // Language picker
                Picker("", selection: $meetingLanguage) {
                    Text("IT").tag("it")
                    Text("EN").tag("en")
                    Text("ES").tag("es")
                    Text("FR").tag("fr")
                    Text("DE").tag("de")
                }
                .pickerStyle(.menu)
                .frame(width: 60)

                // Controls
                if mixedAudioService.isRecording {
                    Button {
                        stopMeeting()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                            Text("End Meeting")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(accentRed)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        startMeeting()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "record.circle")
                            Text("Start Meeting")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(accentGreen)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Button("Back") {
                        viewModel.isRecordingMode = false
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(textTertiary)
                }
            }
            .padding(16)
            .background(cardBackground)

            Divider().background(borderColor)

            // Main content
            HStack(spacing: 0) {
                // Left: Live transcript
                VStack(alignment: .leading, spacing: 0) {
                    // Section header
                    HStack {
                        Text("LIVE TRANSCRIPT")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(textQuaternary)
                            .kerning(0.55)
                        Spacer()
                        Text("\(captionService.segments.count) segments")
                            .font(.system(size: 11))
                            .foregroundStyle(textQuaternary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider().background(borderColor)

                    // Transcript
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(captionService.segments.enumerated()), id: \.offset) { index, segment in
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text(formatCaptionTime(segment.time))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(textQuaternary)
                                            .frame(width: 55, alignment: .trailing)

                                        Text(segment.text)
                                            .font(.system(size: 15))
                                            .foregroundStyle(textSecondary)
                                            .lineSpacing(4)
                                            .textSelection(.enabled)
                                    }
                                    .padding(.vertical, 4)
                                    .id(index)
                                }

                                // Current live text
                                if captionService.isActive && !captionService.currentText.isEmpty {
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text("now")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(accentBlue)
                                            .frame(width: 55, alignment: .trailing)

                                        Text(captionService.currentText)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(textPrimary)
                                            .lineSpacing(4)
                                    }
                                    .padding(.vertical, 4)
                                    .id("current")
                                }
                            }
                            .padding(16)
                        }
                        .onChange(of: captionService.currentText) {
                            withAnimation {
                                proxy.scrollTo("current", anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                Divider().background(borderColor)

                // Right: Sidebar with speakers & action items
                VStack(alignment: .leading, spacing: 0) {
                    // Speakers section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PARTICIPANTS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(textQuaternary)
                            .kerning(0.55)

                        if speakers.isEmpty {
                            Text("Speakers will appear here")
                                .font(.system(size: 12))
                                .foregroundStyle(textQuaternary)
                        }

                        ForEach($speakers) { $speaker in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(speaker.color)
                                    .frame(width: 8, height: 8)
                                TextField("Name", text: $speaker.name)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13))
                                    .foregroundStyle(textPrimary)
                            }
                        }

                        Button {
                            let colors: [Color] = [accentBlue, .orange, accentGreen, .purple, .pink, .cyan]
                            speakers.append(MeetingSpeaker(
                                name: "Person \(speakers.count + 1)",
                                color: colors[speakers.count % colors.count]
                            ))
                        } label: {
                            Label("Add Person", systemImage: "person.badge.plus")
                                .font(.system(size: 12))
                                .foregroundStyle(accentBlue)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)

                    Divider().background(borderColor)

                    // Action items section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("ACTION ITEMS")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(textQuaternary)
                                .kerning(0.55)
                            Spacer()
                            if !captionService.segments.isEmpty {
                                Button {
                                    extractActionItems()
                                } label: {
                                    if isExtracting {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                    } else {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color(red: 0.749, green: 0.353, blue: 0.949))
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(isExtracting)
                            }
                        }

                        if actionItems.isEmpty {
                            Text("Click \u{2728} to extract action items")
                                .font(.system(size: 11))
                                .foregroundStyle(textQuaternary)
                        } else {
                            ForEach(actionItems, id: \.self) { item in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(accentGreen)
                                        .padding(.top, 2)
                                    Text(item)
                                        .font(.system(size: 12))
                                        .foregroundStyle(textSecondary)
                                        .lineSpacing(2)
                                }
                            }
                        }
                    }
                    .padding(16)

                    Spacer()

                    // Copy all button
                    if !captionService.segments.isEmpty {
                        Divider().background(borderColor)
                        HStack {
                            Button {
                                copyMeetingNotes()
                            } label: {
                                Label("Copy Meeting Notes", systemImage: "doc.on.doc")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(textSecondary)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .padding(12)
                    }
                }
                .frame(width: 240)
                .background(cardBackground)
            }

            // Error
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(accentRed)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(accentRed)
                    Spacer()
                }
                .padding(12)
                .background(accentRed.opacity(0.1))
            }
        }
    }

    private func startMeeting() {
        errorMessage = nil

        // Start mixed audio (mic + system)
        Task {
            do {
                try await mixedAudioService.startRecording()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
                return
            }

            // Also start live captions
            captionService.language = meetingLanguage
            do {
                try await captionService.start(modelName: UserDefaults.standard.string(forKey: "defaultModel") ?? "tiny")
            } catch {
                // Captions failed but recording continues
            }
        }
    }

    private func stopMeeting() {
        // Stop captions
        captionService.stop()

        // Stop recording and transcribe
        Task {
            do {
                let url = try await mixedAudioService.stopRecording()
                await MainActor.run {
                    viewModel.isRecordingMode = false
                }
                await viewModel.importFile(url: url)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func extractActionItems() {
        guard AIService.isAvailable else {
            errorMessage = "Claude CLI not found"
            return
        }

        isExtracting = true
        let transcript = captionService.segments.map(\.text).joined(separator: "\n")

        Task {
            let service = AIService()
            do {
                let result = try await service.runPrompt(
                    transcript: transcript,
                    action: .extractKeyPoints,
                    progress: { _ in }
                )
                await MainActor.run {
                    actionItems = result.components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        .map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 }
                        .map { $0.hasPrefix("• ") ? String($0.dropFirst(2)) : $0 }
                    isExtracting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isExtracting = false
                }
            }
        }
    }

    private func copyMeetingNotes() {
        var notes = "# Meeting Notes\n"
        notes += "**Date:** \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))\n"
        notes += "**Duration:** \(formatTime(mixedAudioService.elapsedTime))\n\n"

        if !speakers.isEmpty {
            notes += "## Participants\n"
            for speaker in speakers {
                notes += "- \(speaker.name)\n"
            }
            notes += "\n"
        }

        notes += "## Transcript\n\n"
        for segment in captionService.segments {
            notes += "\(segment.text)\n\n"
        }

        if !actionItems.isEmpty {
            notes += "## Action Items\n\n"
            for item in actionItems {
                notes += "- [ ] \(item)\n"
            }
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(notes, forType: .string)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func formatCaptionTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
