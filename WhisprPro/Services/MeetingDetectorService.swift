import Foundation
import AppKit
import os

private let logger = Logger(subsystem: "com.whisprpro", category: "MeetingDetector")

@Observable
final class MeetingDetectorService {
    var detectedMeeting: DetectedMeeting?
    var isMonitoring = false

    private var timer: Timer?
    private var dismissedMeetings: Set<String> = []

    struct DetectedMeeting: Equatable {
        let app: String
        let service: String
        let icon: String
        let detectedAt: Date

        var id: String { "\(service)-\(Int(detectedAt.timeIntervalSince1970 / 60))" }
    }

    // Known meeting apps and browser tab patterns
    private static let meetingApps: [(bundleId: String, name: String, icon: String)] = [
        ("us.zoom.xos", "Zoom", "video.fill"),
        ("com.microsoft.teams", "Microsoft Teams", "person.3.fill"),
        ("com.microsoft.teams2", "Microsoft Teams", "person.3.fill"),
        ("com.cisco.webexmeetingsapp", "Webex", "video.fill"),
        ("com.amazon.Amazon-Chime", "Amazon Chime", "phone.fill"),
        ("com.hnc.Discord", "Discord", "headphones"),
        ("com.skype.skype", "Skype", "phone.fill"),
        ("com.slack.Slack", "Slack Huddle", "headphones"),
    ]

    // Browser tab titles that indicate a meeting
    private static let meetingURLPatterns: [String] = [
        "meet.google.com",
        "zoom.us/j/",
        "zoom.us/wc/",
        "teams.microsoft.com",
        "teams.live.com",
        "webex.com/meet",
        "discord.com/channels",
    ]

    private static let meetingTitlePatterns: [String] = [
        "Google Meet",
        "Zoom Meeting",
        "Microsoft Teams",
        "Webex Meeting",
    ]

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        logger.info("Meeting detection started")

        // Check immediately
        checkForMeetings()

        // Then check every 10 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkForMeetings()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
        detectedMeeting = nil
        logger.info("Meeting detection stopped")
    }

    func dismissCurrentMeeting() {
        if let meeting = detectedMeeting {
            dismissedMeetings.insert(meeting.id)
        }
        detectedMeeting = nil
    }

    private func checkForMeetings() {
        // Check running apps
        let runningApps = NSWorkspace.shared.runningApplications

        for app in runningApps {
            guard let bundleId = app.bundleIdentifier else { continue }

            // Check known meeting apps
            if let meetingApp = Self.meetingApps.first(where: { $0.bundleId == bundleId }) {
                // Only detect if app is active (has audio session)
                if app.isActive || app.activationPolicy == .regular {
                    let meeting = DetectedMeeting(
                        app: meetingApp.name,
                        service: meetingApp.name,
                        icon: meetingApp.icon,
                        detectedAt: Date()
                    )
                    if !dismissedMeetings.contains(meeting.id) && detectedMeeting == nil {
                        detectedMeeting = meeting
                        logger.info("Meeting detected: \(meetingApp.name)")
                        return
                    }
                }
            }

            // Check browsers for meeting URLs
            if bundleId.contains("com.google.Chrome") ||
               bundleId.contains("com.apple.Safari") ||
               bundleId.contains("org.mozilla.firefox") ||
               bundleId.contains("com.brave.Browser") ||
               bundleId.contains("com.microsoft.edgemac") ||
               bundleId.contains("company.thebrowser.Browser") {  // Arc

                // Check window titles for meeting patterns
                if let appName = app.localizedName {
                    for pattern in Self.meetingTitlePatterns {
                        if checkBrowserWindowTitle(app: app, pattern: pattern) {
                            let meeting = DetectedMeeting(
                                app: appName,
                                service: pattern,
                                icon: "video.fill",
                                detectedAt: Date()
                            )
                            if !dismissedMeetings.contains(meeting.id) && detectedMeeting == nil {
                                detectedMeeting = meeting
                                logger.info("Browser meeting detected: \(pattern) in \(appName)")
                                return
                            }
                        }
                    }
                }
            }
        }
    }

    private func checkBrowserWindowTitle(app: NSRunningApplication, pattern: String) -> Bool {
        // Use Accessibility API to read window titles
        let pid = app.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)

        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue)

        guard result == .success, let windows = windowsValue as? [AXUIElement] else {
            return false
        }

        for window in windows {
            var titleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
               let title = titleValue as? String {
                if title.contains(pattern) {
                    return true
                }
            }
        }

        return false
    }
}
