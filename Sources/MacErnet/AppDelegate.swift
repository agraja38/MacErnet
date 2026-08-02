import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let provider = SystemEthernetProvider()
    private lazy var ethernetMonitor = EthernetMonitor(provider: provider)
    private lazy var speedMonitor = NetworkSpeedMonitor(provider: provider)
    private lazy var preferencesWindow = PreferencesWindowController()
    private let updateService = UpdateService()
    private let wifiAutomation = WiFiAutomation(controller: SystemWiFiController())

    private var statusItem: NSStatusItem?
    private var connection: EthernetConnection?
    private var speed = NetworkSpeed.zero

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPreferences.registerDefaults()

        ethernetMonitor.onConnectionChange = { [weak self] connection in
            self?.applyConnection(connection)
        }
        speedMonitor.onSpeedChange = { [weak self] speed in
            self?.speed = speed
            self?.rebuildMenu()
        }
        preferencesWindow.onSpeedPreferenceChange = { [weak self] in
            self?.updateSpeedMonitoring()
            self?.rebuildMenu()
        }
        preferencesWindow.onIconPreferenceChange = { [weak self] in
            self?.updateStatusItemIcon()
        }
        preferencesWindow.onCheckForUpdates = { [weak self] in
            self?.updateService.checkForUpdates(userInitiated: true)
        }
        preferencesWindow.onWiFiPreferenceChange = { [weak self] in
            self?.applyWiFiAutomation(userInitiated: true)
        }

        ensureStatusItem()
        ethernetMonitor.start()

        if UserDefaults.standard.bool(forKey: AppPreferences.checkForUpdatesAutomatically) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.updateService.checkForUpdates(userInitiated: false)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ethernetMonitor.stop()
        speedMonitor.stop()
        try? wifiAutomation.restoreWiFiIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func menuWillOpen(_ menu: NSMenu) {
        ethernetMonitor.refresh()
        rebuildMenu()
    }

    private func applyConnection(_ newConnection: EthernetConnection?) {
        let interfaceChanged = connection?.interfaceName != newConnection?.interfaceName
        connection = newConnection
        applyWiFiAutomation(userInitiated: false)

        guard let newConnection else {
            speedMonitor.stop()
            speed = .zero
            statusItem?.isVisible = false
            return
        }

        ensureStatusItem()
        statusItem?.isVisible = true
        updateStatusItemIcon()
        if interfaceChanged {
            updateSpeedMonitoring(for: newConnection)
        }
        rebuildMenu()
    }

    private func ensureStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "MacErnetStatusItem"
        item.isVisible = false
        if let button = item.button {
            button.toolTip = "MacErnet — Ethernet connected"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateStatusItemIcon()
        rebuildMenu()
    }

    private func updateStatusItemIcon() {
        statusItem?.button?.image = MenuBarIconLibrary.image(for: AppPreferences.selectedMenuBarIconStyle)
        statusItem?.button?.imagePosition = .imageOnly
    }

    private func rebuildMenu() {
        guard let menu = statusItem?.menu, let connection else { return }
        menu.removeAllItems()

        menu.addItem(informationalItem(title: "Network: \(connection.networkName)", imageName: "network"))
        menu.addItem(informationalItem(title: "Adapter: \(connection.adapterDescription)", imageName: "cable.connector"))

        if UserDefaults.standard.bool(forKey: AppPreferences.showNetworkSpeed) {
            menu.addItem(.separator())
            menu.addItem(informationalItem(
                title: "Download: \(SpeedFormatter.string(bytesPerSecond: speed.downloadBytesPerSecond))",
                imageName: "arrow.down"
            ))
            menu.addItem(informationalItem(
                title: "Upload: \(SpeedFormatter.string(bytesPerSecond: speed.uploadBytesPerSecond))",
                imageName: "arrow.up"
            ))
        }

        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Open Network Settings…", action: #selector(openNetworkSettings), keyEquivalent: ","))
        menu.addItem(actionItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "s"))
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Quit MacErnet", action: #selector(quit), keyEquivalent: "q"))
    }

    private func informationalItem(title: String, imageName: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)
        item.isEnabled = false
        return item
    }

    private func actionItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func updateSpeedMonitoring(for explicitConnection: EthernetConnection? = nil) {
        guard UserDefaults.standard.bool(forKey: AppPreferences.showNetworkSpeed) else {
            speedMonitor.stop()
            speed = .zero
            return
        }
        guard let activeConnection = explicitConnection ?? connection else { return }
        speedMonitor.start(interfaceName: activeConnection.interfaceName)
    }

    private func applyWiFiAutomation(userInitiated: Bool) {
        do {
            try wifiAutomation.apply(
                ethernetConnected: connection != nil,
                enabled: UserDefaults.standard.bool(forKey: AppPreferences.turnOffWiFiWithEthernet)
            )
        } catch where userInitiated {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t Change Wi-Fi Power"
            alert.runModal()
        } catch {
            // A missing or temporarily unavailable Wi-Fi interface should not affect Ethernet monitoring.
        }
    }

    @objc private func openNetworkSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openSettings() {
        preferencesWindow.show()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
