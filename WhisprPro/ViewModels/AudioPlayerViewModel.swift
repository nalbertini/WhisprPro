import Foundation
import AVFoundation
import os

private let logger = Logger(subsystem: "com.whisprpro", category: "AudioPlayer")

@Observable
final class AudioPlayerViewModel {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var playbackRate: Float = 1.0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func loadAudio(url: URL) {
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.enableRate = true
            player?.prepareToPlay()
            duration = player?.duration ?? 0
        } catch {
            logger.error("Failed to load audio: \(error)")
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            stopTimer()
        } else {
            player.rate = playbackRate
            player.play()
            startTimer()
        }
        isPlaying = !isPlaying
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
    }

    func stop() {
        player?.stop()
        stopTimer()
        isPlaying = false
        currentTime = 0
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.currentTime = player.currentTime
            if !player.isPlaying {
                self.isPlaying = false
                self.stopTimer()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        stopTimer()
    }
}
