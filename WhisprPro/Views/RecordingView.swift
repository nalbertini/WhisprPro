import SwiftUI
import AVFoundation

struct RecordingView: View {
    @Bindable var viewModel: RecordingViewModel
    let onComplete: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var recordSystemAudio = false
    @State private var systemAudioService = SystemAudioService()
    @State private var systemAudioError: String?
    @State private var isStoppingSystemAudio = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Recording")
                .font(.headline)

            // Source picker
            Picker("Source", selection: $recordSystemAudio) {
                Text("Microphone").tag(false)
                Text("System Audio").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            .disabled(viewModel.recordingService.isRecording || systemAudioService.isRecording)

            if recordSystemAudio {
                systemAudioContent
            } else {
                micContent
            }
        }
        .padding(32)
        .frame(width: 400, height: 400)
    }

    // MARK: - Microphone UI

    @ViewBuilder
    private var micContent: some View {
        // Record button
        Button(action: toggleMicRecording) {
            Circle()
                .fill(viewModel.recordingService.isRecording ? .red : .red.opacity(0.8))
                .frame(width: 80, height: 80)
                .overlay {
                    if viewModel.recordingService.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white)
                            .frame(width: 28, height: 28)
                    } else {
                        Circle()
                            .fill(.white)
                            .frame(width: 28, height: 28)
                    }
                }
        }
        .buttonStyle(.plain)

        // Timer
        Text(formatTime(viewModel.recordingService.elapsedTime))
            .font(.system(size: 32, weight: .light, design: .monospaced))

        // Audio level
        if viewModel.recordingService.isRecording {
            WaveformView(level: viewModel.recordingService.audioLevel)
                .frame(height: 40)
        }

        // Device selector
        if !viewModel.availableDevices.isEmpty {
            Picker("Input:", selection: $viewModel.selectedDeviceID) {
                Text("Default").tag(nil as String?)
                ForEach(viewModel.availableDevices, id: \.uniqueID) { device in
                    Text(device.localizedName).tag(device.uniqueID as String?)
                }
            }
            .frame(width: 300)
        }

        // Actions
        HStack(spacing: 16) {
            Button("Cancel") {
                if viewModel.recordingService.isRecording {
                    _ = viewModel.stopAndGetFile()
                }
                dismiss()
            }

            if viewModel.recordingService.isRecording {
                Button(viewModel.recordingService.isPaused ? "Resume" : "Pause") {
                    if viewModel.recordingService.isPaused {
                        viewModel.recordingService.resume()
                    } else {
                        viewModel.recordingService.pause()
                    }
                }

                Button("Stop & Transcribe") {
                    if let url = viewModel.stopAndGetFile() {
                        onComplete(url)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }

        if let error = viewModel.errorMessage {
            Text(error)
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    // MARK: - System Audio UI

    @ViewBuilder
    private var systemAudioContent: some View {
        // Record button
        Button(action: toggleSystemAudioRecording) {
            Circle()
                .fill(systemAudioService.isRecording ? .orange : .orange.opacity(0.8))
                .frame(width: 80, height: 80)
                .overlay {
                    if systemAudioService.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white)
                            .frame(width: 28, height: 28)
                    } else {
                        Circle()
                            .fill(.white)
                            .frame(width: 28, height: 28)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isStoppingSystemAudio)

        // Timer
        Text(formatTime(systemAudioService.elapsedTime))
            .font(.system(size: 32, weight: .light, design: .monospaced))

        Text("Capturing system audio")
            .font(.caption)
            .foregroundStyle(.secondary)

        // Actions
        HStack(spacing: 16) {
            Button("Cancel") {
                if systemAudioService.isRecording {
                    Task {
                        isStoppingSystemAudio = true
                        _ = try? await systemAudioService.stopRecording()
                        isStoppingSystemAudio = false
                    }
                }
                dismiss()
            }

            if systemAudioService.isRecording {
                Button("Stop & Transcribe") {
                    Task {
                        isStoppingSystemAudio = true
                        do {
                            let url = try await systemAudioService.stopRecording()
                            isStoppingSystemAudio = false
                            onComplete(url)
                            dismiss()
                        } catch {
                            systemAudioError = error.localizedDescription
                            isStoppingSystemAudio = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isStoppingSystemAudio)
            }
        }

        if let error = systemAudioError {
            Text(error)
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    // MARK: - Helpers

    private func toggleMicRecording() {
        if viewModel.recordingService.isRecording {
            if let url = viewModel.stopAndGetFile() {
                onComplete(url)
                dismiss()
            }
        } else {
            viewModel.startRecording()
        }
    }

    private func toggleSystemAudioRecording() {
        if systemAudioService.isRecording {
            Task {
                isStoppingSystemAudio = true
                do {
                    let url = try await systemAudioService.stopRecording()
                    isStoppingSystemAudio = false
                    onComplete(url)
                    dismiss()
                } catch {
                    systemAudioError = error.localizedDescription
                    isStoppingSystemAudio = false
                }
            }
        } else {
            Task {
                do {
                    try await systemAudioService.startRecording()
                } catch {
                    systemAudioError = error.localizedDescription
                }
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct WaveformView: View {
    let level: Float
    private let barCount = 20

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.red.opacity(0.7))
                    .frame(width: 3, height: barHeight(for: i))
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let normalized = CGFloat(min(level * 10, 1.0))
        let randomFactor = CGFloat.random(in: 0.3...1.0)
        return max(4, normalized * 36 * randomFactor)
    }
}
