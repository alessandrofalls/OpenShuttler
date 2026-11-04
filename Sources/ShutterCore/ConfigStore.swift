import Foundation

/// Already loaded and validated configuration state.
public struct ConfigSnapshot: Sendable {
    public let config: AppConfig
    /// Structured ~/.ssh/config entries ready for menu display (with groups/folders).
    public let sshEntries: [MenuEntry]
    /// Filtered SSH host aliases.
    public let sshHosts: [String]
    public let issues: [ConfigIssue]
    /// Path -> modification date for cache invalidation.
    fileprivate let fingerprint: [String: Double]
}

/// Reads, caches, and bootstraps configuration.
/// Main-thread only by design.
public final class ConfigStore {
    public enum Bootstrap: Equatable {
        case alreadyExists
        case createdSample
        case importedLegacy(issues: [ConfigIssue])
    }

    public let configURL: URL
    public let previousConfigURL: URL?
    public let legacyURL: URL?
    public let sshConfigPath: String
    private var cached: ConfigSnapshot?

    public init(configURL: URL, previousConfigURL: URL? = nil, legacyURL: URL?, sshConfigPath: String) {
        self.configURL = configURL
        self.previousConfigURL = previousConfigURL
        self.legacyURL = legacyURL
        self.sshConfigPath = sshConfigPath
    }

    public static func standard() -> ConfigStore {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return ConfigStore(
            configURL: home
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("openshuttler", isDirectory: true)
                .appendingPathComponent("config.json"),
            previousConfigURL: home.appendingPathComponent(".config/my-own-shutter/config.json"),
            legacyURL: home.appendingPathComponent(".shuttle.json"),
            sshConfigPath: home.appendingPathComponent(".ssh/config").path
        )
    }

    // MARK: - Bootstrapping

    /// Creates configuration if not found: migrates previous configs or writes sample.
    @discardableResult
    public func bootstrap() throws -> Bootstrap {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: configURL.path) else { return .alreadyExists }

        var result = Bootstrap.createdSample
        var config = AppConfig.sample

        // 1. Check if previous version config exists (~/.config/my-own-shutter/config.json)
        if let previousConfigURL,
           fm.fileExists(atPath: previousConfigURL.path),
           let data = try? Data(contentsOf: previousConfigURL),
           let decoded = try? ConfigCodec.decode(data) {
            config = decoded.config
            result = .importedLegacy(issues: decoded.issues)
        } else if let legacyURL, let data = try? Data(contentsOf: legacyURL),
                  let imported = try? LegacyShuttleImporter.importConfig(from: data) {
            config = imported.config
            result = .importedLegacy(issues: imported.issues)
        }

        try fm.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try ConfigCodec.encode(config).write(to: configURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        cached = nil
        return result
    }

    // MARK: - Cached Snapshot

    /// Returns the current state; only re-reads disk if any monitored file changed.
    public func snapshot() -> ConfigSnapshot {
        if let cached, Self.fingerprint(of: Array(cached.fingerprint.keys)) == cached.fingerprint {
            return cached
        }
        let fresh = load()
        cached = fresh
        return fresh
    }

    private func load() -> ConfigSnapshot {
        var issues: [ConfigIssue] = []
        var config = AppConfig()

        do {
            let data = try Data(contentsOf: configURL)
            let decoded = try ConfigCodec.decode(data)
            config = decoded.config
            issues += decoded.issues
        } catch {
            issues.append(ConfigIssue(
                "Unable to read \(configURL.lastPathComponent): \(ConfigCodec.describe(error))"
            ))
        }

        var sshEntries: [MenuEntry] = []
        var sshHosts: [String] = []
        var watched = [configURL.path, sshConfigPath]
        if config.sshConfigHosts.enabled {
            let loaded = SSHConfigLoader.load(rootPath: sshConfigPath)
            let filteredItems = SSHConfigParser.filter(loaded.items, options: config.sshConfigHosts)
            sshEntries = SSHConfigParser.buildMenuEntries(from: filteredItems)
            sshHosts = filteredItems.map(\.alias)
            watched += loaded.files
        }
        return ConfigSnapshot(
            config: config,
            sshEntries: sshEntries,
            sshHosts: sshHosts,
            issues: issues,
            fingerprint: Self.fingerprint(of: watched)
        )
    }

    private static func fingerprint(of paths: [String]) -> [String: Double] {
        var result: [String: Double] = [:]
        for path in paths {
            let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
            result[path] = date?.timeIntervalSince1970 ?? -1
        }
        return result
    }
}
