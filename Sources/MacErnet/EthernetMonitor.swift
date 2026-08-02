import Foundation

enum EthernetConnectionUpdate: Equatable {
    case unchanged
    case changed(EthernetConnection?)
}

struct EthernetConnectionDebouncer {
    private let requiredMissingSamples: Int
    private var lastConnection: EthernetConnection?
    private var hasReported = false
    private var missingSamples = 0

    init(requiredMissingSamples: Int = 3) {
        self.requiredMissingSamples = max(1, requiredMissingSamples)
    }

    mutating func receive(_ connection: EthernetConnection?, force: Bool = false) -> EthernetConnectionUpdate {
        if let connection {
            missingSamples = 0
            guard force || !hasReported || connection != lastConnection else { return .unchanged }
            hasReported = true
            lastConnection = connection
            return .changed(connection)
        }

        missingSamples += 1
        guard missingSamples >= requiredMissingSamples else { return .unchanged }
        guard !hasReported || lastConnection != nil else { return .unchanged }
        hasReported = true
        lastConnection = nil
        return .changed(nil)
    }
}

final class EthernetMonitor {
    typealias Handler = (EthernetConnection?) -> Void

    private let provider: EthernetProviding
    private let queue = DispatchQueue(label: "com.agraja.macernet.ethernet-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var debouncer = EthernetConnectionDebouncer()

    var onConnectionChange: Handler?

    init(provider: EthernetProviding) {
        self.provider = provider
    }

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 2)
        timer.setEventHandler { [weak self] in self?.poll() }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func refresh() {
        queue.async { [weak self] in self?.poll(force: true) }
    }

    private func poll(force: Bool = false) {
        let connection = provider.activeConnection()
        guard case let .changed(updatedConnection) = debouncer.receive(connection, force: force) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onConnectionChange?(updatedConnection)
        }
    }
}
