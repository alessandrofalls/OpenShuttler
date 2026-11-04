import Foundation

/// Represents a host configured in `~/.ssh/config` along with extracted metadata.
public struct SSHHostItem: Equatable, Sendable {
    public var alias: String
    public var displayName: String
    public var group: String?
    public var hostName: String?
    public var user: String?
    public var port: Int?
    public var identityFile: String?

    public init(
        alias: String,
        displayName: String? = nil,
        group: String? = nil,
        hostName: String? = nil,
        user: String? = nil,
        port: Int? = nil,
        identityFile: String? = nil
    ) {
        self.alias = alias
        self.displayName = displayName ?? alias
        self.group = group
        self.hostName = hostName
        self.user = user
        self.port = port
        self.identityFile = identityFile
    }

    /// Detailed connection summary displayed in menu tooltips.
    public var summary: String {
        var parts: [String] = []
        if let user, let hostName {
            parts.append("\(user)@\(hostName)")
        } else if let hostName {
            parts.append(hostName)
        } else if let user {
            parts.append("user: \(user)")
        }
        if let port {
            parts.append("port: \(port)")
        }
        if let identityFile {
            let shortKey = (identityFile as NSString).lastPathComponent
            parts.append("key: \(shortKey)")
        }
        let detail = parts.isEmpty ? "" : " (\(parts.joined(separator: ", ")))"
        return "ssh \(alias)\(detail)"
    }
}

/// Parser for `~/.ssh/config` supporting metadata tags (# Group:, # Description:), folders, and includes.
public enum SSHConfigParser {
    public struct Parsed: Equatable, Sendable {
        public var items: [SSHHostItem] = []
        public var includes: [String] = []

        /// List of host aliases for backward compatibility.
        public var hosts: [String] { items.map(\.alias) }
    }

    public static func parse(_ text: String) -> Parsed {
        var parsed = Parsed()
        var currentGroup: String?
        var pendingDescription: String?
        var currentBlockIndices: [Int] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // Annotation comments (# Group: ..., # Description: ...)
            if line.hasPrefix("#") {
                let isIndented = rawLine.hasPrefix(" ") || rawLine.hasPrefix("\t")
                let comment = line.dropFirst().trimmingCharacters(in: .whitespaces)
                let lower = comment.lowercased()

                if lower.hasPrefix("group:") || lower.hasPrefix("folder:") {
                    let sep = comment.firstIndex(of: ":")!
                    let val = comment[comment.index(after: sep)...].trimmingCharacters(in: .whitespaces)
                    currentGroup = (val.lowercased() == "none" || val.isEmpty) ? nil : val
                    currentBlockIndices = []
                } else if lower.hasPrefix("description:") || lower.hasPrefix("name:") {
                    let sep = comment.firstIndex(of: ":")!
                    let val = String(comment[comment.index(after: sep)...]).trimmingCharacters(in: .whitespaces)
                    if isIndented && !currentBlockIndices.isEmpty {
                        for idx in currentBlockIndices {
                            parsed.items[idx].displayName = val
                        }
                    } else {
                        currentBlockIndices = []
                        pendingDescription = val
                    }
                }
                continue
            }

            guard let sep = line.firstIndex(where: { $0 == " " || $0 == "\t" || $0 == "=" }) else { continue }
            let keyword = line[..<sep].lowercased()
            let rest = String(line[line.index(after: sep)...])
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t="))
            let values = (Shell.split(rest) ?? []).filter { !$0.isEmpty }

            switch keyword {
            case "host":
                currentBlockIndices = []
                for rawAlias in values {
                    // Wildcard patterns ("*", "?", "!negation") are not direct connectable hosts.
                    if rawAlias.contains("*") || rawAlias.contains("?") || rawAlias.hasPrefix("!") { continue }
                    if !Validation.isValidHost(rawAlias) { continue }

                    var group = currentGroup
                    var display = pendingDescription ?? rawAlias

                    // Slash grouping support: Host Group/Server
                    if rawAlias.contains("/") {
                        let parts = rawAlias.split(separator: "/", maxSplits: 1).map(String.init)
                        if parts.count == 2 {
                            group = parts[0]
                            if pendingDescription == nil {
                                display = parts[1]
                            }
                        }
                    }

                    let item = SSHHostItem(alias: rawAlias, displayName: display, group: group)
                    parsed.items.append(item)
                    currentBlockIndices.append(parsed.items.count - 1)
                }
                pendingDescription = nil

            case "hostname":
                if let val = values.first {
                    for idx in currentBlockIndices { parsed.items[idx].hostName = val }
                }

            case "user":
                if let val = values.first {
                    for idx in currentBlockIndices { parsed.items[idx].user = val }
                }

            case "port":
                if let val = values.first, let p = Int(val) {
                    for idx in currentBlockIndices { parsed.items[idx].port = p }
                }

            case "identityfile":
                if let val = values.first {
                    for idx in currentBlockIndices { parsed.items[idx].identityFile = val }
                }

            case "include":
                parsed.includes += values
                currentBlockIndices = []

            default:
                break
            }
        }
        return parsed
    }

    /// Filters items based on configured ignore options.
    public static func filter(_ items: [SSHHostItem], options: SSHConfigOptions) -> [SSHHostItem] {
        var seen = Set<String>()
        return items
            .filter { !options.ignoreHosts.contains($0.alias) }
            .filter { item in
                !options.ignoreKeywords.contains { kw in
                    item.alias.contains(kw) || item.displayName.contains(kw)
                }
            }
            .filter { seen.insert($0.alias).inserted }
            .sorted { $0.alias.localizedCaseInsensitiveCompare($1.alias) == .orderedAscending }
    }

    /// Legacy filter for test compatibility.
    public static func filter(_ hosts: [String], options: SSHConfigOptions) -> [String] {
        let dummyItems = hosts.map { SSHHostItem(alias: $0) }
        return filter(dummyItems, options: options).map(\.alias)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Converts SSH items into a hierarchy of MenuEntry items with folder support.
    public static func buildMenuEntries(from items: [SSHHostItem]) -> [MenuEntry] {
        var rootServers: [MenuEntry] = []
        var grouped: [String: [SSHHostItem]] = [:]
        var groupOrder: [String] = []

        for item in items {
            if let group = item.group, !group.isEmpty {
                if grouped[group] == nil {
                    grouped[group] = []
                    groupOrder.append(group)
                }
                grouped[group]!.append(item)
            } else {
                if let server = serverFromItem(item) {
                    rootServers.append(.server(server))
                }
            }
        }

        var result: [MenuEntry] = []

        // Folders first (alphabetical order)
        let sortedGroups = groupOrder.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        for group in sortedGroups {
            guard let groupItems = grouped[group] else { continue }
            let serverEntries: [MenuEntry] = groupItems.compactMap { item in
                serverFromItem(item).map { .server($0) }
            }
            if !serverEntries.isEmpty {
                result.append(.folder(name: group, items: serverEntries))
            }
        }

        // Servers at the root level
        result.append(contentsOf: rootServers)
        return result
    }

    private static func serverFromItem(_ item: SSHHostItem) -> Server? {
        Server.sshConfigAlias(item.alias, displayName: item.displayName, tooltip: item.summary)
    }
}

/// Loads `~/.ssh/config` recursively following `Include` patterns.
public enum SSHConfigLoader {
    public struct Result: Equatable, Sendable {
        public var items: [SSHHostItem] = []
        public var hosts: [String] { items.map(\.alias) }
        /// Monitored file paths for change detection.
        public var files: [String] = []
    }

    private static let maxDepth = 5

    public static func load(rootPath: String) -> Result {
        var result = Result()
        var visited = Set<String>()
        let baseDirectory = (rootPath as NSString).deletingLastPathComponent

        func visit(_ path: String, depth: Int) {
            guard depth <= maxDepth, visited.insert(path).inserted,
                  let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
            result.files.append(path)
            let parsed = SSHConfigParser.parse(text)
            result.items += parsed.items
            for pattern in parsed.includes {
                for included in expand(pattern, baseDirectory: baseDirectory) {
                    visit(included, depth: depth + 1)
                }
            }
        }
        visit(rootPath, depth: 0)
        return result
    }

    private static func expand(_ pattern: String, baseDirectory: String) -> [String] {
        let absolute = (pattern.hasPrefix("/") || pattern.hasPrefix("~"))
            ? pattern
            : baseDirectory + "/" + pattern
        var g = glob_t()
        defer { globfree(&g) }
        guard glob(absolute, GLOB_TILDE, nil, &g) == 0 else { return [] }
        return (0..<Int(g.gl_pathc)).compactMap { index in
            g.gl_pathv[index].map { String(cString: $0) }
        }
    }
}
