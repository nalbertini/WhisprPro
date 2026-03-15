import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let url: URL
    @Bindable var playerViewModel: AudioPlayerViewModel
    let subtitles: [(start: TimeInterval, end: TimeInterval, text: String)]

    @State private var avPlayer: AVPlayer?
    @State private var currentSubtitle = ""

    var body: some View {
        VStack(spacing: 0) {
            // Video
            VideoPlayer(player: avPlayer)
                .frame(minHeight: 200, maxHeight: 350)
                .onAppear {
                    let player = AVPlayer(url: url)
                    avPlayer = player
                    startSubtitleSync()
                }
                .onDisappear {
                    avPlayer?.pause()
                }

            // Subtitle overlay bar
            if !currentSubtitle.isEmpty {
                Text(currentSubtitle)
                    .font(.system(size: 15))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.7))
                    .foregroundStyle(.white)
            }

            // Controls
            HStack(spacing: 12) {
                Button {
                    if avPlayer?.rate == 0 {
                        avPlayer?.play()
                    } else {
                        avPlayer?.pause()
                    }
                } label: {
                    Image(systemName: avPlayer?.rate == 0 ? "play.fill" : "pause.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)

                if let duration = avPlayer?.currentItem?.duration.seconds, duration.isFinite {
                    Text(formatTime(avPlayer?.currentTime().seconds ?? 0))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text("/ \(formatTime(duration))")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0], id: \.self) { rate in
                        Button("\(rate, specifier: "%.2g")x") {
                            avPlayer?.rate = Float(rate)
                        }
                    }
                } label: {
                    Text("1x")
                        .font(.system(size: 12))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary)
                        .cornerRadius(4)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func startSubtitleSync() {
        // Use a periodic time observer to update subtitles
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        avPlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let seconds = time.seconds
            if let sub = subtitles.first(where: { seconds >= $0.start && seconds < $0.end }) {
                currentSubtitle = sub.text
            } else {
                currentSubtitle = ""
            }
            // Sync with AudioPlayerViewModel for segment highlighting
            playerViewModel.currentTime = seconds
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "00:00" }
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
