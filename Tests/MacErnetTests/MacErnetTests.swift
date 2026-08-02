import XCTest
@testable import MacErnet

final class MacErnetTests: XCTestCase {
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
}
