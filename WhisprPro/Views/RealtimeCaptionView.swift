import SwiftUI

struct RealtimeCaptionView: View {
    @State private var captionService = RealtimeCaptionService()
    @State private var selectedModel = "tiny"
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(captionService.isActive ? .red : .gray)
                    .frame(width: 8, height: 8)

                Text("Live Captions")
                    .font(.headline)

                Spacer()

                if !captionService.isActive {
                    Picker("Model", selection: $selectedModel) {
                        Text("tiny").tag("tiny")
                        Text("base").tag("base")
                        Text("small").tag("small")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 80)
                }

                Button(captionService.isActive ? "Stop" : "Start") {
                    toggleCaptions()
                }
                .buttonStyle(.borderedProminent)
                .tint(captionService.isActive ? .red : .accentColor)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Caption display
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if captionService.segments.isEmpty && captionService.isActive {
                            Text("Listening...")
                                .foregroundStyle(.tertiary)
                                .italic()
                                .padding()
                        }

                        ForEach(Array(captionService.segments.enumerated()), id: \.offset) { index, segment in
                            HStack(alignment: .top, spacing: 8) {
                                Text(formatTime(segment.time))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 50, alignment: .trailing)

                                Text(segment.text)
                                    .font(.system(size: 16))
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                            }
                            .id(index)
                        }

                        // Current live text
                        if captionService.isActive && !captionService.currentText.isEmpty {
                            HStack(alignment: .top, spacing: 8) {
                                Text("now")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.blue)
                                    .frame(width: 50, alignment: .trailing)

                                Text(captionService.currentText)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineSpacing(4)
                            }
                            .id("current")
                        }
                    }
                    .padding()
                }
                .onChange(of: captionService.currentText) {
                    withAnimation {
                        proxy.scrollTo("current", anchor: .bottom)
                    }
                }
            }

            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            // Footer with copy all
            if !captionService.segments.isEmpty {
                Divider()
                HStack {
                    Text("\(captionService.segments.count) segments")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Copy All") {
                        let text = captionService.segments.map(\.text).joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 500)
        .frame(minHeight: 300, maxHeight: 600)
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
