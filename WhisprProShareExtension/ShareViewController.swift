import Cocoa
import UniformTypeIdentifiers

class ShareViewController: NSViewController {

    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        handleSharedItems()
    }

    private func handleSharedItems() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            close()
            return
        }

        let supportedTypes: [UTType] = [.audio, .movie, .mpeg4Audio, .wav, .mp3, .aiff]

        for attachment in attachments {
            // Check for file URL
            if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] item, error in
                    guard let url = item as? URL ?? (item as? Data).flatMap({ URL(dataRepresentation: $0, relativeTo: nil) }) else {
                        self?.close()
                        return
                    }
                    self?.sendToWhisprPro(fileURL: url)
                }
                return
            }

            // Check for audio/video types
            for type in supportedTypes {
                if attachment.hasItemConformingToTypeIdentifier(type.identifier) {
                    attachment.loadItem(forTypeIdentifier: type.identifier) { [weak self] item, error in
                        if let url = item as? URL {
                            self?.sendToWhisprPro(fileURL: url)
                        } else {
                            self?.close()
                        }
                    }
                    return
                }
            }
        }

        close()
    }

    private func sendToWhisprPro(fileURL: URL) {
        // Copy file to shared App Group container
        let sharedDir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.whisprpro"
        )?.appendingPathComponent("SharedFiles")

        if let sharedDir {
            try? FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)

            let destURL = sharedDir.appendingPathComponent(fileURL.lastPathComponent)
            try? FileManager.default.removeItem(at: destURL)
            try? FileManager.default.copyItem(at: fileURL, to: destURL)

            // Write a marker file that the main app will pick up
            let markerURL = sharedDir.appendingPathComponent(".pending-import")
            try? destURL.path.write(to: markerURL, atomically: true, encoding: .utf8)
        }

        // Open WhisprPro via URL scheme
        let encodedPath = fileURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let appURL = URL(string: "whisprpro://import?file=\(encodedPath)") {
            NSWorkspace.shared.open(appURL)
        }

        // Close the extension
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.close()
        }
    }

    private func close() {
        DispatchQueue.main.async { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
