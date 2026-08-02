import Foundation

final class EthernetMonitor {
    typealias Handler = (EthernetConnection?) -> Void

    private let provider: EthernetProviding
    private let queue = DispatchQueue(label: "com.agraja.macernet.ethernet-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastConnection: EthernetConnection?
    private var hasReported = false

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
        guard force || !hasReported || connection != lastConnection else { return }
        hasReported = true
        lastConnection = connection
        DispatchQueue.main.async { [weak self] in
            self?.onConnectionChange?(connection)
        }
    }
}
