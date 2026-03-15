import SwiftUI

struct AudioPlayerView: View {
    @Bindable var viewModel: AudioPlayerViewModel

    var body: some View {
        HStack(spacing: 12) {
            Button(action: viewModel.togglePlayback) {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)

            Slider(
                value: Binding(
                    get: { viewModel.currentTime },
                    set: { viewModel.seek(to: $0) }
                ),
                in: 0...max(viewModel.duration, 0.01)
            )

            Text("\(formatTime(viewModel.currentTime)) / \(formatTime(viewModel.duration))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 100)

            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0], id: \.self) { rate in
                    Button("\(rate, specifier: "%.2g")x") {
                        viewModel.setRate(Float(rate))
                    }
                }
            } label: {
                Text("\(viewModel.playbackRate, specifier: "%.2g")x")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding()
        .background(.bar)
        .cornerRadius(8)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
