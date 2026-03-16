import SwiftUI
import AVFoundation
import Speech
import ScreenCaptureKit

struct OnboardingView: View {
    @Binding var isComplete: Bool

    @State private var micStatus: PermissionStatus = .unknown
    @State private var screenStatus: PermissionStatus = .unknown
    @State private var speechStatus: PermissionStatus = .unknown
    @State private var currentStep = 0

    enum PermissionStatus {
        case unknown, granted, denied
    }

    private let textPrimary = Color(red: 0.961, green: 0.961, blue: 0.969)
    private let textTertiary = Color(red: 0.557, green: 0.557, blue: 0.576)
    private let textQuaternary = Color(red: 0.388, green: 0.388, blue: 0.400)
    private let accentBlue = Color(red: 0.039, green: 0.518, blue: 1.0)
    private let accentGreen = Color(red: 0.188, green: 0.820, blue: 0.345)
    private let accentRed = Color(red: 1.0, green: 0.271, blue: 0.227)
    private let cardBackground = Color(red: 0.173, green: 0.173, blue: 0.180)
    private let borderColor = Color(red: 0.227, green: 0.227, blue: 0.235)

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Logo
                VStack(spacing: 12) {
                    HStack(spacing: 4) {
                        ForEach([16, 28, 40, 52, 40, 28, 16], id: \.self) { height in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(accentBlue)
                                .frame(width: 4, height: CGFloat(height))
                        }
                    }

                    Text("WhisprPro")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(textPrimary)
                        .tracking(-0.5)

                    Text("Transcribe audio locally with Whisper")
                        .font(.system(size: 14))
                        .foregroundStyle(textQuaternary)
                }

                // Permissions
                VStack(spacing: 12) {
                    Text("PERMISSIONS NEEDED")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(textQuaternary)
                        .kerning(0.55)

                    PermissionRow(
                        icon: "mic.fill",
                        title: "Microphone",
                        description: "Record audio for transcription",
                        status: micStatus,
                        color: accentRed,
                        action: requestMicrophone
                    )

                    PermissionRow(
                        icon: "rectangle.on.rectangle",
                        title: "Screen Recording",
                        description: "Capture system audio for meetings",
                        status: screenStatus,
                        color: .orange,
                        action: requestScreenRecording
                    )

                    PermissionRow(
                        icon: "waveform",
                        title: "Speech Recognition",
                        description: "Auto-detect speakers (optional)",
                        status: speechStatus,
                        color: accentBlue,
                        action: requestSpeechRecognition
                    )
                }
                .frame(maxWidth: 420)

                // Continue button
                Button {
                    isComplete = true
                    UserDefaults.standard.set(true, forKey: "onboardingComplete")
                } label: {
                    Text(allGranted ? "Get Started" : "Continue Anyway")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 200)
                        .padding(.vertical, 10)
                        .background(allGranted ? accentBlue : textQuaternary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                if !allGranted {
                    Text("You can grant permissions later in System Settings")
                        .font(.system(size: 11))
                        .foregroundStyle(textQuaternary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.110, green: 0.110, blue: 0.118))
        .onAppear {
            checkPermissions()
        }
    }

    private var allGranted: Bool {
        micStatus == .granted
    }

    private func checkPermissions() {
        // Microphone
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: micStatus = .granted
        case .denied, .restricted: micStatus = .denied
        default: micStatus = .unknown
        }

        // Speech
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speechStatus = .granted
        case .denied, .restricted: speechStatus = .denied
        default: speechStatus = .unknown
        }

        // Screen recording - can't check directly, assume unknown
        screenStatus = .unknown
    }

    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                micStatus = granted ? .granted : .denied
            }
        }
    }

    private func requestScreenRecording() {
        // Open System Settings to Screen Recording
        Task {
            // Trigger the permission dialog by attempting capture
            do {
                let content = try await SCShareableContent.current
                if content.displays.isEmpty {
                    screenStatus = .denied
                } else {
                    screenStatus = .granted
                }
            } catch {
                // Open System Settings
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
                screenStatus = .unknown
            }
        }
    }

    private func requestSpeechRecognition() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                speechStatus = status == .authorized ? .granted : .denied
            }
        }
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let status: OnboardingView.PermissionStatus
    let color: Color
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.12))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 0.961, green: 0.961, blue: 0.969))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.388, green: 0.388, blue: 0.400))
            }

            Spacer()

            switch status {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(red: 0.188, green: 0.820, blue: 0.345))
            case .denied:
                Button("Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(red: 0.220, green: 0.220, blue: 0.228))
                .cornerRadius(5)
            case .unknown:
                Button("Allow") {
                    action()
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(color)
                .cornerRadius(5)
            }
        }
        .padding(14)
        .background(Color(red: 0.173, green: 0.173, blue: 0.180))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.227, green: 0.227, blue: 0.235), lineWidth: 1)
        )
    }
}
