import Foundation

/// Structured SSH target. Only instantiable if valid.
public struct SSHTarget: Equatable, Sendable {
    public let host: String
    public let user: String?
    public let port: Int?
    public let identityFile: String?
    public let jumpHost: String?

    public init(
        host: String,
        user: String? = nil,
        port: Int? = nil,
        identityFile: String? = nil,
        jumpHost: String? = nil
    ) throws {
        guard Validation.isValidHost(host) else { throw ConfigError("invalid host: '\(host)'") }
        if let user, !Validation.isValidUser(user) { throw ConfigError("invalid user: '\(user)'") }
        if let port, !Validation.isValidPort(port) { throw ConfigError("invalid port: \(port)") }
        if let identityFile, !Validation.isValidPath(identityFile) { throw ConfigError("invalid identityFile") }
        if let jumpHost, !Validation.isValidJumpHost(jumpHost) { throw ConfigError("invalid jumpHost: '\(jumpHost)'") }
        self.host = host
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.jumpHost = jumpHost
    }
}

/// A clickable menu item representing a server or shell command.
public struct Server: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Structured SSH connection.
        case ssh(SSHTarget)
        /// Arbitrary shell command.
        case shell(String)
    }

    public var name: String
    public var kind: Kind
    public var tooltip: String?

    public init(name: String, kind: Kind, tooltip: String? = nil) {
        self.name = name
        self.kind = kind
        self.tooltip = tooltip
    }

    /// Creates a server from an SSH config alias.
    public static func sshConfigAlias(_ alias: String, displayName: String? = nil, tooltip: String? = nil) -> Server? {
        guard let target = try? SSHTarget(host: alias) else { return nil }
        return Server(name: displayName ?? alias, kind: .ssh(target), tooltip: tooltip)
    }

    /// Short tooltip summary (e.g. `deploy@host:2222`).
    public var summary: String {
        if let tooltip { return tooltip }
        switch kind {
        case .ssh(let t):
            var s = ""
            if let user = t.user { s += "\(user)@" }
            s += t.host
            if let port = t.port { s += ":\(port)" }
            return s
        case .shell(let command):
            return command.count > 80 ? String(command.prefix(80)) + "…" : command
        }
    }
}

// MARK: - Codable

extension Server: Codable {
    private enum Keys: String, CodingKey {
        case name, host, user, port, identityFile, jumpHost, command
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let rawName = try c.decodeIfPresent(String.self, forKey: .name)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        func corrupted(_ message: String) -> DecodingError {
            .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: message))
        }

        if let command = try c.decodeIfPresent(String.self, forKey: .command) {
            guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw corrupted("'command' is empty")
            }
            guard let rawName, !rawName.isEmpty else {
                throw corrupted("'name' is required when 'command' is used")
            }
            self.init(name: rawName, kind: .shell(command))
            return
        }

        guard let host = try c.decodeIfPresent(String.self, forKey: .host) else {
            throw DecodingError.keyNotFound(
                Keys.host,
                .init(codingPath: decoder.codingPath, debugDescription: "missing host")
            )
        }
        let target: SSHTarget
        do {
            target = try SSHTarget(
                host: host,
                user: try c.decodeIfPresent(String.self, forKey: .user),
                port: try c.decodeIfPresent(Int.self, forKey: .port),
                identityFile: try c.decodeIfPresent(String.self, forKey: .identityFile),
                jumpHost: try c.decodeIfPresent(String.self, forKey: .jumpHost)
            )
        } catch let error as ConfigError {
            throw corrupted(error.message)
        }
        let name = (rawName?.isEmpty == false) ? rawName! : host
        self.init(name: name, kind: .ssh(target))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(name, forKey: .name)
        switch kind {
        case .ssh(let t):
            try c.encode(t.host, forKey: .host)
            try c.encodeIfPresent(t.user, forKey: .user)
            try c.encodeIfPresent(t.port, forKey: .port)
            try c.encodeIfPresent(t.identityFile, forKey: .identityFile)
            try c.encodeIfPresent(t.jumpHost, forKey: .jumpHost)
        case .shell(let command):
            try c.encode(command, forKey: .command)
        }
    }
}
