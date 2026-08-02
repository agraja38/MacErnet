import Foundation

struct EthernetConnection: Equatable {
    let interfaceName: String
    let networkName: String
    let adapterName: String

    var adapterDescription: String {
        "\(adapterName) (\(interfaceName))"
    }
}

struct NetworkCounters: Equatable {
    let bytesReceived: UInt64
    let bytesSent: UInt64
}

struct NetworkSpeed: Equatable {
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double

    static let zero = NetworkSpeed(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
}

enum SpeedFormatter {
    static func string(bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .decimal
        formatter.includesUnit = true
        formatter.isAdaptive = true
        let safeValue = max(0, min(bytesPerSecond, Double(Int64.max)))
        return formatter.string(fromByteCount: Int64(safeValue)) + "/s"
    }
}

enum VersionComparator {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }
}
