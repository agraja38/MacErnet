import AppKit
import ServiceManagement

@MainActor
final class PreferencesWindowController: NSWindowController {
    private let speedCheckbox = NSButton(checkboxWithTitle: "Show network speed in the menu", target: nil, action: nil)
    private let updatesCheckbox = NSButton(checkboxWithTitle: "Automatically check for updates", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch MacErnet at login", target: nil, action: nil)
    private var iconButtons: [MenuBarIconStyle: NSButton] = [:]

    var onSpeedPreferenceChange: (() -> Void)?
    var onIconPreferenceChange: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 350),
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
        guard let contentView = window?.contentView else { return }

        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.addTabViewItem(makeGeneralTab())
        tabView.addTabViewItem(makeUpdatesTab())
        tabView.addTabViewItem(makeAboutTab())
        contentView.addSubview(tabView)

        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }

    private func makeGeneralTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "general")
        item.label = "General"

        speedCheckbox.target = self
        speedCheckbox.action = #selector(speedChanged)
        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginChanged)

        let iconTitle = sectionTitle("Menu bar icon")
        let iconStack = NSStackView()
        iconStack.orientation = .horizontal
        iconStack.spacing = 16

        for style in MenuBarIconStyle.allCases {
            let button = NSButton(radioButtonWithTitle: style.title, target: self, action: #selector(iconChanged(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(style.rawValue)
            button.image = MenuBarIconLibrary.image(for: style, size: 24)
            button.imagePosition = .imageLeft
            iconButtons[style] = button
            iconStack.addArrangedSubview(button)
        }

        let note = NSTextField(wrappingLabelWithString: "The icon is hidden automatically whenever Ethernet is inactive.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)

        let stack = contentStack(views: [iconTitle, iconStack, separator(), speedCheckbox, loginCheckbox, note])
        item.view = wrappedView(containing: stack)
        return item
    }

    private func makeUpdatesTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "updates")
        item.label = "Updates"

        updatesCheckbox.target = self
        updatesCheckbox.action = #selector(updatesChanged)
        let checkButton = NSButton(title: "Check for Updates…", target: self, action: #selector(checkForUpdates))
        checkButton.bezelStyle = .rounded

        let stack = contentStack(views: [sectionTitle("Software Updates"), updatesCheckbox, checkButton])
        item.view = wrappedView(containing: stack)
        return item
    }

    private func makeAboutTab() -> NSTabViewItem {
        let item = NSTabViewItem(identifier: "about")
        item.label = "About"

        let name = NSTextField(labelWithString: "MacErnet")
        name.font = .systemFont(ofSize: 24, weight: .bold)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.3"
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.textColor = .secondaryLabelColor
        let credit = NSTextField(labelWithString: "Made by Agraja")
        credit.font = .systemFont(ofSize: 14, weight: .medium)
        let repositoryButton = NSButton(title: "View MacErnet on GitHub", target: self, action: #selector(openRepository))
        repositoryButton.bezelStyle = .rounded

        let stack = contentStack(views: [name, versionLabel, credit, repositoryButton])
        item.view = wrappedView(containing: stack)
        return item
    }

    private func contentStack(views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func wrappedView(containing stack: NSStackView) -> NSView {
        let view = NSView()
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 22)
        ])
        return view
    }

    private func sectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 400).isActive = true
        return box
    }

    private func syncFromDefaults() {
        speedCheckbox.state = UserDefaults.standard.bool(forKey: AppPreferences.showNetworkSpeed) ? .on : .off
        updatesCheckbox.state = UserDefaults.standard.bool(forKey: AppPreferences.checkForUpdatesAutomatically) ? .on : .off
        let selectedStyle = AppPreferences.selectedMenuBarIconStyle
        for (style, button) in iconButtons {
            button.state = style == selectedStyle ? .on : .off
        }
        if #available(macOS 13.0, *) {
            loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    @objc private func iconChanged(_ sender: NSButton) {
        guard let value = sender.identifier?.rawValue, let style = MenuBarIconStyle(rawValue: value) else { return }
        AppPreferences.selectedMenuBarIconStyle = style
        for (candidate, button) in iconButtons {
            button.state = candidate == style ? .on : .off
        }
        onIconPreferenceChange?()
    }

    @objc private func speedChanged() {
        UserDefaults.standard.set(speedCheckbox.state == .on, forKey: AppPreferences.showNetworkSpeed)
        onSpeedPreferenceChange?()
    }

    @objc private func updatesChanged() {
        UserDefaults.standard.set(updatesCheckbox.state == .on, forKey: AppPreferences.checkForUpdatesAutomatically)
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    @objc private func openRepository() {
        NSWorkspace.shared.open(URL(string: "https://github.com/agraja38/MacErnet")!)
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
