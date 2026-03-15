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

    static func toCSV(segments: [ExportSegment]) -> String {
        var output = "Start,End,Speaker,Text\n"
        for seg in segments {
            let text = seg.text.replacingOccurrences(of: "\"", with: "\"\"")
            let speaker = seg.speaker ?? ""
            output += "\"\(simpleTimestamp(seg.start))\",\"\(simpleTimestamp(seg.end))\",\"\(speaker)\",\"\(text)\"\n"
        }
        return output
    }

    static func toMarkdown(
        title: String,
        language: String,
        duration: TimeInterval,
        segments: [ExportSegment]
    ) -> String {
        let durationStr = "\(Int(duration) / 60):\(String(format: "%02d", Int(duration) % 60))"
        var output = "# \(title)\n\n"
        output += "**Language:** \(language) | **Duration:** \(durationStr)\n\n---\n\n"
        for seg in segments {
            if let speaker = seg.speaker {
                output += "**\(speaker)** _[\(simpleTimestamp(seg.start))]_\n\n"
            } else {
                output += "_[\(simpleTimestamp(seg.start))]_\n\n"
            }
            output += "\(seg.text)\n\n"
        }
        return output
    }

    static func toHTML(
        title: String,
        language: String,
        duration: TimeInterval,
        segments: [ExportSegment]
    ) -> String {
        let durationStr = "\(Int(duration) / 60):\(String(format: "%02d", Int(duration) % 60))"
        var output = """
        <!DOCTYPE html>
        <html lang="\(language)">
        <head>
        <meta charset="utf-8">
        <title>\(title)</title>
        <style>
        body { font-family: -apple-system, system-ui, sans-serif; max-width: 800px; margin: 40px auto; padding: 0 20px; color: #333; }
        h1 { margin-bottom: 4px; }
        .meta { color: #888; font-size: 14px; margin-bottom: 24px; }
        .segment { margin-bottom: 16px; }
        .speaker { font-weight: 600; color: #007AFF; }
        .timestamp { font-size: 12px; color: #aaa; font-variant-numeric: tabular-nums; }
        .text { margin-top: 2px; line-height: 1.6; }
        </style>
        </head>
        <body>
        <h1>\(title)</h1>
        <p class="meta">Language: \(language) | Duration: \(durationStr)</p>

        """
        for seg in segments {
            output += "<div class=\"segment\">\n"
            if let speaker = seg.speaker {
                output += "  <span class=\"speaker\">\(speaker)</span> "
            }
            output += "<span class=\"timestamp\">\(simpleTimestamp(seg.start))</span>\n"
            output += "  <p class=\"text\">\(seg.text)</p>\n"
            output += "</div>\n"
        }
        output += "</body>\n</html>"
        return output
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

    static func toDOCX(
        title: String,
        language: String,
        duration: TimeInterval,
        segments: [ExportSegment]
    ) -> Data? {
        let durationStr = "\(Int(duration) / 60):\(String(format: "%02d", Int(duration) % 60))"

        // Build document.xml content
        var paragraphs = ""

        // Title
        paragraphs += """
        <w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr>
        <w:r><w:rPr><w:b/><w:sz w:val="36"/></w:rPr>
        <w:t>\(escapeXML(title))</w:t></w:r></w:p>
        """

        // Metadata
        paragraphs += """
        <w:p><w:r><w:rPr><w:color w:val="888888"/><w:sz w:val="22"/></w:rPr>
        <w:t>Language: \(escapeXML(language)) | Duration: \(durationStr)</w:t></w:r></w:p>
        <w:p/>
        """

        // Segments
        for seg in segments {
            var run = ""
            if let speaker = seg.speaker {
                run += """
                <w:r><w:rPr><w:b/><w:color w:val="007AFF"/></w:rPr>
                <w:t xml:space="preserve">\(escapeXML(speaker)): </w:t></w:r>
                """
            }
            run += """
            <w:r><w:rPr><w:color w:val="999999"/><w:sz w:val="18"/></w:rPr>
            <w:t xml:space="preserve">[\(simpleTimestamp(seg.start))] </w:t></w:r>
            """
            run += """
            <w:r><w:t xml:space="preserve">\(escapeXML(seg.text))</w:t></w:r>
            """
            paragraphs += "<w:p>\(run)</w:p>\n"
        }

        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
        \(paragraphs)
        </w:body>
        </w:document>
        """

        let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """

        let relsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """

        // Create ZIP archive (DOCX is a ZIP file)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let wordDir = tempDir.appendingPathComponent("word")
        let relsDir = tempDir.appendingPathComponent("_rels")
        try? FileManager.default.createDirectory(at: wordDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)

        try? contentTypesXML.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        try? relsXML.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
        try? documentXML.write(to: wordDir.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)

        // Use NSFileCoordinator to create ZIP
        let coordinator = NSFileCoordinator()
        var zipData: Data?
        var error: NSError?

        coordinator.coordinate(readingItemAt: tempDir, options: .forUploading, error: &error) { zippedURL in
            zipData = try? Data(contentsOf: zippedURL)
        }

        try? FileManager.default.removeItem(at: tempDir)

        return zipData
    }

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
