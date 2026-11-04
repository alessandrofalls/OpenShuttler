import AppKit
import OSLog

enum Log {
    private static let subsystem = "io.github.openshuttler"
    static let config = Logger(subsystem: subsystem, category: "config")
    static let launch = Logger(subsystem: subsystem, category: "launch")
}

@MainActor
enum Alerts {
    static func show(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

