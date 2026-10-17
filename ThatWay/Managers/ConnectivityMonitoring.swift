//
//  ConnectivityMonitoring.swift
//  ThatWay
//
//  Lets the routing governor tell "offline" apart from "the server is having a bad day" —
//  mocked in tests so offline/online transitions are deterministic instead of waiting on
//  real network hardware.
//

import Network

protocol ConnectivityMonitoring: AnyObject {
    var isConnected: Bool { get }
    /// Called whenever connectivity flips, including online -> online-again after a blip.
    var onChange: ((Bool) -> Void)? { get set }
}

/// Real, `NWPathMonitor`-backed implementation used in production.
final class NetworkConnectivityMonitor: ConnectivityMonitoring {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.thatway.connectivity")
    private(set) var isConnected = true
    var onChange: ((Bool) -> Void)?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                guard self.isConnected != connected else { return }
                self.isConnected = connected
                self.onChange?(connected)
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
