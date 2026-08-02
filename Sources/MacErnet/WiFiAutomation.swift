import CoreWLAN
import Foundation

protocol WiFiControlling {
    var isPoweredOn: Bool? { get }
    func setPower(_ enabled: Bool) throws
}

enum WiFiControlError: LocalizedError {
    case interfaceUnavailable

    var errorDescription: String? {
        switch self {
        case .interfaceUnavailable:
            return "MacErnet could not find a Wi-Fi interface."
        }
    }
}

final class SystemWiFiController: WiFiControlling {
    private var interface: CWInterface? {
        CWWiFiClient.shared().interface()
    }

    var isPoweredOn: Bool? {
        interface?.powerOn()
    }

    func setPower(_ enabled: Bool) throws {
        guard let interface else { throw WiFiControlError.interfaceUnavailable }
        try interface.setPower(enabled)
    }
}

final class WiFiAutomation {
    private let controller: WiFiControlling
    private let defaults: UserDefaults

    init(controller: WiFiControlling, defaults: UserDefaults = .standard) {
        self.controller = controller
        self.defaults = defaults
    }

    func apply(ethernetConnected: Bool, enabled: Bool) throws {
        if ethernetConnected && enabled {
            guard let isPoweredOn = controller.isPoweredOn else {
                throw WiFiControlError.interfaceUnavailable
            }
            if isPoweredOn {
                try controller.setPower(false)
                defaults.set(true, forKey: AppPreferences.wifiDisabledByMacErnet)
            }
            return
        }

        try restoreWiFiIfNeeded()
    }

    func restoreWiFiIfNeeded() throws {
        guard defaults.bool(forKey: AppPreferences.wifiDisabledByMacErnet) else { return }
        try controller.setPower(true)
        defaults.set(false, forKey: AppPreferences.wifiDisabledByMacErnet)
    }
}
