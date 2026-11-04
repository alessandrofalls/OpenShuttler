import AppKit
import ShutterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ConfigStore.standard()
    private var statusItem: NSStatusItem?
    private var startupError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        bootstrapConfig()
        Launcher.cleanUpStaleScripts()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "OpenShuttler")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuild(menu)
    }

    // Rebuilds the menu on open; ConfigStore only re-reads disk if files changed.
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func bootstrapConfig() {
        do {
            switch try store.bootstrap() {
            case .alreadyExists:
                break
            case .createdSample:
                Log.config.info("Sample configuration created at \(self.store.configURL.path)")
            case .importedLegacy(let issues):
                Log.config.info("Configuration imported with \(issues.count) warning(s)")
            }
        } catch {
            Log.config.error("Failed to initialize configuration: \(error.localizedDescription)")
            startupError = "Unable to initialize configuration: \(error.localizedDescription)"
        }
    }

    private func rebuild(_ menu: NSMenu) {
        let snapshot = store.snapshot()
        let terminalApp = snapshot.config.terminalApp
        let editor = snapshot.config.editor
        let openIn = snapshot.config.openIn

        let actions = MenuActions(
            launch: { server in Launcher.launch(server, terminalApp: terminalApp, openIn: openIn) },
            editSSHConfig: { [store] in
                Launcher.openEditor(
                    path: store.sshConfigPath,
                    editor: editor,
                    terminalApp: terminalApp
                )
            },
            editConfig: { [store] in
                Launcher.openEditor(
                    path: store.configURL.path,
                    editor: editor,
                    terminalApp: terminalApp
                )
            },
            toggleLogin: {
                do {
                    try LoginItem.toggle()
                } catch {
                    Log.config.error("Login item: \(error.localizedDescription)")
                    Alerts.show(title: "Unable to change Launch at Login setting",
                                message: error.localizedDescription)
                }
            },
            quit: { NSApp.terminate(nil) }
        )
        MenuBuilder.populate(
            menu,
            snapshot: snapshot,
            startupError: startupError,
            loginEnabled: LoginItem.isEnabled,
            actions: actions
        )
    }
}
