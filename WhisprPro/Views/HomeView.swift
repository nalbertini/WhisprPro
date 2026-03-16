import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Transcription.createdAt, order: .reverse)
    private var transcriptions: [Transcription]

    let onImport: () -> Void
    let onRecord: () -> Void
    let onYouTube: () -> Void
    let onMeeting: () -> Void
    let onLiveCaptions: () -> Void
    let onSelectTranscription: (Transcription) -> Void

    // Design tokens
    private let textPrimary = Color(red: 0.961, green: 0.961, blue: 0.969)
    private let textSecondary = Color(red: 0.898, green: 0.898, blue: 0.918)
    private let textTertiary = Color(red: 0.557, green: 0.557, blue: 0.576)
    private let textQuaternary = Color(red: 0.388, green: 0.388, blue: 0.400)
    private let textMuted = Color(red: 0.290, green: 0.290, blue: 0.306)
    private let cardBackground = Color(red: 0.173, green: 0.173, blue: 0.180)
    private let cardBorder = Color(red: 0.227, green: 0.227, blue: 0.235)
    private let pillBackground = Color(red: 0.220, green: 0.220, blue: 0.228)

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                // Greeting
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(textPrimary)
                        .tracking(-0.5)
                    Text("What would you like to transcribe today?")
                        .font(.system(size: 15))
                        .foregroundStyle(textQuaternary)
                }

                // Quick actions
                HStack(spacing: 12) {
                    QuickActionCard(
                        icon: "record.circle",
                        iconColor: Color(red: 1.0, green: 0.271, blue: 0.227),
                        title: "Record",
                        subtitle: "Mic or system audio",
                        shortcut: "⇧⌘R",
                        action: onRecord
                    )
                    QuickActionCard(
                        icon: "doc.badge.plus",
                        iconColor: Color(red: 0.039, green: 0.518, blue: 1.0),
                        title: "Import File",
                        subtitle: "Audio or video files",
                        shortcut: "⌘I",
                        action: onImport
                    )
                    QuickActionCard(
                        icon: "play.rectangle.fill",
                        iconColor: Color(red: 1.0, green: 0.271, blue: 0.227),
                        title: "YouTube",
                        subtitle: "Paste a video URL",
                        shortcut: "⇧⌘Y",
                        action: onYouTube
                    )
                    QuickActionCard(
                        icon: "person.2.fill",
                        iconColor: Color(red: 0.188, green: 0.820, blue: 0.345),
                        title: "Meeting",
                        subtitle: "Mic + system audio",
                        shortcut: "⇧⌘M",
                        action: onMeeting
                    )
                    QuickActionCard(
                        icon: "captions.bubble",
                        iconColor: Color(red: 0.749, green: 0.353, blue: 0.949),
                        title: "Live Captions",
                        subtitle: "Real-time subtitles",
                        shortcut: "⇧⌘L",
                        action: onLiveCaptions
                    )
                }

                // Recent transcriptions
                if !transcriptions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("RECENT TRANSCRIPTIONS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(textQuaternary)
                            .kerning(0.55)

                        ForEach(transcriptions.prefix(5)) { transcription in
                            Button {
                                onSelectTranscription(transcription)
                            } label: {
                                RecentTranscriptionRow(transcription: transcription)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Drag & drop hint
                HStack {
                    Spacer()
                    Text("Drop audio or video files anywhere to transcribe")
                        .font(.system(size: 12))
                        .foregroundStyle(textMuted)
                    Spacer()
                }
                .padding(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        .foregroundStyle(cardBorder)
                )
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 36)
        }
    }
}

// MARK: - Quick Action Card

private struct QuickActionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let shortcut: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(iconColor)
                    .frame(width: 48, height: 48)
                    .background(iconColor.opacity(0.12))
                    .cornerRadius(12)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.961, green: 0.961, blue: 0.969))

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.388, green: 0.388, blue: 0.400))

                Text(shortcut)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(red: 0.290, green: 0.290, blue: 0.306))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.220, green: 0.220, blue: 0.228))
                    .cornerRadius(3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 16)
            .background(Color(red: 0.173, green: 0.173, blue: 0.180))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.227, green: 0.227, blue: 0.235), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recent Transcription Row

private struct RecentTranscriptionRow: View {
    let transcription: Transcription

    var body: some View {
        HStack(spacing: 14) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(transcription.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 0.961, green: 0.961, blue: 0.969))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(relativeDate)
                    Text("·")
                    Text(formatDuration(transcription.duration))
                    if !transcription.speakers.isEmpty {
                        Text("·")
                        Text("\(transcription.speakers.count) speakers")
                    }
                    Text("·")
                    Text(transcription.modelName)
                }
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.388, green: 0.388, blue: 0.400))
                .lineLimit(1)
            }

            Spacer()

            // Type badge
            if transcription.title.contains("YouTube") || transcription.title.contains("youtube") {
                TypeBadge(text: "YouTube", color: Color(red: 1.0, green: 0.271, blue: 0.227))
            } else if transcription.title.contains("Meeting") || transcription.title.contains("meeting") {
                TypeBadge(text: "Meeting", color: Color(red: 0.188, green: 0.820, blue: 0.345))
            } else if transcription.title.contains("Recording") {
                TypeBadge(text: "Recording", color: Color(red: 0.557, green: 0.557, blue: 0.576))
            } else {
                TypeBadge(text: "Import", color: Color(red: 0.557, green: 0.557, blue: 0.576))
            }
        }
        .padding(14)
        .background(Color(red: 0.173, green: 0.173, blue: 0.180))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.227, green: 0.227, blue: 0.235), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch transcription.status {
        case .completed: Color(red: 0.188, green: 0.820, blue: 0.345)
        case .transcribing, .diarizing: Color(red: 1.0, green: 0.624, blue: 0.039)
        case .failed: Color(red: 1.0, green: 0.271, blue: 0.227)
        case .pending: Color(red: 0.557, green: 0.557, blue: 0.576)
        }
    }

    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: transcription.createdAt, relativeTo: Date())
    }

    private func formatDuration(_ d: TimeInterval) -> String {
        let m = Int(d) / 60
        let s = Int(d) % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct TypeBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .cornerRadius(5)
    }
}
