import SwiftUI

struct EditorView: View {
    @Bindable var segment: Segment
    let isActive: Bool
    var searchText: String = ""
    var timestampOffset: TimeInterval = 0
    var compactMode: Bool = false
    var fontSize: Double = 15
    let onSeek: (TimeInterval) -> Void

    // Design tokens
    private let activeBackground = Color(.sRGB, red: 0.039, green: 0.518, blue: 1.0, opacity: 0.08)
    private let textPrimary = Color(red: 0.961, green: 0.961, blue: 0.969)      // #F5F5F7
    private let textSecondary = Color(red: 0.898, green: 0.898, blue: 0.918)   // #E5E5EA
    private let textTertiary = Color(red: 0.388, green: 0.388, blue: 0.400)    // #636366
    private let starFilled = Color(red: 1.0, green: 0.839, blue: 0.039)        // #FFD60A
    private let starEmpty = Color(red: 0.290, green: 0.290, blue: 0.306)       // #4A4A4E

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !compactMode {
                HStack(alignment: .center, spacing: 8) {
                    if let speaker = segment.speaker {
                        SpeakerLabelView(speaker: speaker)
                    }

                    Button {
                        onSeek(segment.startTime)
                    } label: {
                        Text(formatTimestamp(segment.startTime + timestampOffset))
                            .font(.custom("JetBrainsMono-Regular", size: 11).fallback(size: 11, design: .monospaced))
                            .foregroundStyle(textTertiary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .buttonStyle(.plain)

                    if segment.isEdited {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundStyle(textTertiary)
                    }

                    Spacer()

                    Button {
                        segment.isStarred.toggle()
                    } label: {
                        Image(systemName: segment.isStarred ? "star.fill" : "star")
                            .foregroundStyle(segment.isStarred ? starFilled : starEmpty)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }

            if searchText.isEmpty {
                TextField("", text: $segment.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: fontSize))
                    .foregroundStyle(isActive ? textPrimary : textSecondary)
                    .lineSpacing(fontSize * 0.5 - fontSize * 0.1)
                    .onChange(of: segment.text) {
                        segment.isEdited = true
                    }
            } else {
                highlightedText(segment.text, highlight: searchText)
                    .font(.system(size: fontSize))
                    .foregroundStyle(isActive ? textPrimary : textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? activeBackground : .clear)
        .cornerRadius(8)
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
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color(hex: speaker.color) ?? .primary)
            .frame(width: 100)
        } else {
            Text(speaker.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: speaker.color) ?? .primary)
                .onTapGesture {
                    editText = speaker.label
                    isEditing = true
                }
        }
    }
}

// MARK: - Font fallback helper

private extension Font {
    func fallback(size: CGFloat, design: Font.Design) -> Font {
        return self
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
