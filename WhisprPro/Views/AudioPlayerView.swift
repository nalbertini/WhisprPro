import SwiftUI

struct AudioPlayerView: View {
    @Bindable var viewModel: AudioPlayerViewModel

    // Design tokens
    private let trackColor = Color(red: 0.227, green: 0.227, blue: 0.235)    // #3A3A3C
    private let accentBlue = Color(red: 0.039, green: 0.518, blue: 1.0)       // #0A84FF
    private let timeColor = Color(red: 0.557, green: 0.557, blue: 0.576)      // #8E8E93
    private let pillBackground = Color(red: 0.220, green: 0.220, blue: 0.228) // #38383A
    private let playButtonColor = Color(red: 0.961, green: 0.961, blue: 0.969) // #F5F5F7

    var body: some View {
        HStack(spacing: 16) {
            Button(action: viewModel.togglePlayback) {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(playButtonColor)
            }
            .buttonStyle(.plain)

            // Custom progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(trackColor)
                        .frame(height: 4)

                    // Filled portion
                    let progress = viewModel.duration > 0 ? viewModel.currentTime / viewModel.duration : 0
                    Capsule()
                        .fill(accentBlue)
                        .frame(width: geo.size.width * CGFloat(progress), height: 4)
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let ratio = value.location.x / geo.size.width
                            let clamped = max(0, min(1, ratio))
                            viewModel.seek(to: clamped * viewModel.duration)
                        }
                )
            }
            .frame(height: 20)

            Text("\(formatTime(viewModel.currentTime)) / \(formatTime(viewModel.duration))")
                .font(.custom("JetBrainsMono-Regular", size: 12).fallback(size: 12))
                .foregroundStyle(timeColor)
                .frame(width: 110)

            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0], id: \.self) { rate in
                    Button("\(rate, specifier: "%.2g")x") {
                        viewModel.setRate(Float(rate))
                    }
                }
            } label: {
                Text("\(viewModel.playbackRate, specifier: "%.2g")x")
                    .font(.custom("JetBrainsMono-Regular", size: 11).fallback(size: 11))
                    .foregroundStyle(timeColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(pillBackground)
                    .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.137, green: 0.137, blue: 0.145)) // #232325
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Font fallback helper

private extension Font {
    func fallback(size: CGFloat) -> Font {
        return self
    }
}
