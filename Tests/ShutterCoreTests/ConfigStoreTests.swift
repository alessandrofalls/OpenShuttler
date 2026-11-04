import XCTest
@testable import ShutterCore

final class ConfigStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeStore(legacy: Bool = false) -> ConfigStore {
        ConfigStore(
            configURL: dir.appendingPathComponent("cfg/config.json"),
            legacyURL: legacy ? dir.appendingPathComponent(".shuttle.json") : nil,
            sshConfigPath: dir.appendingPathComponent("ssh_config").path
        )
    }

    /// Rewrites file and updates mtime (filesystem resolution might hide rapid changes).
    private func rewrite(_ store: ConfigStore, _ text: String) throws {
        try text.write(to: store.configURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(30)],
                                              ofItemAtPath: store.configURL.path)
    }

    func testBootstrapCreatesSampleOnce() throws {
        let store = makeStore()
        XCTAssertEqual(try store.bootstrap(), .createdSample)
        XCTAssertEqual(try store.bootstrap(), .alreadyExists)
        XCTAssertEqual(store.snapshot().config, .sample)
    }

    func testBootstrapImportsLegacyWithoutTouchingIt() throws {
        let legacyURL = dir.appendingPathComponent(".shuttle.json")
        let legacyText = #"{"hosts":[{"name":"A","cmd":"ssh u@a.com"}]}"#
        try legacyText.write(to: legacyURL, atomically: true, encoding: .utf8)

        let store = makeStore(legacy: true)
        guard case .importedLegacy = try store.bootstrap() else { return XCTFail("failed to import legacy config") }
        XCTAssertEqual(store.snapshot().config.entries.count, 1)
        XCTAssertEqual(try String(contentsOf: legacyURL, encoding: .utf8), legacyText)
    }

    func testBrokenLegacyFallsBackToSample() throws {
        try "{ quebrado".write(to: dir.appendingPathComponent(".shuttle.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try makeStore(legacy: true).bootstrap(), .createdSample)
    }

    func testSnapshotReloadsWhenFileChanges() throws {
        let store = makeStore()
        try store.bootstrap()
        let first = store.snapshot()

        try rewrite(store, #"{"servers":[{"host":"novo.example.com"}]}"#)
        let second = store.snapshot()
        XCTAssertNotEqual(first.config, second.config)
        XCTAssertEqual(second.config.entries.count, 1)
    }

    func testSnapshotIsCachedWhenNothingChanged() throws {
        let store = makeStore()
        try store.bootstrap()
        XCTAssertEqual(store.snapshot().config, store.snapshot().config)
    }

    func testInvalidJSONProducesIssueNotCrash() throws {
        let store = makeStore()
        try store.bootstrap()
        try rewrite(store, "{ quebrado")
        let snapshot = store.snapshot()
        XCTAssertTrue(snapshot.config.entries.isEmpty)
        XCTAssertEqual(snapshot.issues.count, 1)
    }

    func testIncludesSSHConfigHostsAndRespectsToggle() throws {
        let store = makeStore()
        try store.bootstrap()
        try "Host zeta\nHost alfa\n".write(to: dir.appendingPathComponent("ssh_config"), atomically: true, encoding: .utf8)
        XCTAssertEqual(store.snapshot().sshHosts, ["alfa", "zeta"])

        try rewrite(store, #"{"sshConfigHosts":{"enabled":false}}"#)
        XCTAssertTrue(store.snapshot().sshHosts.isEmpty)
    }
}
