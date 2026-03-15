import SwiftUI
import AppKit

struct AIActionView: View {
    let transcription: Transcription
    @State private var selectedAction: AIService.AIAction = .summarize
    @State private var customPrompt = ""
    @State private var targetLanguage = "English"
    @State private var isProcessing = false
    @State private var result = ""
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("AI Assistant")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                if !AIService.isAvailable {
                    Label("Claude CLI not found", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding()

            Divider()

            // Action picker
            VStack(alignment: .leading, spacing: 12) {
                Picker("Action", selection: $selectedAction) {
                    ForEach(AIService.AIAction.allCases, id: \.self) { action in
                        Text(action.rawValue).tag(action)
                    }
                }
                .pickerStyle(.menu)

                if selectedAction == .translate {
                    Picker("Target Language", selection: $targetLanguage) {
                        Text("English").tag("English")
                        Text("Italian").tag("Italian")
                        Text("Spanish").tag("Spanish")
                        Text("French").tag("French")
                        Text("German").tag("German")
                        Text("Portuguese").tag("Portuguese")
                        Text("Japanese").tag("Japanese")
                        Text("Chinese").tag("Chinese")
                    }
                }

                if selectedAction == .askQuestion || selectedAction == .custom {
                    TextField(
                        selectedAction == .askQuestion ? "Ask a question about the transcript..." : "Enter your prompt...",
                        text: $customPrompt,
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                }

                Button {
                    runAction()
                } label: {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text(isProcessing ? "Processing..." : "Run with Claude")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(isProcessing || !AIService.isAvailable)
                .disabled((selectedAction == .askQuestion || selectedAction == .custom) && customPrompt.isEmpty)
            }
            .padding()

            Divider()

            // Result
            if !result.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Result")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(result, forType: .string)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Text(result)
                            .font(.body)
                            .textSelection(.enabled)
                            .lineSpacing(4)
                    }
                    .padding()
                }
            } else if let error = errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 30))
                        .foregroundStyle(.quaternary)
                    Text("Select an action and click Run")
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Footer
            Divider()
            HStack {
                Text("Powered by Claude CLI")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()
        }
        .frame(width: 550, height: 500)
    }

    private func runAction() {
        isProcessing = true
        errorMessage = nil
        result = ""

        let segments = transcription.segments.sorted { $0.startTime < $1.startTime }
        let transcript = segments.map { seg in
            var line = ""
            if let speaker = seg.speaker {
                line += "\(speaker.label): "
            }
            line += seg.text
            return line
        }.joined(separator: "\n")

        Task {
            let service = AIService()
            do {
                let response = try await service.runPrompt(
                    transcript: transcript,
                    action: selectedAction,
                    customPrompt: customPrompt,
                    targetLanguage: targetLanguage
                ) { status in
                    // Progress updates happen on background thread
                }
                await MainActor.run {
                    result = response
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}
