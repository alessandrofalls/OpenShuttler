import AppKit
import ShutterCore

/// Executes a `LaunchPlan`. Supports AppleScript for tabs/windows, direct URLs, and shell scripts.
@MainActor
enum Launcher {
    private static let scriptDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("openshuttler", isDirectory: true)

    static func launch(_ server: Server, terminalApp: String?, openIn: String = "new") {
        switch LaunchPlanner.plan(for: server, terminalApp: terminalApp, openIn: openIn) {
        case .appleScript(let source):
            runAppleScript(source, failureTitle: "Unable to launch \"\(server.name)\"") {
                // If AppleScript fails (e.g. System Events keystrokes denied/not allowed),
                // gracefully fall back to opening a dedicated window without showing an error popup!
                Log.launch.warning("AppleScript failed or denied; falling back to direct window launch for \(server.name)")
                launchDirectly(server, terminalApp: terminalApp)
            }

        case .openURL(let url):
            Log.launch.info("Opening \(url.absoluteString, privacy: .private)")
            if !NSWorkspace.shared.open(url) {
                Alerts.show(
                    title: "Unable to launch \"\(server.name)\"",
                    message: "No application responded to ssh:// scheme. Set a default terminal or specify 'terminalApp' in preferences."
                )
            }
        case .script(let contents):
            launchScript(contents, terminalApp: terminalApp, failureTitle: "Unable to launch \"\(server.name)\"")
        }
    }

    private static func launchDirectly(_ server: Server, terminalApp: String?) {
        let command = LaunchPlanner.commandString(for: server)
        let line: String
        switch server.kind {
        case .shell:
            line = command
        case .ssh:
            line = "exec " + command
        }
        let scriptContent = LaunchPlanner.script(title: server.name, command: line)
        launchScript(scriptContent, terminalApp: terminalApp, failureTitle: "Unable to launch \"\(server.name)\"")
    }

    private static func launchScript(_ contents: String, terminalApp: String?, failureTitle: String) {
        do {
            let file = try writeScript(contents)
            open(["-a", terminalApp ?? "Terminal", file.path], failureTitle: failureTitle)
        } catch {
            Log.launch.error("Failed to create script: \(error.localizedDescription)")
            Alerts.show(title: failureTitle, message: error.localizedDescription)
        }
    }

    /// Executes an AppleScript via /usr/bin/osascript asynchronously.
    static func runAppleScript(
        _ source: String,
        failureTitle: String,
        fallback: (@MainActor () -> Void)? = nil
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.terminationHandler = { finished in
            guard finished.terminationStatus != 0 else { return }
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Task { @MainActor in
                Log.launch.error("osascript failed: \(text)")
                if let fallback {
                    fallback()
                } else {
                    Alerts.show(
                        title: failureTitle,
                        message: text.isEmpty ? "Failed to execute terminal script." : text
                    )
                }
            }
        }
        do {
            try process.run()
        } catch {
            if let fallback {
                fallback()
            } else {
                Alerts.show(title: failureTitle, message: error.localizedDescription)
            }
        }
    }

    /// Opens the editor for configuration.
    /// Supports CLI editors (vim, nano, etc.) directly in terminal, GUI apps (open -a),
    /// and safely falls back to system text editor (open -t) if the app is missing.
    static func openEditor(path: String, editor: String?, terminalApp: String?) {
        let cleanEditor = editor?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let cleanEditor, !cleanEditor.isEmpty, cleanEditor.lowercased() != "default" else {
            open(["-t", path], failureTitle: "Unable to open default text editor")
            return
        }

        let cliEditors: Set<String> = [
            "vim", "vi", "nvim", "nano", "pico", "emacs", "micro", "helix", "kak"
        ]

        if cliEditors.contains(cleanEditor.lowercased()) {
            let command = "exec \(cleanEditor) \(Shell.quote(path))"
            let scriptContent = LaunchPlanner.script(title: "Config (\(cleanEditor))", command: command)
            do {
                let file = try writeScript(scriptContent)
                open(["-a", terminalApp ?? "Terminal", file.path], failureTitle: "Unable to open \(cleanEditor)")
            } catch {
                Alerts.show(title: "Unable to open editor", message: error.localizedDescription)
            }
            return
        }

        // Try GUI app (e.g. "Visual Studio Code", "TextEdit").
        // If not found, safely fallback to system text editor.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", cleanEditor, path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.terminationHandler = { finished in
            guard finished.terminationStatus != 0 else { return }
            Task { @MainActor in
                Log.launch.warning("Editor '\(cleanEditor)' not found; opening in default text editor...")
                open(["-t", path], failureTitle: "Unable to open editor")
            }
        }
        do {
            try process.run()
        } catch {
            open(["-t", path], failureTitle: "Unable to open editor")
        }
    }

    /// Runs `/usr/bin/open` and warns the user upon failure.
    static func open(_ arguments: [String], failureTitle: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.terminationHandler = { finished in
            guard finished.terminationStatus != 0 else { return }
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Task { @MainActor in
                Log.launch.error("open failed: \(text)")
                Alerts.show(title: failureTitle, message: text.isEmpty ? "The 'open' command failed." : text)
            }
        }
        do {
            try process.run()
        } catch {
            Alerts.show(title: failureTitle, message: error.localizedDescription)
        }
    }

    // MARK: - Temporary Scripts

    private static func writeScript(_ contents: String) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: scriptDirectory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let url = scriptDirectory.appendingPathComponent("\(UUID().uuidString).command")
        guard fm.createFile(atPath: url.path, contents: Data(contents.utf8),
                            attributes: [.posixPermissions: 0o700]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    /// Cleans up leftover script files.
    static func cleanUpStaleScripts(olderThan age: TimeInterval = 3600) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: scriptDirectory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for file in files where file.pathExtension == "command" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, Date().timeIntervalSince(modified) > age {
                try? fm.removeItem(at: file)
            }
        }
    }
}
