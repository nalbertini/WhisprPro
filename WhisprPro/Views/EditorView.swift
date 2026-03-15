import SwiftUI

struct EditorView: View {
    @Bindable var segment: Segment
    let isActive: Bool
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let speaker = segment.speaker {
                    SpeakerLabelView(speaker: speaker)
                }

                Button {
                    onSeek(segment.startTime)
                } label: {
                    Text(formatTimestamp(segment.startTime))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if segment.isEdited {
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("", text: $segment.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .onChange(of: segment.text) {
                    segment.isEdited = true
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? Color.accentColor.opacity(0.1) : .clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            onSeek(segment.startTime)
        }
    }

    private func formatTimestamp(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct SpeakerLabelView: View {
    @Bindable var speaker: Speaker
    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        if isEditing {
            TextField("Name", text: $editText)
                .onSubmit {
                    speaker.label = editText
                    isEditing = false
                }
            .textFieldStyle(.plain)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Color(hex: speaker.color) ?? .primary)
            .frame(width: 100)
        } else {
            Text(speaker.label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color(hex: speaker.color) ?? .primary)
                .onTapGesture {
                    editText = speaker.label
                    isEditing = true
                }
        }
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6,
              let rgb = UInt64(hexSanitized, radix: 16) else {
            return nil
        }

        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }
}
