import SwiftUI
import AppKit

struct RealtimeCaptionView: View {
    @State private var captionService = RealtimeCaptionService()
    @State private var selectedModel = "tiny"
    @State private var selectedLanguage = "it"
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(captionService.isActive ? .red : .gray.opacity(0.5))
                        .frame(width: 10, height: 10)
                        .overlay {
                            if captionService.isActive {
                                Circle()
                                    .fill(.red.opacity(0.3))
                                    .frame(width: 18, height: 18)
                            }
                        }

                    Text("Live Captions")
                        .font(.title3)
                        .fontWeight(.semibold)
                }

                Spacer()

                if !captionService.isActive {
                    // Model picker
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Model")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Picker("", selection: $selectedModel) {
                            Text("tiny (fast)").tag("tiny")
                            Text("base").tag("base")
                            Text("small (accurate)").tag("small")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }

                    // Language picker
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Language")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Picker("", selection: $selectedLanguage) {
                            Text("Auto Detect").tag("auto")
                            Divider()
                            Text("Italiano").tag("it")
                            Text("English").tag("en")
                            Text("Español").tag("es")
                            Text("Français").tag("fr")
                            Text("Deutsch").tag("de")
                            Text("Português").tag("pt")
                            Text("日本語").tag("ja")
                            Text("中文").tag("zh")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }
                }

                Button(action: toggleCaptions) {
                    HStack(spacing: 4) {
                        Image(systemName: captionService.isActive ? "stop.fill" : "mic.fill")
                        Text(captionService.isActive ? "Stop" : "Start")
                    }
                    .frame(width: 80)
                }
                .buttonStyle(.borderedProminent)
                .tint(captionService.isActive ? .red : .accentColor)
                .controlSize(.regular)
            }
            .padding(16)

            Divider()

            // Main content area
            ZStack {
                if captionService.segments.isEmpty && !captionService.isActive && errorMessage == nil {
                    // Empty state
                    VStack(spacing: 12) {
                        Image(systemName: "captions.bubble")
                            .font(.system(size: 40))
                            .foregroundStyle(.quaternary)
                        Text("Press Start to begin live transcription")
                            .foregroundStyle(.tertiary)
                        Text("Tip: Set your language for better accuracy")
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                    }
                } else if captionService.segments.isEmpty && captionService.isActive {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Listening...")
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                } else {
                    // Transcript
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(captionService.segments.enumerated()), id: \.offset) { index, segment in
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text(formatTime(segment.time))
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                            .frame(width: 60, alignment: .trailing)

                                        Text(segment.text)
                                            .font(.system(size: 18))
                                            .lineSpacing(5)
                                            .textSelection(.enabled)
                                    }
                                    .padding(.vertical, 4)
                                    .id(index)
                                }

                                // Current live text
                                if captionService.isActive && !captionService.currentText.isEmpty {
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text("now")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.blue)
                                            .frame(width: 60, alignment: .trailing)

                                        Text(captionService.currentText)
                                            .font(.system(size: 18, weight: .medium))
                                            .lineSpacing(5)
                                    }
                                    .padding(.vertical, 4)
                                    .id("current")
                                }
                            }
                            .padding(20)
                        }
                        .onChange(of: captionService.currentText) {
                            withAnimation {
                                proxy.scrollTo("current", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Error
            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Settings") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)
                .background(.red.opacity(0.1))
            }

            // Footer
            if !captionService.segments.isEmpty {
                Divider()
                HStack {
                    Text("\(captionService.segments.count) segments")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Button {
                        let text = captionService.segments.map(\.text).joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } label: {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 650, height: 500)
        .onDisappear {
            if captionService.isActive {
                captionService.stop()
            }
        }
    }

    private func toggleCaptions() {
        if captionService.isActive {
            captionService.stop()
        } else {
            errorMessage = nil
            Task {
                do {
                    captionService.language = selectedLanguage
                    try await captionService.start(modelName: selectedModel)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
