import Foundation

enum MenuBarIconStyle: String, CaseIterable {
    case wiredNetwork
    case macOSEthernet

    var title: String {
        switch self {
        case .wiredNetwork: return "Wired Network"
        case .macOSEthernet: return "macOS Ethernet"
        }
    }

    var resourceName: String {
        switch self {
        case .wiredNetwork: return "WiredNetwork"
        case .macOSEthernet: return "MacOSEthernet"
        }
    }
}

enum AppPreferences {
    static let showNetworkSpeed = "showNetworkSpeed"
    static let checkForUpdatesAutomatically = "checkForUpdatesAutomatically"
    static let launchAtLogin = "launchAtLogin"
    static let menuBarIconStyle = "menuBarIconStyle"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showNetworkSpeed: true,
            checkForUpdatesAutomatically: true,
            launchAtLogin: false,
            menuBarIconStyle: MenuBarIconStyle.macOSEthernet.rawValue
        ])
    }

    static var selectedMenuBarIconStyle: MenuBarIconStyle {
        get {
            let value = UserDefaults.standard.string(forKey: menuBarIconStyle)
            return MenuBarIconStyle(rawValue: value ?? "") ?? .macOSEthernet
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: menuBarIconStyle)
        }
    }
}
