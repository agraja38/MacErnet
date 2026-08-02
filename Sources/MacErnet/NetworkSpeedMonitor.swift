import Foundation

final class NetworkSpeedMonitor {
    private let provider: EthernetProviding
    private let queue = DispatchQueue(label: "com.agraja.macernet.speed-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var interfaceName: String?
    private var previousCounters: NetworkCounters?
    private var previousTimestamp: TimeInterval?

    var onSpeedChange: ((NetworkSpeed) -> Void)?

    init(provider: EthernetProviding) {
        self.provider = provider
    }

    func start(interfaceName: String) {
        stop()
        self.interfaceName = interfaceName
        previousCounters = nil
        previousTimestamp = nil

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1)
        timer.setEventHandler { [weak self] in self?.sample() }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        interfaceName = nil
        previousCounters = nil
        previousTimestamp = nil
        DispatchQueue.main.async { [weak self] in self?.onSpeedChange?(.zero) }
    }

    private func sample() {
        guard let interfaceName, let counters = provider.counters(for: interfaceName) else { return }
        let timestamp = ProcessInfo.processInfo.systemUptime
        defer {
            previousCounters = counters
            previousTimestamp = timestamp
        }

        guard
            let previousCounters,
            let previousTimestamp,
            timestamp > previousTimestamp
        else { return }

        let elapsed = timestamp - previousTimestamp
        let received = counterDelta(current: counters.bytesReceived, previous: previousCounters.bytesReceived)
        let sent = counterDelta(current: counters.bytesSent, previous: previousCounters.bytesSent)
        let speed = NetworkSpeed(
            downloadBytesPerSecond: Double(received) / elapsed,
            uploadBytesPerSecond: Double(sent) / elapsed
        )

        DispatchQueue.main.async { [weak self] in self?.onSpeedChange?(speed) }
    }

    private func counterDelta(current: UInt64, previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : current
    }
}
