import XCTest
@testable import ShutterCore

final class SSHConfigTests: XCTestCase {
    func testParsesHostsAndSkipsPatterns() {
        let text = """
        # comentário
        Host alpha beta
            HostName 10.0.0.1
        Host *
            ServerAliveInterval 30
        host=gamma
        Host !negado *.corp prod-?
        Host "quoted"
        Include conf.d/*.conf
        """
        let parsed = SSHConfigParser.parse(text)
        XCTAssertEqual(parsed.hosts, ["alpha", "beta", "gamma", "quoted"])
        XCTAssertEqual(parsed.includes, ["conf.d/*.conf"])
    }

    func testParsesMetadataAndBuildsMenuEntries() {
        let text = """
        # Group: Cloud
        # Description: Servidor Web
        Host web-prod
            HostName 1.2.3.4
            User admin
            Port 2222
            IdentityFile ~/.ssh/id_rsa

        # Description: DB Interno
        Host db-prod
            HostName 10.0.0.2
            User postgres

        # Group: none
        Host infra/bastion
            HostName bastion.corp.com

        Host standalone
            HostName standalone.org
        """
        let parsed = SSHConfigParser.parse(text)
        XCTAssertEqual(parsed.items.count, 4)

        let web = parsed.items[0]
        XCTAssertEqual(web.alias, "web-prod")
        XCTAssertEqual(web.displayName, "Servidor Web")
        XCTAssertEqual(web.group, "Cloud")
        XCTAssertEqual(web.hostName, "1.2.3.4")
        XCTAssertEqual(web.user, "admin")
        XCTAssertEqual(web.port, 2222)
        XCTAssertEqual(web.identityFile, "~/.ssh/id_rsa")
        XCTAssertTrue(web.summary.contains("admin@1.2.3.4"))

        let bastion = parsed.items[2]
        XCTAssertEqual(bastion.alias, "infra/bastion")
        XCTAssertEqual(bastion.displayName, "bastion")
        XCTAssertEqual(bastion.group, "infra")

        let entries = SSHConfigParser.buildMenuEntries(from: parsed.items)
        // Should contain 2 folders (Cloud and infra) and 1 root server (standalone)
        XCTAssertEqual(entries.count, 3)

        guard case .folder(let name1, let items1) = entries[0] else { return XCTFail("expected folder") }
        XCTAssertEqual(name1, "Cloud")
        XCTAssertEqual(items1.count, 2)

        guard case .folder(let name2, let items2) = entries[1] else { return XCTFail("expected folder") }
        XCTAssertEqual(name2, "infra")
        XCTAssertEqual(items2.count, 1)

        guard case .server(let standalone) = entries[2] else { return XCTFail("expected server") }
        XCTAssertEqual(standalone.name, "standalone")
    }

    func testHostnameKeywordIsNotAHost() {
        XCTAssertTrue(SSHConfigParser.parse("HostName example.com").hosts.isEmpty)
    }

    func testFilterDedupesSortsAndIgnores() {
        let options = SSHConfigOptions(enabled: true, ignoreHosts: ["skip"], ignoreKeywords: ["tmp"])
        XCTAssertEqual(SSHConfigParser.filter(["b", "A", "skip", "tmp-1", "b", "c"], options: options),
                       ["A", "b", "c"])
    }

    func testLoaderFollowsIncludes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("conf.d"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "Host root\nInclude conf.d/*.conf\n".write(to: dir.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        try "Host included\n".write(to: dir.appendingPathComponent("conf.d/a.conf"), atomically: true, encoding: .utf8)

        let result = SSHConfigLoader.load(rootPath: dir.appendingPathComponent("config").path)
        XCTAssertEqual(Set(result.hosts), ["root", "included"])
        XCTAssertEqual(result.files.count, 2)
    }

    func testLoaderSurvivesIncludeCycles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("config")
        try "Host loop\nInclude \(path.path)\n".write(to: path, atomically: true, encoding: .utf8)

        XCTAssertEqual(SSHConfigLoader.load(rootPath: path.path).hosts, ["loop"])
    }

    func testMissingFileIsEmpty() {
        XCTAssertTrue(SSHConfigLoader.load(rootPath: "/nonexistent/\(UUID().uuidString)").hosts.isEmpty)
    }
}

final class LegacyImporterTests: XCTestCase {
    private let legacy = """
    {
      "terminal": "iTerm.app",
      "editor": "default",
      "show_ssh_config_hosts": true,
      "ssh_config_ignore_hosts": ["x"],
      "hosts": [
        {"name": "Simples", "cmd": "ssh user@host.com"},
        {"name": "Porta", "cmd": "ssh -p 2222 -l bob host2.com"},
        {"name": "Chave", "cmd": "ssh -i ~/.ssh/id_ed25519 user@host3.com"},
        {"name": "-", "cmd": "-"},
        {"name": "Túnel", "cmd": "ssh -L 8080:localhost:80 user@host4.com"},
        {"name": "Encadeado", "cmd": "ssh a@b.com && echo oi"},
        {"name": "Remoto", "cmd": "ssh user@host5.com uptime"},
        {"Clientes": [
            {"name": "Dentro", "cmd": "ssh admin@cliente.com"}
        ]}
      ]
    }
    """

    private func kind(_ entry: MenuEntry) -> Server.Kind? {
        if case .server(let s) = entry { return s.kind }
        return nil
    }

    private func entries() throws -> [MenuEntry] {
        try LegacyShuttleImporter.importConfig(from: Data(legacy.utf8)).config.entries
    }

    func testImportsSettings() throws {
        let out = try LegacyShuttleImporter.importConfig(from: Data(legacy.utf8))
        XCTAssertEqual(out.config.terminalApp, "iTerm")
        XCTAssertNil(out.config.editor)
        XCTAssertTrue(out.config.sshConfigHosts.enabled)
        XCTAssertEqual(out.config.sshConfigHosts.ignoreHosts, ["x"])
        XCTAssertTrue(out.issues.isEmpty)
    }

    func testMapsSimpleCommandsToStructuredTargets() throws {
        let e = try entries()
        XCTAssertEqual(kind(e[0]), .ssh(try SSHTarget(host: "host.com", user: "user")))
        XCTAssertEqual(kind(e[1]), .ssh(try SSHTarget(host: "host2.com", user: "bob", port: 2222)))
        XCTAssertEqual(kind(e[2]), .ssh(try SSHTarget(host: "host3.com", user: "user", identityFile: "~/.ssh/id_ed25519")))
        XCTAssertEqual(e[3], .separator)
    }

    func testKeepsComplexCommandsAsShell() throws {
        let e = try entries()
        XCTAssertEqual(kind(e[4]), .shell("ssh -L 8080:localhost:80 user@host4.com"))
        XCTAssertEqual(kind(e[5]), .shell("ssh a@b.com && echo oi"))
        XCTAssertEqual(kind(e[6]), .shell("ssh user@host5.com uptime"))
    }

    func testImportsFolders() throws {
        guard case .folder(let name, let items) = try entries()[7] else { return XCTFail("sem pasta") }
        XCTAssertEqual(name, "Clientes")
        XCTAssertEqual(items.count, 1)
    }

    func testImportedConfigSurvivesRoundTrip() throws {
        let config = try LegacyShuttleImporter.importConfig(from: Data(legacy.utf8)).config
        let decoded = try ConfigCodec.decode(try ConfigCodec.encode(config))
        XCTAssertEqual(decoded.config, config)
        XCTAssertTrue(decoded.issues.isEmpty)
    }

    func testRejectsNonObjectRoot() {
        XCTAssertThrowsError(try LegacyShuttleImporter.importConfig(from: Data("[]".utf8)))
    }
}
