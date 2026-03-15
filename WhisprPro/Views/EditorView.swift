import SwiftUI

struct EditorView: View {
    @Bindable var segment: Segment
    let isActive: Bool
    var searchText: String = ""
    var timestampOffset: TimeInterval = 0
    var compactMode: Bool = false
    var fontSize: Double = 15
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !compactMode {
                HStack {
                    if let speaker = segment.speaker {
                        SpeakerLabelView(speaker: speaker)
                    }

                    Button {
                        onSeek(segment.startTime)
                    } label: {
                        Text(formatTimestamp(segment.startTime + timestampOffset))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    if segment.isEdited {
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        segment.isStarred.toggle()
                    } label: {
                        Image(systemName: segment.isStarred ? "star.fill" : "star")
                            .foregroundStyle(segment.isStarred ? .yellow : .secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            if searchText.isEmpty {
                TextField("", text: $segment.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: fontSize))
                    .onChange(of: segment.text) {
                        segment.isEdited = true
                    }
            } else {
                highlightedText(segment.text, highlight: searchText)
                    .font(.system(size: fontSize))
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

    private func highlightedText(_ text: String, highlight: String) -> Text {
        guard !highlight.isEmpty else { return Text(text) }

        let lowercasedText = text.lowercased()
        let lowercasedHighlight = highlight.lowercased()

        var result = Text("")
        var searchRange = lowercasedText.startIndex..<lowercasedText.endIndex

        while let range = lowercasedText.range(of: lowercasedHighlight, range: searchRange) {
            let before = text[searchRange.lowerBound..<range.lowerBound]
            let match = text[range]

            result = result + Text(before) + Text(match).bold().foregroundColor(.yellow)
            searchRange = range.upperBound..<lowercasedText.endIndex
        }

        let remaining = text[searchRange.lowerBound...]
        result = result + Text(remaining)

        return result
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
    var hexString: String {
        let nsColor = NSColor(self)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return "#007AFF" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

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
