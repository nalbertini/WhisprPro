import SwiftUI

struct YouTubeImportView: View {
    @State private var urlText = ""
    @State private var isDownloading = false
    @State private var progressText = ""
    @State private var errorMessage: String?

    let onComplete: (URL, String, TimeInterval) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "play.rectangle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                Text("YouTube Transcription")
                    .font(.headline)
            }

            // URL input
            VStack(alignment: .leading, spacing: 6) {
                Text("Paste a YouTube URL:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("https://youtube.com/watch?v=...", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { startDownload() }

                    Button("Paste") {
                        if let clip = NSPasteboard.general.string(forType: .string) {
                            urlText = clip
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // yt-dlp status
            if !YouTubeService.isAvailable() {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("yt-dlp not found. Install with: brew install yt-dlp")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(8)
                .background(.orange.opacity(0.1))
                .cornerRadius(6)
            }

            // Progress
            if isDownloading {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(progressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            // Error
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Download & Transcribe") {
                    startDownload()
                }
                .buttonStyle(.borderedProminent)
                .disabled(urlText.isEmpty || isDownloading || !YouTubeService.isAvailable())
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func startDownload() {
        guard !urlText.isEmpty else { return }
        isDownloading = true
        errorMessage = nil
        progressText = "Starting download..."

        Task {
            let service = YouTubeService()
            do {
                let result = try await service.downloadAudio(url: urlText) { status in
                    Task { @MainActor in
                        progressText = status
                    }
                }
                await MainActor.run {
                    onComplete(result.audioURL, result.title, result.duration)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isDownloading = false
                }
            }
        }
    }
}
