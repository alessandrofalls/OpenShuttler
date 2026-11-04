import XCTest
@testable import ShutterCore

final class ConfigDecodingTests: XCTestCase {
    func testDecodesStructuredServer() throws {
        let json = """
        {"servers":[{"name":"Prod","host":"prod.example.com","user":"deploy","port":2222,
                     "identityFile":"~/.ssh/id","jumpHost":"bastion"}]}
        """
        let (config, issues) = try ConfigCodec.decode(Data(json.utf8))
        XCTAssertTrue(issues.isEmpty)
        guard case .server(let server) = config.entries.first, case .ssh(let t) = server.kind else {
            return XCTFail("expected an SSH server")
        }
        XCTAssertEqual(server.name, "Prod")
        XCTAssertEqual(t.host, "prod.example.com")
        XCTAssertEqual(t.user, "deploy")
        XCTAssertEqual(t.port, 2222)
        XCTAssertEqual(t.jumpHost, "bastion")
    }

    func testNameDefaultsToHost() throws {
        let (config, _) = try ConfigCodec.decode(Data(#"{"servers":[{"host":"a.example.com"}]}"#.utf8))
        guard case .server(let server) = config.entries.first else { return XCTFail("missing server") }
        XCTAssertEqual(server.name, "a.example.com")
    }

    func testRejectsOptionInjectionInHost() throws {
        let json = #"{"servers":[{"name":"x","host":"-oProxyCommand=touch /tmp/pwned"}]}"#
        let (config, issues) = try ConfigCodec.decode(Data(json.utf8))
        XCTAssertTrue(config.entries.isEmpty)
        XCTAssertEqual(issues.count, 1)
    }

    func testBadEntriesBecomeIssuesAndDoNotDropTheRest() throws {
        let json = """
        {"servers":[
          {"name":"ok1","host":"a.example.com"},
          {"name":"porta","host":"b.example.com","port":70000},
          "this is not an object",
          {"name":"missing host"},
          {"folder":"Folder","items":[{"host":"c.example.com"},{"host":"bad host"}]},
          {"separator":true},
          {"name":"ok2","host":"d.example.com"}
        ]}
        """
        let (config, issues) = try ConfigCodec.decode(Data(json.utf8))
        XCTAssertEqual(issues.count, 4)
        XCTAssertEqual(config.entries.count, 4)   // ok1, folder, separator, ok2
        guard case .folder(_, let items) = config.entries[1] else { return XCTFail("missing folder") }
        XCTAssertEqual(items.count, 1)
    }

    func testShellCommandRequiresName() throws {
        let (config, issues) = try ConfigCodec.decode(Data(#"{"servers":[{"command":"ssh -L 80:x:80 h"}]}"#.utf8))
        XCTAssertTrue(config.entries.isEmpty)
        XCTAssertEqual(issues.count, 1)
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try ConfigCodec.decode(Data("{ not json".utf8)))
    }

    func testRejectsNewerVersion() {
        XCTAssertThrowsError(try ConfigCodec.decode(Data(#"{"version":99}"#.utf8)))
    }

    func testRoundTrip() throws {
        let config = AppConfig(
            sshConfigHosts: .init(enabled: true, ignoreHosts: ["x"], ignoreKeywords: ["tmp"]),
            terminalApp: "iTerm",
            entries: [
                .server(Server(name: "A", kind: .ssh(try SSHTarget(host: "a.com", user: "u", port: 22)))),
                .separator,
                .folder(name: "F", items: [.server(Server(name: "S", kind: .shell("ssh -A h")))])
            ]
        )
        let decoded = try ConfigCodec.decode(try ConfigCodec.encode(config))
        XCTAssertEqual(decoded.config, config)
        XCTAssertTrue(decoded.issues.isEmpty)
    }

    func testSampleIsValid() throws {
        let decoded = try ConfigCodec.decode(try ConfigCodec.encode(.sample))
        XCTAssertTrue(decoded.issues.isEmpty)
        XCTAssertEqual(decoded.config, .sample)
    }
}
