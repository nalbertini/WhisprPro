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

    // Design tokens
    private let textPrimary = Color(red: 0.961, green: 0.961, blue: 0.969)     // #F5F5F7
    private let textTertiary = Color(red: 0.557, green: 0.557, blue: 0.576)    // #8E8E93
    private let textQuaternary = Color(red: 0.388, green: 0.388, blue: 0.400)  // #636366
    private let accentRed = Color(red: 1.0, green: 0.271, blue: 0.227)         // #FF453A
    private let accentBlue = Color(red: 0.039, green: 0.518, blue: 1.0)        // #0A84FF
    private let cardBackground = Color(red: 0.220, green: 0.220, blue: 0.228)  // #38383A
    private let sidebarBackground = Color(red: 0.173, green: 0.173, blue: 0.180) // #2C2C2E

    private var isRecording: Bool {
        recordingService.isRecording || systemAudioService.isRecording
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Title
                Text("New Recording")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(textPrimary)

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
                            .fill(isRecording ? accentRed : accentRed.opacity(0.15))
                            .frame(width: 100, height: 100)

                        Circle()
                            .strokeBorder(accentRed, lineWidth: 3)
                            .frame(width: 100, height: 100)

                        if isRecording {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white)
                                .frame(width: 32, height: 32)
                        } else {
                            Circle()
                                .fill(accentRed)
                                .frame(width: 36, height: 36)
                        }
                    }
                }
                .buttonStyle(.plain)

                // Timer
                Text(formatTime(recordSystemAudio ? systemAudioService.elapsedTime : recordingService.elapsedTime))
                    .font(.system(size: 52, weight: .ultraLight, design: .monospaced))
                    .foregroundStyle(isRecording ? textPrimary : textQuaternary)

                // Waveform (mic only)
                if !recordSystemAudio && recordingService.isRecording {
                    WaveformView(level: recordingService.audioLevel)
                        .frame(height: 40)
                        .frame(width: 300)

                    // Show active mic name
                    HStack(spacing: 4) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(accentRed)
                        Text(activeMicName)
                            .font(.system(size: 12))
                            .foregroundStyle(textTertiary)
                    }
                }

                if recordSystemAudio && systemAudioService.isRecording {
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(.orange)
                        Text("Capturing system audio...")
                            .foregroundStyle(textTertiary)
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
                HStack(spacing: 12) {
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
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(textPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(cardBackground)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            stopAndTranscribe()
                        } label: {
                            Label("Stop & Transcribe", systemImage: "stop.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(accentBlue)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Button("Cancel") {
                            cancelRecording()
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(cardBackground)
                        .cornerRadius(8)
                        .buttonStyle(.plain)
                    } else {
                        Button("Back") {
                            viewModel.isRecordingMode = false
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(cardBackground)
                        .cornerRadius(8)
                        .buttonStyle(.plain)

                        Button {
                            showLiveCaptions = true
                        } label: {
                            Label("Live Captions", systemImage: "captions.bubble")
                                .font(.system(size: 12))
                                .foregroundStyle(textQuaternary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Error
                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(accentRed)
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
