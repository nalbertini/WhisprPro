import SwiftUI
import AVFoundation
import ScreenCaptureKit

struct OnboardingView: View {
    @Binding var isComplete: Bool

    @State private var micStatus: PermissionStatus = .checking
    @State private var screenStatus: PermissionStatus = .checking

    enum PermissionStatus: Equatable {
        case checking, granted, denied, unknown
    }

    private let textPrimary = Color(red: 0.961, green: 0.961, blue: 0.969)
    private let textTertiary = Color(red: 0.557, green: 0.557, blue: 0.576)
    private let textQuaternary = Color(red: 0.388, green: 0.388, blue: 0.400)
    private let accentBlue = Color(red: 0.039, green: 0.518, blue: 1.0)
    private let accentGreen = Color(red: 0.188, green: 0.820, blue: 0.345)
    private let accentRed = Color(red: 1.0, green: 0.271, blue: 0.227)

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Logo
                VStack(spacing: 12) {
                    HStack(spacing: 4) {
                        ForEach(Array([16, 28, 40, 52, 40, 28, 16].enumerated()), id: \.offset) { _, height in
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
                        description: "Record your voice for transcription",
                        detail: "Used by Record, Meeting and Live Captions",
                        status: micStatus,
                        color: accentRed,
                        action: requestMicrophone
                    )

                    PermissionRow(
                        icon: "rectangle.on.rectangle",
                        title: "Screen Recording",
                        description: "Capture audio from other apps",
                        detail: "Used by Meeting and System Audio to record Zoom, Meet, Teams etc.",
                        status: screenStatus,
                        color: .orange,
                        action: requestScreenRecording
                    )
                }
                .frame(maxWidth: 420)

                // Status summary
                if micStatus == .granted && screenStatus == .granted {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(accentGreen)
                        Text("All permissions granted!")
                            .font(.system(size: 13))
                            .foregroundStyle(accentGreen)
                    }
                }

                // Continue button
                Button {
                    isComplete = true
                    UserDefaults.standard.set(true, forKey: "onboardingComplete")
                } label: {
                    Text(micStatus == .granted ? "Get Started" : "Continue Anyway")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 200)
                        .padding(.vertical, 10)
                        .background(micStatus == .granted ? accentBlue : textQuaternary)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                if micStatus != .granted {
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

    private func checkPermissions() {
        // Microphone
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: micStatus = .granted
        case .denied, .restricted: micStatus = .denied
        case .notDetermined: micStatus = .unknown
        @unknown default: micStatus = .unknown
        }

        // Screen Recording - try to get shareable content
        Task {
            do {
                let content = try await SCShareableContent.current
                await MainActor.run {
                    screenStatus = content.displays.isEmpty ? .denied : .granted
                }
            } catch {
                await MainActor.run {
                    screenStatus = .unknown
                }
            }
        }
    }

    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                micStatus = granted ? .granted : .denied
            }
        }
    }

    private func requestScreenRecording() {
        Task {
            do {
                let content = try await SCShareableContent.current
                await MainActor.run {
                    if content.displays.isEmpty {
                        screenStatus = .denied
                    } else {
                        screenStatus = .granted
                    }
                }
            } catch {
                await MainActor.run {
                    screenStatus = .denied
                    // Open System Settings
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    var detail: String = ""
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

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 0.961, green: 0.961, blue: 0.969))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.557, green: 0.557, blue: 0.576))
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 0.388, green: 0.388, blue: 0.400))
                }
            }

            Spacer()

            switch status {
            case .checking:
                ProgressView()
                    .scaleEffect(0.7)
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(red: 0.188, green: 0.820, blue: 0.345))
            case .denied:
                Button("Open Settings") {
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
    }
}
