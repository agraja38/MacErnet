import XCTest
@testable import MacErnet

final class MacErnetTests: XCTestCase {
    private final class FakeWiFiController: WiFiControlling {
        var isPoweredOn: Bool?
        var powerChanges: [Bool] = []

        init(isPoweredOn: Bool) {
            self.isPoweredOn = isPoweredOn
        }

        func setPower(_ enabled: Bool) throws {
            isPoweredOn = enabled
            powerChanges.append(enabled)
        }
    }

    func testVersionComparisonUsesNumericOrdering() {
        XCTAssertTrue(VersionComparator.isNewer("1.0.10", than: "1.0.9"))
        XCTAssertTrue(VersionComparator.isNewer("2.0.0", than: "1.9.9"))
        XCTAssertFalse(VersionComparator.isNewer("1.0.0", than: "1.0.0"))
        XCTAssertFalse(VersionComparator.isNewer("1.0.0", than: "1.0.1"))
    }

    func testAdapterDescriptionIncludesBSDName() {
        let connection = EthernetConnection(
            interfaceName: "en5",
            networkName: "USB Ethernet",
            adapterName: "AX88179A"
        )
        XCTAssertEqual(connection.adapterDescription, "AX88179A (en5)")
    }

    func testSpeedFormatterNeverDisplaysNegativeValues() {
        XCTAssertEqual(
            SpeedFormatter.string(bytesPerSecond: -100),
            SpeedFormatter.string(bytesPerSecond: 0)
        )
    }

    func testMenuBarOffersExactlyTwoIconStyles() {
        XCTAssertEqual(MenuBarIconStyle.allCases.count, 2)
        XCTAssertEqual(Set(MenuBarIconStyle.allCases.map(\.resourceName)), ["WiredNetwork", "MacOSEthernet"])
    }

    func testUpdateInstallerReplacesAppAndTerminatesOldProcess() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceApp = root.appendingPathComponent("Source/MacErnet.app", isDirectory: true)
        let targetApp = root.appendingPathComponent("Target/MacErnet.app", isDirectory: true)
        let scriptURL = root.appendingPathComponent("update.sh")
        let diskImageURL = root.appendingPathComponent("update.dmg")
        try fileManager.createDirectory(at: sourceApp, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: targetApp, withIntermediateDirectories: true)
        try "new".write(to: sourceApp.appendingPathComponent("version.txt"), atomically: true, encoding: .utf8)
        try "old".write(to: targetApp.appendingPathComponent("version.txt"), atomically: true, encoding: .utf8)
        try Data().write(to: diskImageURL)
        try UpdateInstallerScript.contents.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let oldProcess = Process()
        oldProcess.executableURL = URL(fileURLWithPath: "/bin/sleep")
        oldProcess.arguments = ["60"]
        try oldProcess.run()

        let installer = Process()
        installer.executableURL = URL(fileURLWithPath: "/bin/zsh")
        installer.arguments = [
            scriptURL.path,
            sourceApp.path,
            targetApp.path,
            root.path,
            diskImageURL.path,
            String(oldProcess.processIdentifier)
        ]
        installer.environment = ProcessInfo.processInfo.environment.merging(["MACERNET_UPDATE_TESTING": "1"]) { _, new in new }
        try installer.run()
        installer.waitUntilExit()
        oldProcess.waitUntilExit()

        XCTAssertEqual(installer.terminationStatus, 0)
        XCTAssertFalse(oldProcess.isRunning)
        XCTAssertEqual(
            try String(contentsOf: targetApp.appendingPathComponent("version.txt"), encoding: .utf8),
            "new"
        )
        XCTAssertFalse(fileManager.fileExists(atPath: targetApp.appendingPathExtension("previous").path))
        XCTAssertFalse(fileManager.fileExists(atPath: diskImageURL.path))
        try? fileManager.removeItem(at: root)
    }

    func testTransientMissingEthernetSamplesDoNotHideIcon() {
        let ethernet = EthernetConnection(interfaceName: "en5", networkName: "LAN", adapterName: "Ethernet")
        var debouncer = EthernetConnectionDebouncer(requiredMissingSamples: 3)

        XCTAssertEqual(debouncer.receive(ethernet), .changed(ethernet))
        XCTAssertEqual(debouncer.receive(nil), .unchanged)
        XCTAssertEqual(debouncer.receive(nil), .unchanged)
        XCTAssertEqual(debouncer.receive(ethernet), .unchanged)
        XCTAssertEqual(debouncer.receive(nil), .unchanged)
        XCTAssertEqual(debouncer.receive(nil), .unchanged)
        XCTAssertEqual(debouncer.receive(nil), .changed(nil))
    }

    func testWiFiAutomationRestoresOnlyWiFiItDisabled() throws {
        let suiteName = "MacErnetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = FakeWiFiController(isPoweredOn: true)
        let automation = WiFiAutomation(controller: controller, defaults: defaults)

        try automation.apply(ethernetConnected: true, enabled: true)
        XCTAssertEqual(controller.powerChanges, [false])
        XCTAssertTrue(defaults.bool(forKey: AppPreferences.wifiDisabledByMacErnet))

        try automation.apply(ethernetConnected: false, enabled: true)
        XCTAssertEqual(controller.powerChanges, [false, true])
        XCTAssertFalse(defaults.bool(forKey: AppPreferences.wifiDisabledByMacErnet))
    }

    func testWiFiAutomationLeavesPreexistingOffStateAlone() throws {
        let suiteName = "MacErnetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = FakeWiFiController(isPoweredOn: false)
        let automation = WiFiAutomation(controller: controller, defaults: defaults)

        try automation.apply(ethernetConnected: true, enabled: true)
        try automation.apply(ethernetConnected: false, enabled: true)
        XCTAssertTrue(controller.powerChanges.isEmpty)
    }
}
