import AppKit
import ServiceManagement

final class PreferencesWindowController: NSWindowController {
    private let speedCheckbox = NSButton(checkboxWithTitle: "Show network speed in the menu", target: nil, action: nil)
    private let updatesCheckbox = NSButton(checkboxWithTitle: "Automatically check for updates", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch MacErnet at login", target: nil, action: nil)
    var onSpeedPreferenceChange: (() -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 225),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacErnet Settings"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        configureContent()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        syncFromDefaults()
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func configureContent() {
        guard let window else { return }

        let title = NSTextField(labelWithString: "MacErnet")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "Ethernet menu bar settings")
        subtitle.textColor = .secondaryLabelColor

        speedCheckbox.target = self
        speedCheckbox.action = #selector(speedChanged)
        updatesCheckbox.target = self
        updatesCheckbox.action = #selector(updatesChanged)
        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginChanged)

        let note = NSTextField(wrappingLabelWithString: "The menu bar icon is hidden automatically whenever no active Ethernet connection is detected.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)

        let stack = NSStackView(views: [title, subtitle, speedCheckbox, updatesCheckbox, loginCheckbox, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22)
        ])
        note.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func syncFromDefaults() {
        speedCheckbox.state = UserDefaults.standard.bool(forKey: AppPreferences.showNetworkSpeed) ? .on : .off
        updatesCheckbox.state = UserDefaults.standard.bool(forKey: AppPreferences.checkForUpdatesAutomatically) ? .on : .off
        if #available(macOS 13.0, *) {
            loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    @objc private func speedChanged() {
        UserDefaults.standard.set(speedCheckbox.state == .on, forKey: AppPreferences.showNetworkSpeed)
        onSpeedPreferenceChange?()
    }

    @objc private func updatesChanged() {
        UserDefaults.standard.set(updatesCheckbox.state == .on, forKey: AppPreferences.checkForUpdatesAutomatically)
    }

    @objc private func loginChanged() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if loginCheckbox.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t Change Login Setting"
            alert.runModal()
        }
    }
}
