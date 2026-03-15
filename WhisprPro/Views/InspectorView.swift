import SwiftUI
import AppKit

struct InspectorView: View {
    @Bindable var transcription: Transcription
    @State private var fontSize: Double = 15
    @State private var favoritesOnly = false
    @State private var compactMode = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Copy button
                Button {
                    copyTranscript()
                } label: {
                    Label("Copy Transcript", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Divider()

                // View options
                VStack(alignment: .leading, spacing: 12) {
                    Text("Display")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Font Size")
                        Spacer()
                        Picker("", selection: $fontSize) {
                            Text("13").tag(13.0)
                            Text("15").tag(15.0)
                            Text("18").tag(18.0)
                            Text("22").tag(22.0)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 70)
                    }

                    Toggle("Favorites Only", isOn: $favoritesOnly)
                    Toggle("Compact Mode", isOn: $compactMode)
                }

                Divider()

                // Speakers
                if transcription.status == .completed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("People")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        if transcription.speakers.isEmpty {
                            Text("No speakers detected")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(transcription.speakers) { speaker in
                                HStack {
                                    Circle()
                                        .fill(Color(hex: speaker.color) ?? .blue)
                                        .frame(width: 10, height: 10)
                                    Text(speaker.label)
                                        .font(.body)
                                    Spacer()
                                }
                            }
                        }
                    }

                    Divider()

                    // Actions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Actions")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Button("Remove Fillers") {
                            removeFillerWords()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Divider()

                    // Timestamp offset
                    HStack {
                        Text("Time Offset")
                            .font(.subheadline)
                        Spacer()
                        TextField("0", value: $transcription.timestampOffset, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .font(.caption)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .background(.bar)
    }

    private func copyTranscript() {
        let segments = transcription.segments.sorted { $0.startTime < $1.startTime }
        let text = segments.map { seg in
            var line = ""
            if let speaker = seg.speaker {
                line += "\(speaker.label): "
            }
            line += seg.text
            return line
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func removeFillerWords() {
        for segment in transcription.segments {
            let cleaned = FillerWordService.removeFillersFrom(segment.text)
            if cleaned != segment.text {
                segment.text = cleaned
                segment.isEdited = true
            }
        }
    }
}
