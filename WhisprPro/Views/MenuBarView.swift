import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Query(sort: \Transcription.createdAt, order: .reverse)
    private var transcriptions: [Transcription]

    let onImport: () -> Void
    let onRecord: () -> Void
    let onOpenMain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "waveform")
                    .font(.title3)
                Text("WhisprPro")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            // Quick actions
            VStack(spacing: 2) {
                MenuBarButton(icon: "doc.badge.plus", title: "Import File...", shortcut: "⌘I") {
                    onImport()
                }

                MenuBarButton(icon: "record.circle", title: "New Recording", shortcut: "⇧⌘R", tint: .red) {
                    onRecord()
                }
            }
            .padding(.vertical, 4)

            Divider()

            // Recent transcriptions
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                if transcriptions.isEmpty {
                    Text("No transcriptions yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                } else {
                    ForEach(transcriptions.prefix(5)) { transcription in
                        Button {
                            onOpenMain()
                        } label: {
                            HStack {
                                statusIcon(for: transcription)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(transcription.title)
                                        .font(.body)
                                        .lineLimit(1)
                                    Text(formatDate(transcription.createdAt))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Text(formatDuration(transcription.duration))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // Footer
            VStack(spacing: 2) {
                MenuBarButton(icon: "macwindow", title: "Open WhisprPro") {
                    onOpenMain()
                }

                MenuBarButton(icon: "gear", title: "Settings...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }

                Divider()

                MenuBarButton(icon: "power", title: "Quit WhisprPro", shortcut: "⌘Q") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 300)
    }

    @ViewBuilder
    private func statusIcon(for transcription: Transcription) -> some View {
        switch transcription.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .transcribing, .diarizing:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 14, height: 14)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct MenuBarButton: View {
    let icon: String
    let title: String
    var shortcut: String? = nil
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundStyle(tint ?? .primary)
                Text(title)
                    .foregroundStyle(tint ?? .primary)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
