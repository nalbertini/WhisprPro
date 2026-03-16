import Foundation
import os

private let logger = Logger(subsystem: "com.whisprpro", category: "AI")

actor AIService {

    enum AIProvider: String, CaseIterable {
        case claudeCLI = "Claude CLI"
        case claudeDesktop = "Claude Desktop"
    }

    enum AIAction: String, CaseIterable {
        case summarize = "Summarize"
        case fixGrammar = "Fix Grammar & Punctuation"
        case translate = "Translate"
        case askQuestion = "Ask a Question"
        case extractKeyPoints = "Extract Key Points"
        case generateTitle = "Generate Title"
        case custom = "Custom Prompt"
        case meetingNotes = "Meeting Notes"
    }

    /// Find Claude CLI path
    static func claudeCLIPath() -> String? {
        let paths = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    static var isAvailable: Bool {
        claudeCLIPath() != nil
    }

    /// Run a prompt against the transcript using Claude CLI
    func runPrompt(
        transcript: String,
        action: AIAction,
        customPrompt: String = "",
        targetLanguage: String = "English",
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let claudePath = Self.claudeCLIPath() else {
            throw AIServiceError.claudeNotFound
        }

        let systemPrompt: String
        switch action {
        case .summarize:
            systemPrompt = "Summarize the following transcript concisely. Keep the key points and main ideas. Output only the summary, no preamble."
        case .fixGrammar:
            systemPrompt = "Fix the grammar, spelling, and punctuation of the following transcript. Keep the original meaning and structure. Output only the corrected text, no preamble."
        case .translate:
            systemPrompt = "Translate the following transcript to \(targetLanguage). Output only the translation, no preamble."
        case .askQuestion:
            systemPrompt = "Based on the following transcript, answer this question: \(customPrompt)\n\nOutput only the answer."
        case .extractKeyPoints:
            systemPrompt = "Extract the key points from the following transcript as a bullet-point list. Output only the list, no preamble."
        case .generateTitle:
            systemPrompt = "Generate a concise, descriptive title for the following transcript. Output only the title, nothing else."
        case .custom:
            systemPrompt = customPrompt
        case .meetingNotes:
            systemPrompt = """
            Generate structured meeting notes from the following transcript. Include:
            - **Meeting Title** (infer from context)
            - **Key Discussion Points** (bullet list)
            - **Decisions Made** (if any)
            - **Action Items** (who does what, if identifiable)
            - **Summary** (2-3 sentences)

            Output in Markdown format. Be concise and professional.
            """
        }

        let fullPrompt = "\(systemPrompt)\n\n---\nTRANSCRIPT:\n\(transcript)\n---"

        logger.info("Running AI action: \(action.rawValue)")
        progress("Thinking...")

        // Run claude CLI with --print flag for non-interactive output
        let result = try await runClaudeCLI(
            path: claudePath,
            prompt: fullPrompt,
            progress: progress
        )

        return result
    }

    private func runClaudeCLI(
        path: String,
        prompt: String,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let result: (exitCode: Int32, stdout: String, stderr: String) = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: path)
                    proc.arguments = [
                        "-p",  // Non-interactive, print response
                        prompt
                    ]

                    var env = ProcessInfo.processInfo.environment
                    env["PATH"] = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                    proc.environment = env

                    let outPipe = Pipe()
                    let errPipe = Pipe()
                    proc.standardOutput = outPipe
                    proc.standardError = errPipe

                    var stdoutData = Data()
                    var stderrData = Data()

                    outPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if !data.isEmpty {
                            stdoutData.append(data)
                            progress("Generating response...")
                        }
                    }

                    errPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if !data.isEmpty { stderrData.append(data) }
                    }

                    proc.terminationHandler = { p in
                        outPipe.fileHandleForReading.readabilityHandler = nil
                        errPipe.fileHandleForReading.readabilityHandler = nil
                        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                        continuation.resume(returning: (p.terminationStatus, stdout, stderr))
                    }

                    try proc.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        guard result.exitCode == 0 else {
            let errMsg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.error("Claude CLI failed: \(errMsg)")
            throw AIServiceError.claudeFailed(errMsg.isEmpty ? "Exit code \(result.exitCode)" : errMsg)
        }

        let response = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.info("AI response: \(response.prefix(100))...")
        progress("Done!")

        return response
    }
}

enum AIServiceError: Error, LocalizedError {
    case claudeNotFound
    case claudeFailed(String)

    var errorDescription: String? {
        switch self {
        case .claudeNotFound: "Claude CLI not found. Install Claude Code: npm install -g @anthropic-ai/claude-code"
        case .claudeFailed(let msg): "Claude error: \(msg)"
        }
    }
}
