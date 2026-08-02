import Foundation

enum AppPreferences {
    static let showNetworkSpeed = "showNetworkSpeed"
    static let checkForUpdatesAutomatically = "checkForUpdatesAutomatically"
    static let launchAtLogin = "launchAtLogin"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showNetworkSpeed: true,
            checkForUpdatesAutomatically: true,
            launchAtLogin: false
        ])
    }
}
