import AppKit
import ShutterCore

/// Menu item that fires a Swift closure.
@MainActor
final class ActionMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, keyEquivalent: String = "", handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: nil, keyEquivalent: keyEquivalent)
        action = #selector(fire)
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}

struct MenuActions {
    var launch: @MainActor (Server) -> Void
    var editSSHConfig: @MainActor () -> Void
    var editConfig: @MainActor () -> Void
    var toggleLogin: @MainActor () -> Void
    var quit: @MainActor () -> Void
}

/// Builds the NSMenu from a ConfigSnapshot. Stateless.
@MainActor
enum MenuBuilder {
    static func populate(
        _ menu: NSMenu,
        snapshot: ConfigSnapshot,
        startupError: String?,
        loginEnabled: Bool,
        actions: MenuActions
    ) {
        menu.removeAllItems()

        var warnings = snapshot.issues.map(\.message)
        if let startupError { warnings.insert(startupError, at: 0) }
        if !warnings.isEmpty {
            addWarnings(warnings, to: menu)
            menu.addItem(.separator())
        }

        var hasContent = false

        // 1. Entries parsed from ~/.ssh/config (first-class citizen)
        if !snapshot.sshEntries.isEmpty {
            add(snapshot.sshEntries, to: menu, actions: actions)
            hasContent = true
        }

        // 2. Additional custom commands from config.json (if any)
        if !snapshot.config.entries.isEmpty {
            if hasContent { menu.addItem(.separator()) }
            add(snapshot.config.entries, to: menu, actions: actions)
            hasContent = true
        }

        if !hasContent {
            let empty = NSMenuItem(title: "No servers configured", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "Edit ~/.ssh/config…", keyEquivalent: "e", handler: actions.editSSHConfig))
        menu.addItem(ActionMenuItem(title: "Edit App Preferences…", keyEquivalent: ",", handler: actions.editConfig))
        let login = ActionMenuItem(title: "Launch at Login", handler: actions.toggleLogin)
        login.state = loginEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "Quit", keyEquivalent: "q", handler: actions.quit))
    }

    private static func add(_ entries: [MenuEntry], to menu: NSMenu, actions: MenuActions) {
        for entry in entries {
            switch entry {
            case .server(let server):
                menu.addItem(serverItem(server, actions: actions))
            case .separator:
                menu.addItem(.separator())
            case .folder(let name, let items):
                let submenu = NSMenu()
                add(items, to: submenu, actions: actions)
                let parent = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                parent.submenu = submenu
                menu.addItem(parent)
            }
        }
    }

    private static func serverItem(_ server: Server, actions: MenuActions) -> NSMenuItem {
        let launch = actions.launch
        let item = ActionMenuItem(title: server.name) { launch(server) }
        item.toolTip = server.summary
        return item
    }

    private static func addWarnings(_ warnings: [String], to menu: NSMenu) {
        let submenu = NSMenu()
        for warning in warnings {
            let text = warning.count > 100 ? String(warning.prefix(100)) + "…" : warning
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.toolTip = warning
            submenu.addItem(item)
        }
        let title = warnings.count == 1 ? "⚠️ 1 configuration warning" : "⚠️ \(warnings.count) configuration warnings"
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        menu.addItem(parent)
    }
}
