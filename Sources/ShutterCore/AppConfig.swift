import Foundation

/// A menu entry: server, folder (submenu), or separator.
public indirect enum MenuEntry: Equatable, Sendable {
    case server(Server)
    case folder(name: String, items: [MenuEntry])
    case separator
}

extension MenuEntry: Codable {
    private enum Keys: String, CodingKey { case folder, items, separator }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if (try? c.decode(Bool.self, forKey: .separator)) == true {
            self = .separator
        } else if c.contains(.folder) {
            let name = try c.decode(String.self, forKey: .folder)
            var items: [MenuEntry] = []
            if c.contains(.items) {
                var list = try c.nestedUnkeyedContainer(forKey: .items)
                items = list.decodeLossy(
                    MenuEntry.self,
                    label: "folder '\(name)'",
                    collector: decoder.userInfo[.issueCollector] as? IssueCollector
                )
            }
            self = .folder(name: name, items: items)
        } else {
            self = .server(try Server(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .server(let server):
            try server.encode(to: encoder)
        case .folder(let name, let items):
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(name, forKey: .folder)
            try c.encode(items, forKey: .items)
        case .separator:
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(true, forKey: .separator)
        }
    }
}

public struct SSHConfigOptions: Equatable, Sendable, Codable {
    public var enabled: Bool
    public var ignoreHosts: [String]
    public var ignoreKeywords: [String]

    public init(enabled: Bool = true, ignoreHosts: [String] = [], ignoreKeywords: [String] = []) {
        self.enabled = enabled
        self.ignoreHosts = ignoreHosts
        self.ignoreKeywords = ignoreKeywords
    }

    private enum Keys: String, CodingKey { case enabled, ignoreHosts, ignoreKeywords }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true,
            ignoreHosts: try c.decodeIfPresent([String].self, forKey: .ignoreHosts) ?? [],
            ignoreKeywords: try c.decodeIfPresent([String].self, forKey: .ignoreKeywords) ?? []
        )
    }
}

/// Application preferences (`~/.config/openshuttler/config.json`).
public struct AppConfig: Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// Load hosts from `~/.ssh/config`.
    public var sshConfigHosts: SSHConfigOptions
    /// Terminal launch mode: "tab" (new tab), "current" (active tab), "new" (new window).
    public var openIn: String
    /// Terminal app to use: "Terminal" or "iTerm". If nil, uses default system terminal.
    public var terminalApp: String?
    /// Preferred editor for "Edit..." menus (e.g. "vim", "nano", "code").
    public var editor: String?
    public var entries: [MenuEntry]

    public init(
        version: Int = AppConfig.currentVersion,
        sshConfigHosts: SSHConfigOptions = .init(),
        openIn: String = "tab",
        terminalApp: String? = nil,
        editor: String? = nil,
        entries: [MenuEntry] = []
    ) {
        self.version = version
        self.sshConfigHosts = sshConfigHosts
        self.openIn = openIn
        self.terminalApp = terminalApp
        self.editor = editor
        self.entries = entries
    }

    /// Sample configuration created on first launch.
    public static var sample: AppConfig {
        func server(_ name: String, host: String, user: String, port: Int? = nil) -> MenuEntry {
            .server(Server(name: name, kind: .ssh(try! SSHTarget(host: host, user: user, port: port))))
        }
        return AppConfig(entries: [
            server("Example", host: "example.com", user: "user"),
            .folder(name: "My Servers", items: [
                server("Server 1", host: "server1.example.com", user: "user"),
                server("Server 2", host: "server2.example.com", user: "user", port: 2222)
            ])
        ])
    }
}

extension AppConfig: Codable {
    private enum Keys: String, CodingKey {
        case version, sshConfigHosts, openIn, terminalApp, editor, servers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .version) ?? AppConfig.currentVersion
        guard version <= AppConfig.currentVersion else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "config version \(version) is newer than supported (\(AppConfig.currentVersion))"
            ))
        }
        var entries: [MenuEntry] = []
        if c.contains(.servers) {
            var list = try c.nestedUnkeyedContainer(forKey: .servers)
            entries = list.decodeLossy(
                MenuEntry.self,
                label: "servers",
                collector: decoder.userInfo[.issueCollector] as? IssueCollector
            )
        }
        self.init(
            version: version,
            sshConfigHosts: try c.decodeIfPresent(SSHConfigOptions.self, forKey: .sshConfigHosts) ?? .init(),
            openIn: try c.decodeIfPresent(String.self, forKey: .openIn) ?? "tab",
            terminalApp: try c.decodeIfPresent(String.self, forKey: .terminalApp),
            editor: try c.decodeIfPresent(String.self, forKey: .editor),
            entries: entries
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(version, forKey: .version)
        try c.encode(sshConfigHosts, forKey: .sshConfigHosts)
        try c.encode(openIn, forKey: .openIn)
        try c.encodeIfPresent(terminalApp, forKey: .terminalApp)
        try c.encodeIfPresent(editor, forKey: .editor)
        try c.encode(entries, forKey: .servers)
    }
}

/// Unified serialization codec.
public enum ConfigCodec {
    public static func decode(_ data: Data) throws -> (config: AppConfig, issues: [ConfigIssue]) {
        let collector = IssueCollector()
        let decoder = JSONDecoder()
        decoder.userInfo[.issueCollector] = collector
        let config = try decoder.decode(AppConfig.self, from: data)
        return (config, collector.issues)
    }

    public static func encode(_ config: AppConfig) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(config)
    }

    public static func describe(_ error: Error) -> String { ErrorDescriber.describe(error) }
}
