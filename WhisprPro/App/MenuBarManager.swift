import SwiftUI
import AppKit
import os

private let logger = Logger(subsystem: "com.whisprpro", category: "MenuBar")

final class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func setup() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "WhisprPro")
            button.image?.size = NSSize(width: 16, height: 16)
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        self.statusItem = statusItem

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 380)
        popover.behavior = .transient
        popover.animates = true
        self.popover = popover
    }

    func setContentView(_ view: some View) {
        popover?.contentViewController = NSHostingController(rootView: view)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }

        if let popover, popover.isShown {
            popover.performClose(sender)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover?.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover() {
        popover?.performClose(nil)
    }
}
