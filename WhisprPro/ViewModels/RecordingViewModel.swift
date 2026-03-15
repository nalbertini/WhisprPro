import Foundation
import AVFoundation

@Observable
final class RecordingViewModel {
    let recordingService = RecordingService()
    var selectedDeviceID: String?
    var errorMessage: String?

    var availableDevices: [AVCaptureDevice] {
        recordingService.availableInputDevices()
    }

    func startRecording() {
        do {
            try recordingService.startRecording(deviceID: selectedDeviceID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopAndGetFile() -> URL? {
        do {
            return try recordingService.stopRecording()
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
