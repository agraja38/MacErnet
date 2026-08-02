import Darwin
import Foundation
import SystemConfiguration

protocol EthernetProviding {
    func activeConnection() -> EthernetConnection?
    func counters(for interfaceName: String) -> NetworkCounters?
}

final class SystemEthernetProvider: EthernetProviding {
    private struct InterfaceSnapshot {
        var hasIPv4Address = false
        var isRunning = false
        var counters: NetworkCounters?
    }

    func activeConnection() -> EthernetConnection? {
        let snapshots = interfaceSnapshots()
        let services = networkServices()

        for interface in ethernetInterfaces() {
            guard
                let bsdName = SCNetworkInterfaceGetBSDName(interface) as String?,
                let snapshot = snapshots[bsdName],
                snapshot.isRunning,
                snapshot.hasIPv4Address
            else { continue }

            let localizedName = (SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?) ?? "Ethernet"
            let serviceName = services[bsdName] ?? "Ethernet"

            return EthernetConnection(
                interfaceName: bsdName,
                networkName: serviceName,
                adapterName: localizedName
            )
        }

        return nil
    }

    func counters(for interfaceName: String) -> NetworkCounters? {
        interfaceSnapshots()[interfaceName]?.counters
    }

    private func ethernetInterfaces() -> [SCNetworkInterface] {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [] }
        return interfaces.filter { interface in
            guard let type = SCNetworkInterfaceGetInterfaceType(interface) as String? else { return false }
            return type == (kSCNetworkInterfaceTypeEthernet as String)
        }
    }

    private func networkServices() -> [String: String] {
        guard
            let preferences = SCPreferencesCreate(nil, "MacErnet" as CFString, nil),
            let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService]
        else { return [:] }

        var names: [String: String] = [:]
        for service in services where SCNetworkServiceGetEnabled(service) {
            guard
                let interface = SCNetworkServiceGetInterface(service),
                let bsdName = SCNetworkInterfaceGetBSDName(interface) as String?,
                let serviceName = SCNetworkServiceGetName(service) as String?
            else { continue }
            names[bsdName] = serviceName
        }
        return names
    }

    private func interfaceSnapshots() -> [String: InterfaceSnapshot] {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let firstAddress = addressList else { return [:] }
        defer { freeifaddrs(addressList) }

        var snapshots: [String: InterfaceSnapshot] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let current = pointer {
            let interface = current.pointee
            let name = String(cString: interface.ifa_name)
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if !isLoopback {
                var snapshot = snapshots[name] ?? InterfaceSnapshot()
                snapshot.isRunning = snapshot.isRunning || (isUp && isRunning)

                if let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) {
                    let socketAddress = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee
                    snapshot.hasIPv4Address = snapshot.hasIPv4Address || socketAddress.sin_addr.s_addr != INADDR_ANY
                }

                if let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    snapshot.counters = NetworkCounters(
                        bytesReceived: UInt64(data.pointee.ifi_ibytes),
                        bytesSent: UInt64(data.pointee.ifi_obytes)
                    )
                }

                snapshots[name] = snapshot
            }

            pointer = interface.ifa_next
        }

        return snapshots
    }
}
