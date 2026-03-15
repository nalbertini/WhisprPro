import SwiftUI
import AVFoundation

struct InlineRecordingView: View {
    @Bindable var viewModel: TranscriptionViewModel
    @Bindable var playerViewModel: AudioPlayerViewModel

    @State private var recordingService = RecordingService()
    @State private var systemAudioService = SystemAudioService()
    @State private var recordSystemAudio = false
    @State private var selectedDeviceID: String?
    @State private var errorMessage: String?
    @State private var showLiveCaptions = false

    private var isRecording: Bool {
        recordingService.isRecording || systemAudioService.isRecording
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Title
                Text("New Recording")
                    .font(.title2)
                    .fontWeight(.semibold)

                // Source picker
                Picker("", selection: $recordSystemAudio) {
                    Text("Microphone").tag(false)
                    Text("System Audio").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                .disabled(isRecording)

                // Record button
                Button(action: toggleRecording) {
                    ZStack {
                        Circle()
                            .fill(isRecording ? .red : .red.opacity(0.15))
                            .frame(width: 100, height: 100)

                        Circle()
                            .strokeBorder(.red, lineWidth: 3)
                            .frame(width: 100, height: 100)

                        if isRecording {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white)
                                .frame(width: 32, height: 32)
                        } else {
                            Circle()
                                .fill(.red)
                                .frame(width: 36, height: 36)
                        }
                    }
                }
                .buttonStyle(.plain)

                // Timer
                Text(formatTime(recordSystemAudio ? systemAudioService.elapsedTime : recordingService.elapsedTime))
                    .font(.system(size: 48, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(isRecording ? .primary : .tertiary)

                // Waveform (mic only)
                if !recordSystemAudio && recordingService.isRecording {
                    WaveformView(level: recordingService.audioLevel)
                        .frame(height: 40)
                        .frame(width: 300)

                    // Show active mic name
                    HStack(spacing: 4) {
                        Image(systemName: "mic.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Text(activeMicName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if recordSystemAudio && systemAudioService.isRecording {
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(.orange)
                        Text("Capturing system audio...")
                            .foregroundStyle(.secondary)
                    }
                }

                // Device selector (mic only)
                if !recordSystemAudio && !isRecording {
                    let devices = RecordingService().availableInputDevices()
                    if !devices.isEmpty {
                        Picker("Input Device", selection: $selectedDeviceID) {
                            Text("Default").tag(nil as String?)
                            ForEach(devices, id: \.uniqueID) { device in
                                Text(device.localizedName).tag(device.uniqueID as String?)
                            }
                        }
                        .frame(width: 280)
                    }
                }

                // Action buttons
                HStack(spacing: 16) {
                    if isRecording {
                        // Pause (mic only)
                        if !recordSystemAudio {
                            Button {
                                if recordingService.isPaused {
                                    recordingService.resume()
                                } else {
                                    recordingService.pause()
                                }
                            } label: {
                                Label(recordingService.isPaused ? "Resume" : "Pause",
                                      systemImage: recordingService.isPaused ? "play.fill" : "pause.fill")
                            }
                            .buttonStyle(.bordered)
                        }

                        Button {
                            stopAndTranscribe()
                        } label: {
                            Label("Stop & Transcribe", systemImage: "stop.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Cancel") {
                            cancelRecording()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Back") {
                            viewModel.isRecordingMode = false
                        }
                        .buttonStyle(.bordered)

                        Button {
                            showLiveCaptions = true
                        } label: {
                            Label("Live Captions", systemImage: "captions.bubble")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Error
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 40)
                }
            }
            .frame(maxWidth: 500)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showLiveCaptions) {
            RealtimeCaptionView()
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopAndTranscribe()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        errorMessage = nil
        if recordSystemAudio {
            Task {
                do {
                    try await systemAudioService.startRecording()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } else {
            do {
                try recordingService.startRecording(deviceID: selectedDeviceID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stopAndTranscribe() {
        Task {
            do {
                let url: URL
                if recordSystemAudio {
                    url = try await systemAudioService.stopRecording()
                } else {
                    url = try recordingService.stopRecording()
                }
                viewModel.isRecordingMode = false
                await viewModel.importFile(url: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelRecording() {
        if recordSystemAudio {
            Task { _ = try? await systemAudioService.stopRecording() }
        } else {
            _ = try? recordingService.stopRecording()
        }
        viewModel.isRecordingMode = false
    }

    private var activeMicName: String {
        if let id = selectedDeviceID {
            let devices = RecordingService().availableInputDevices()
            return devices.first(where: { $0.uniqueID == id })?.localizedName ?? "Unknown"
        }
        // Get default input device name
        let devices = RecordingService().availableInputDevices()
        return devices.first?.localizedName ?? "Default Microphone"
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
