import Foundation

/// Safe quoting for POSIX shells (single quotes).
public enum Shell {
    private static let safe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")

    public static func quote(_ s: String) -> String {
        if !s.isEmpty, s.allSatisfy({ safe.contains($0) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Splits a command line into words respecting single/double quotes. Returns nil if quotes are unbalanced.
    static func split(_ line: String) -> [String]? {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        for ch in line {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "'" || ch == "\"" {
                quote = ch
                inWord = true
            } else if ch == " " || ch == "\t" {
                if inWord { words.append(current); current = ""; inWord = false }
            } else {
                current.append(ch)
                inWord = true
            }
        }
        if quote != nil { return nil }
        if inWord { words.append(current) }
        return words
    }
}

/// Plan describing how the app should open a connection. Pure and testable; actual execution stays in the app layer.
public enum LaunchPlan: Equatable, Sendable {
    /// Open an `ssh://` URL (macOS hands off to the default terminal).
    case openURL(URL)
    /// Contents of a temporary `.command` script to execute in terminal.
    case script(String)
    /// AppleScript to control active terminal window or open a tab/window in Terminal or iTerm.
    case appleScript(String)
}

public enum LaunchPlanner {
    public static func plan(
        for server: Server,
        terminalApp: String?,
        openIn: String = "tab",
        homeDirectory: String = NSHomeDirectory()
    ) -> LaunchPlan {
        let command = commandString(for: server, homeDirectory: homeDirectory)

        switch openIn.lowercased() {
        case "current", "tab":
            // Interactive mode: injects into active window or new tab via AppleScript
            let script = appleScript(
                terminalApp: terminalApp,
                command: command,
                mode: openIn.lowercased(),
                title: server.name
            )
            return .appleScript(script)

        default: // "new"
            // Dedicated new window mode
            if terminalApp == nil, case .ssh(let target) = server.kind, let url = sshURL(for: target) {
                return .openURL(url)
            }
            let line: String
            switch server.kind {
            case .shell:
                line = command
            case .ssh:
                line = "exec " + command
            }
            return .script(script(title: server.name, command: line))
        }
    }

    public static func commandString(for server: Server, homeDirectory: String = NSHomeDirectory()) -> String {
        switch server.kind {
        case .shell(let command):
            return command
        case .ssh(let target):
            return sshCommandLine(for: target, homeDirectory: homeDirectory)
        }
    }

    public static func appleScript(
        terminalApp: String?,
        command: String,
        mode: String,
        title: String? = nil
    ) -> String {
        let terminal = (terminalApp ?? "Terminal").lowercased()
        if terminal.contains("iterm") {
            return iTermScript(cmd: command, mode: mode, title: title)
        } else {
            return terminalAppScript(cmd: command, mode: mode, title: title)
        }
    }

    private static func terminalAppScript(cmd: String, mode: String, title: String?) -> String {
        let c = esc(cmd)
        var lines: [String] = ["tell application \"Terminal\"", "activate"]

        if mode == "tab" {
            lines.append("""
            if (count of windows) is 0 then
                set t to do script "\(c)"
            else
                tell application "System Events" to keystroke "t" using command down
                delay 0.2
                set t to do script "\(c)" in selected tab of front window
            end if
            """)
        } else { // "current"
            lines.append("""
            if (count of windows) is 0 then
                set t to do script "\(c)"
            else
                set t to do script "\(c)" in selected tab of front window
            end if
            """)
        }

        if let title = title {
            lines.append("try\nset custom title of t to \"\(esc(title))\"\nend try")
        }
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    private static func iTermScript(cmd: String, mode: String, title: String?) -> String {
        let c = esc(cmd)
        var body: String

        if mode == "tab" {
            body = """
            if (count of windows) is 0 then
                create window with default profile
            else
                tell current window to create tab with default profile
            end if
            set s to current session of current window
            """
        } else { // "current"
            body = """
            if (count of windows) is 0 then
                create window with default profile
            end if
            set s to current session of current window
            """
        }

        var extra = ""
        if let title = title {
            extra = "\ntry\nset name of s to \"\(esc(title))\"\nend try"
        }

        return """
        tell application "iTerm"
            activate
            \(body)
            tell s to write text "\(c)"\(extra)
        end tell
        """
    }

    static func sshURL(for target: SSHTarget) -> URL? {
        guard target.identityFile == nil, target.jumpHost == nil,
              Validation.isSimpleHostname(target.host) else { return nil }
        var components = URLComponents()
        components.scheme = "ssh"
        components.user = target.user
        components.host = target.host
        components.port = target.port
        return components.url
    }

    static func sshCommandLine(for target: SSHTarget, homeDirectory: String) -> String {
        var args = ["ssh"]
        if let port = target.port { args += ["-p", String(port)] }
        if let identity = target.identityFile {
            args += ["-i", expandTilde(identity, home: homeDirectory)]
        }
        if let jump = target.jumpHost { args += ["-J", jump] }
        args += ["--", target.user.map { "\($0)@\(target.host)" } ?? target.host]
        return args.map(Shell.quote).joined(separator: " ")
    }

    public static func script(title: String, command: String) -> String {
        let safeTitle = String(String.UnicodeScalarView(
            title.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        ))
        return """
        #!/bin/zsh
        rm -f -- "$0"
        printf '\\033]0;%s\\007' \(Shell.quote(safeTitle))
        \(command)

        """
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func expandTilde(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + String(path.dropFirst(1)) }
        return path
    }
}
