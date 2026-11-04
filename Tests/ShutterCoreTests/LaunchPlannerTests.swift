import XCTest
@testable import ShutterCore

final class LaunchPlannerTests: XCTestCase {
    private func server(_ target: SSHTarget, name: String = "S") -> Server {
        Server(name: name, kind: .ssh(target))
    }

    private func script(_ server: Server, terminalApp: String? = nil, home: String = "/Users/x",
                        file: StaticString = #filePath, line: UInt = #line) -> String? {
        guard case .script(let text) = LaunchPlanner.plan(for: server, terminalApp: terminalApp, openIn: "new", homeDirectory: home) else {
            XCTFail("esperava script", file: file, line: line)
            return nil
        }
        return text
    }

    func testSimpleServerUsesSSHURLInNewMode() throws {
        let s = server(try SSHTarget(host: "host.example.com", user: "deploy", port: 2222))
        XCTAssertEqual(LaunchPlanner.plan(for: s, terminalApp: nil, openIn: "new", homeDirectory: "/Users/x"),
                       .openURL(URL(string: "ssh://deploy@host.example.com:2222")!))
    }

    func testCurrentModeGeneratesAppleScript() throws {
        let s = server(try SSHTarget(host: "host.example.com", user: "deploy", port: 2222))
        guard case .appleScript(let script) = LaunchPlanner.plan(for: s, terminalApp: nil, openIn: "current") else {
            return XCTFail("esperava appleScript")
        }
        XCTAssertTrue(script.contains("tell application \"Terminal\""))
        XCTAssertTrue(script.contains("in selected tab of front window"))
        XCTAssertTrue(script.contains("ssh -p 2222 -- deploy@host.example.com"))
    }

    func testTabModeGeneratesAppleScript() throws {
        let s = server(try SSHTarget(host: "bastion"))
        guard case .appleScript(let script) = LaunchPlanner.plan(for: s, terminalApp: "iTerm", openIn: "tab") else {
            return XCTFail("esperava appleScript para iTerm")
        }
        XCTAssertTrue(script.contains("tell application \"iTerm\""))
        XCTAssertTrue(script.contains("create tab with default profile"))
        XCTAssertTrue(script.contains("ssh -- bastion"))
    }

    func testDefaultModeUsesNewWindow() throws {
        let s = server(try SSHTarget(host: "bastion"))
        guard case .openURL(let url) = LaunchPlanner.plan(for: s, terminalApp: nil) else {
            return XCTFail("expected openURL in default new mode")
        }
        XCTAssertEqual(url.scheme, "ssh")
        XCTAssertEqual(url.host, "bastion")
    }

    func testTabModeOpensNewTabInTerminal() throws {
        let s = server(try SSHTarget(host: "bastion"))
        guard case .appleScript(let script) = LaunchPlanner.plan(for: s, terminalApp: nil, openIn: "tab") else {
            return XCTFail("expected appleScript for tab mode")
        }
        XCTAssertTrue(script.contains("tell application \"Terminal\""))
        XCTAssertTrue(script.contains("keystroke \"t\" using command down"))
        XCTAssertTrue(script.contains("ssh -- bastion"))
    }

    func testIdentityFileForcesScript() throws {
        let s = server(try SSHTarget(host: "h.com", user: "u", identityFile: "~/.ssh/my key"))
        guard let text = script(s) else { return }
        XCTAssertTrue(text.contains("exec ssh -i '/Users/x/.ssh/my key' -- u@h.com"))
        XCTAssertTrue(text.hasPrefix("#!/bin/zsh\n"))
        XCTAssertTrue(text.contains(#"rm -f -- "$0""#))
    }

    func testJumpHostAndPortOrdering() throws {
        let s = server(try SSHTarget(host: "h.com", port: 22, jumpHost: "me@bastion:2200"))
        guard let text = script(s) else { return }
        XCTAssertTrue(text.contains("exec ssh -p 22 -J me@bastion:2200 -- h.com"))
    }

    func testCustomTerminalAppForcesScript() throws {
        _ = script(server(try SSHTarget(host: "h.com")), terminalApp: "iTerm")
    }

    func testIPv6HostFallsBackToScript() throws {
        _ = script(server(try SSHTarget(host: "[::1]")))
    }

    func testShellCommandIsEmbeddedVerbatim() {
        let s = Server(name: "Túnel", kind: .shell("ssh -L 8080:localhost:80 user@h"))
        guard let text = script(s) else { return }
        XCTAssertTrue(text.contains("\nssh -L 8080:localhost:80 user@h\n"))
        XCTAssertFalse(text.contains("exec ssh -L"))
    }

    func testTitleIsQuotedAndSanitized() {
        let s = Server(name: "It's \u{1B}evil\nname", kind: .shell("true"))
        guard let text = script(s) else { return }
        XCTAssertTrue(text.contains(#"'It'\''s evilname'"#))
        XCTAssertFalse(text.contains("\u{1B}"))
    }
}

final class ShellTests: XCTestCase {
    func testQuoting() {
        XCTAssertEqual(Shell.quote("abc-1.2/x"), "abc-1.2/x")
        XCTAssertEqual(Shell.quote("a b"), "'a b'")
        XCTAssertEqual(Shell.quote("it's"), #"'it'\''s'"#)
        XCTAssertEqual(Shell.quote(""), "''")
        XCTAssertEqual(Shell.quote("$(rm -rf)"), "'$(rm -rf)'")
    }

    func testSplitRespectsQuotes() {
        XCTAssertEqual(Shell.split(#"ssh -i "my key" 'a b' host"#), ["ssh", "-i", "my key", "a b", "host"])
        XCTAssertNil(Shell.split("ssh 'oops"))
    }
}
