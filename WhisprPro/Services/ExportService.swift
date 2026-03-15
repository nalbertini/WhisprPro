import Foundation
import AppKit
import PDFKit

struct ExportService {
    typealias ExportSegment = (start: TimeInterval, end: TimeInterval, text: String, speaker: String?)

    static func toSRT(segments: [ExportSegment]) -> String {
        var output = ""
        for (index, seg) in segments.enumerated() {
            output += "\(index + 1)\n"
            output += "\(srtTimestamp(seg.start)) --> \(srtTimestamp(seg.end))\n"
            if let speaker = seg.speaker {
                output += "[\(speaker)] "
            }
            output += "\(seg.text)\n\n"
        }
        return output
    }

    static func toVTT(segments: [ExportSegment]) -> String {
        var output = "WEBVTT\n\n"
        for (index, seg) in segments.enumerated() {
            output += "\(index + 1)\n"
            output += "\(vttTimestamp(seg.start)) --> \(vttTimestamp(seg.end))\n"
            if let speaker = seg.speaker {
                output += "<v \(speaker)>"
            }
            output += "\(seg.text)\n\n"
        }
        return output
    }

    static func toTXT(
        segments: [ExportSegment],
        includeSpeakers: Bool = true,
        includeTimestamps: Bool = true
    ) -> String {
        segments.map { seg in
            var line = ""
            if includeTimestamps {
                line += "[\(simpleTimestamp(seg.start))] "
            }
            if includeSpeakers, let speaker = seg.speaker {
                line += "\(speaker): "
            }
            line += seg.text
            return line
        }.joined(separator: "\n")
    }

    static func toJSON(
        title: String,
        language: String,
        segments: [ExportSegment]
    ) -> String {
        struct JSONOutput: Encodable {
            let title: String
            let language: String
            let segments: [JSONSegment]
        }
        struct JSONSegment: Encodable {
            let start: Double
            let end: Double
            let text: String
            let speaker: String?
        }

        let output = JSONOutput(
            title: title,
            language: language,
            segments: segments.map {
                JSONSegment(start: $0.start, end: $0.end, text: $0.text, speaker: $0.speaker)
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(output) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func toPDF(
        title: String,
        language: String,
        duration: TimeInterval,
        segments: [ExportSegment]
    ) -> Data? {
        let text = NSMutableAttributedString()

        // Title
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .paragraphStyle: {
                let p = NSMutableParagraphStyle()
                p.lineSpacing = 8
                return p
            }()
        ]
        text.append(NSAttributedString(string: "\(title)\n", attributes: titleAttr))

        // Metadata
        let metaAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let durationStr = "\(Int(duration) / 60):\(String(format: "%02d", Int(duration) % 60))"
        text.append(NSAttributedString(
            string: "Language: \(language) | Duration: \(durationStr)\n\n",
            attributes: metaAttr
        ))

        // Segments
        let bodyAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .paragraphStyle: {
                let p = NSMutableParagraphStyle()
                p.lineSpacing = 4
                p.paragraphSpacing = 8
                return p
            }()
        ]
        let speakerAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.controlAccentColor
        ]
        let timeAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]

        for seg in segments {
            text.append(NSAttributedString(string: simpleTimestamp(seg.start) + " ", attributes: timeAttr))
            if let speaker = seg.speaker {
                text.append(NSAttributedString(string: speaker + ": ", attributes: speakerAttr))
            }
            text.append(NSAttributedString(string: seg.text + "\n", attributes: bodyAttr))
        }

        // Generate PDF
        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 595, height: 842) // A4
        printInfo.topMargin = 50
        printInfo.bottomMargin = 50
        printInfo.leftMargin = 50
        printInfo.rightMargin = 50

        let textView = NSTextView(
            frame: NSRect(
                x: 0, y: 0,
                width: printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin,
                height: printInfo.paperSize.height - printInfo.topMargin - printInfo.bottomMargin
            )
        )
        textView.textStorage?.setAttributedString(text)

        return textView.dataWithPDF(inside: textView.bounds)
    }

    // MARK: - Helpers

    private static func srtTimestamp(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let millis = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }

    private static func vttTimestamp(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let millis = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, millis)
    }

    private static func simpleTimestamp(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
