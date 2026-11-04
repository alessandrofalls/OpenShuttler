import Foundation

/// Converts legacy `~/.shuttle.json` to the current format (one-time migration).
public enum LegacyShuttleImporter {
    public struct Output: Sendable {
        public var config: AppConfig
        public var issues: [ConfigIssue]
    }

    public static func importConfig(from data: Data) throws -> Output {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError("Shuttle root JSON must be an object")
        }
        var issues: [ConfigIssue] = []
        var config = AppConfig()

        var options = SSHConfigOptions()
        options.enabled = (root["show_ssh_config_hosts"] as? Bool) ?? false
        options.ignoreHosts = root["ssh_config_ignore_hosts"] as? [String] ?? []
        options.ignoreKeywords = root["ssh_config_ignore_keywords"] as? [String] ?? []
        config.sshConfigHosts = options

        if let terminal = root["terminal"] as? String, terminal.lowercased().contains("iterm") {
            config.terminalApp = "iTerm"
        }
        if let editor = root["editor"] as? String, editor != "default", !editor.isEmpty {
            config.editor = editor
        }
        config.entries = entries(from: root["hosts"] as? [Any] ?? [], issues: &issues)
        return Output(config: config, issues: issues)
    }

    private static func entries(from items: [Any], issues: inout [ConfigIssue]) -> [MenuEntry] {
        var result: [MenuEntry] = []
        for item in items {
            guard let dict = item as? [String: Any] else { continue }

            if let cmd = dict["cmd"] as? String {
                let name = ((dict["name"] as? String) ?? cmd).trimmingCharacters(in: .whitespacesAndNewlines)
                if name == "-" { result.append(.separator); continue }
                guard !cmd.trimmingCharacters(in: .whitespaces).isEmpty, !name.isEmpty else {
                    issues.append(ConfigIssue("Import: entry with empty name or command ignored"))
                    continue
                }
                if let target = sshTarget(fromCommand: cmd) {
                    result.append(.server(Server(name: name, kind: .ssh(target))))
                } else {
                    result.append(.server(Server(name: name, kind: .shell(cmd))))
                }
                continue
            }

            // Folder: { "Name": [ ... ] }
            for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
                if let children = value as? [Any] {
                    result.append(.folder(name: key, items: entries(from: children, issues: &issues)))
                }
            }
        }
        return result
    }

    private static let shellMetacharacters = CharacterSet(charactersIn: ";|&<>`$()\\\n")

    /// Converts `ssh [-p N] [-l user] [-i key] [-J jump] [user@]host` to a structured target.
    static func sshTarget(fromCommand cmd: String) -> SSHTarget? {
        guard cmd.rangeOfCharacter(from: shellMetacharacters) == nil,
              let words = Shell.split(cmd), words.first == "ssh" else { return nil }

        var port: Int?
        var user: String?
        var identity: String?
        var jump: String?
        var positional: [String] = []

        var i = 1
        while i < words.count {
            let word = words[i]
            switch word {
            case "-p":
                guard i + 1 < words.count, let value = Int(words[i + 1]) else { return nil }
                port = value; i += 2
            case "-l":
                guard i + 1 < words.count else { return nil }
                user = words[i + 1]; i += 2
            case "-i":
                guard i + 1 < words.count else { return nil }
                identity = words[i + 1]; i += 2
            case "-J":
                guard i + 1 < words.count else { return nil }
                jump = words[i + 1]; i += 2
            default:
                if word.hasPrefix("-") { return nil }
                positional.append(word); i += 1
            }
        }
        guard positional.count == 1 else { return nil }

        var host = positional[0]
        if let at = host.lastIndex(of: "@") {
            let embedded = String(host[..<at])
            host = String(host[host.index(after: at)...])
            if let user, user != embedded { return nil }
            user = embedded
        }
        return try? SSHTarget(host: host, user: user, port: port, identityFile: identity, jumpHost: jump)
    }
}
