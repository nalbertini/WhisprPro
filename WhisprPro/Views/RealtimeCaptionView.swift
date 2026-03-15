import SwiftUI
import AppKit

struct RealtimeCaptionView: View {
    @State private var captionService = RealtimeCaptionService()
    @State private var selectedModel = "tiny"
    @State private var selectedLanguage = "it"
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    // Design tokens
    private let textPrimary = Color(red: 0.961, green: 0.961, blue: 0.969)     // #F5F5F7
    private let textSecondary = Color(red: 0.898, green: 0.898, blue: 0.918)   // #E5E5EA
    private let textTertiary = Color(red: 0.557, green: 0.557, blue: 0.576)    // #8E8E93
    private let textQuaternary = Color(red: 0.388, green: 0.388, blue: 0.400)  // #636366
    private let accentRed = Color(red: 1.0, green: 0.271, blue: 0.227)         // #FF453A
    private let accentBlue = Color(red: 0.039, green: 0.518, blue: 1.0)        // #0A84FF
    private let cardBackground = Color(red: 0.220, green: 0.220, blue: 0.228)  // #38383A
    private let borderColor = Color(red: 0.227, green: 0.227, blue: 0.235)     // #3A3A3C

    private var downloadedModels: [(name: String, label: String)] {
        let manager = ModelManager()
        let all = [
            ("tiny", "tiny (fast)"),
            ("base", "base"),
            ("small", "small (accurate)"),
            ("medium", "medium"),
            ("large-v3", "large-v3"),
            ("large-v3-turbo", "large-v3-turbo"),
        ]
        return all.filter { manager.isModelDownloaded(name: $0.0, kind: .whisper) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                // Status indicator
                HStack(spacing: 6) {
                    ZStack {
                        if captionService.isActive {
                            Circle()
                                .fill(accentRed.opacity(0.3))
                                .frame(width: 18, height: 18)
                        }
                        Circle()
                            .fill(captionService.isActive ? accentRed : Color(red: 0.5, green: 0.5, blue: 0.5, opacity: 0.5))
                            .frame(width: 10, height: 10)
                    }

                    Text("Live Captions")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(textPrimary)
                }

                Spacer()

                if !captionService.isActive {
                    // Model picker
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Model")
                            .font(.system(size: 10))
                            .foregroundStyle(textTertiary)
                        Picker("", selection: $selectedModel) {
                            ForEach(downloadedModels, id: \.name) { model in
                                Text(model.label).tag(model.name)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 150)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(cardBackground)
                        .cornerRadius(6)
                    }

                    // Language picker
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Language")
                            .font(.system(size: 10))
                            .foregroundStyle(textTertiary)
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
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(cardBackground)
                        .cornerRadius(6)
                    }
                }

                Button(action: toggleCaptions) {
                    HStack(spacing: 4) {
                        Image(systemName: captionService.isActive ? "stop.fill" : "mic.fill")
                        Text(captionService.isActive ? "Stop" : "Start")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 80)
                    .padding(.vertical, 7)
                    .background(captionService.isActive ? accentRed : accentBlue)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(downloadedModels.isEmpty && !captionService.isActive)
            }
            .padding(16)

            Divider()
                .background(borderColor)

            // Main content area
            ZStack {
                if captionService.segments.isEmpty && !captionService.isActive && errorMessage == nil {
                    // Empty state
                    VStack(spacing: 12) {
                        Image(systemName: "captions.bubble")
                            .font(.system(size: 40))
                            .foregroundStyle(textQuaternary)
                        if downloadedModels.isEmpty {
                            Text("No models downloaded")
                                .foregroundStyle(textSecondary)
                            Text("Go to Settings > Models to download one")
                                .font(.system(size: 12))
                                .foregroundStyle(textTertiary)
                        } else {
                            Text("Press Start to begin live transcription")
                                .foregroundStyle(textTertiary)
                            Text("Tip: Set your language for better accuracy")
                                .font(.system(size: 12))
                                .foregroundStyle(textQuaternary)
                        }
                    }
                } else if captionService.segments.isEmpty && captionService.isActive {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Listening...")
                            .foregroundStyle(textSecondary)
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
                                            .foregroundStyle(textQuaternary)
                                            .frame(width: 60, alignment: .trailing)

                                        Text(segment.text)
                                            .font(.system(size: 17))
                                            .foregroundStyle(textSecondary)
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
                                            .foregroundStyle(accentBlue)
                                            .frame(width: 60, alignment: .trailing)

                                        Text(captionService.currentText)
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(textPrimary)
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
                        .foregroundStyle(accentRed)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(accentRed)
                    Spacer()
                    Button("Open Settings") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if #available(macOS 14.0, *) {
                                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)
                .background(accentRed.opacity(0.1))
            }

            // Footer
            if !captionService.segments.isEmpty {
                Divider()
                    .background(borderColor)
                HStack {
                    Text("\(captionService.segments.count) segments")
                        .font(.system(size: 11))
                        .foregroundStyle(textQuaternary)

                    Spacer()

                    Button {
                        let text = captionService.segments.map(\.text).joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } label: {
                        Label("Copy All", systemImage: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(cardBackground)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
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
