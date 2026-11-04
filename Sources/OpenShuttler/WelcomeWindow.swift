import AppKit
import ShutterCore

/// Displays a clean, native welcome onboarding window on first launch.
@MainActor
final class WelcomeWindowController: NSWindowController {
    static let shared = WelcomeWindowController()

    private static let hasSeenWelcomeKey = "hasSeenWelcomeWindow_v1"

    static var shouldShowOnLaunch: Bool {
        !UserDefaults.standard.bool(forKey: hasSeenWelcomeKey)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Welcome to OpenShuttler"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false

        super.init(window: window)
        setupContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(highlightStatusItem: @escaping () -> Void = {}) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        UserDefaults.standard.set(true, forKey: Self.hasSeenWelcomeKey)
    }

    private func setupContent() {
        guard let window else { return }

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .centerX
        container.spacing = 16
        container.edgeInsets = NSEdgeInsets(top: 36, left: 32, bottom: 28, right: 32)
        container.translatesAutoresizingMaskIntoConstraints = false

        // 1. App Icon
        let iconImageView = NSImageView()
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        if let icon = NSImage(named: NSImage.applicationIconName) {
            iconImageView.image = icon
        } else if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            iconImageView.image = NSImage(contentsOf: iconURL)
        }
        iconImageView.widthAnchor.constraint(equalToConstant: 96).isActive = true
        iconImageView.heightAnchor.constraint(equalToConstant: 96).isActive = true
        container.addArrangedSubview(iconImageView)

        // 2. Title
        let titleLabel = NSTextField(labelWithString: "Welcome to OpenShuttler")
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.alignment = .center
        container.addArrangedSubview(titleLabel)

        // 3. Subtitle / Explanation
        let subtitle = NSTextField(wrappingLabelWithString:
            "OpenShuttler runs as a lightweight menu bar utility.\nLook for the terminal icon (>_) in your macOS menu bar at the top right of your screen."
        )
        subtitle.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        container.addArrangedSubview(subtitle)

        // 4. Feature Highlights Box
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 10
        box.fillColor = NSColor.labelColor.withAlphaComponent(0.04)
        box.borderColor = NSColor.separatorColor
        box.borderWidth = 1

        let boxStack = NSStackView()
        boxStack.orientation = .vertical
        boxStack.alignment = .leading
        boxStack.spacing = 10
        boxStack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        boxStack.translatesAutoresizingMaskIntoConstraints = false

        func makeRow(icon: String, text: String) -> NSStackView {
            let row = NSStackView()
            row.spacing = 10
            row.alignment = .centerY
            let img = NSImageView()
            let sf = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
            img.image = sf
            img.contentTintColor = .controlAccentColor
            img.widthAnchor.constraint(equalToConstant: 18).isActive = true
            let lbl = NSTextField(wrappingLabelWithString: text)
            lbl.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            row.addArrangedSubview(img)
            row.addArrangedSubview(lbl)
            return row
        }

        boxStack.addArrangedSubview(makeRow(icon: "key.fill", text: "Reads servers directly from ~/.ssh/config"))
        boxStack.addArrangedSubview(makeRow(icon: "folder.fill", text: "Supports groups (# Group: Name) and tooltips"))
        boxStack.addArrangedSubview(makeRow(icon: "macwindow", text: "Opens in new tabs or focused windows"))

        box.contentView = boxStack
        container.addArrangedSubview(box)
        box.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -16).isActive = true

        // 5. Actions / Dismiss button
        let buttonStack = NSStackView()
        buttonStack.spacing = 12

        let startButton = NSButton(title: "Get Started", target: self, action: #selector(didClickGetStarted))
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r" // Enter key triggers it
        startButton.controlSize = .large

        let editConfigButton = NSButton(title: "Edit ~/.ssh/config", target: self, action: #selector(didClickEditConfig))
        editConfigButton.bezelStyle = .rounded
        editConfigButton.controlSize = .large

        buttonStack.addArrangedSubview(editConfigButton)
        buttonStack.addArrangedSubview(startButton)
        container.addArrangedSubview(buttonStack)

        window.contentView = container
    }

    @objc private func didClickGetStarted() {
        window?.close()
    }

    @objc private func didClickEditConfig() {
        let store = ConfigStore.standard()
        Launcher.openEditor(path: store.sshConfigPath, editor: nil, terminalApp: nil)
        window?.close()
    }
}

