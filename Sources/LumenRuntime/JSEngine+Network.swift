import Foundation
import JavaScriptCore
import Network

/// `lumen.network.{online, type}` — реактивный сигнал сетевого состояния.
///
/// `online` — bool, `type` — `'wifi' | 'cellular' | 'wired' | 'other' | 'none'`.
/// Источник — `NWPathMonitor`, обновления приходят на отдельной очереди
/// и диспатчатся обратно на main.
extension JSEngine {
    func installNetworkBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }

        // Initial — невозможно прочитать NWPathMonitor синхронно.
        // CoreFramework стартует с (online: true, type: 'unknown') — первый
        // pathUpdate (приходит сразу после .start) переопределит.
        lumen.setObject(true, forKeyedSubscript: "_networkOnlineInitial" as NSString)
        lumen.setObject("unknown", forKeyedSubscript: "_networkTypeInitial" as NSString)

        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.lumen.network.monitor")

        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let type = Self.classify(path: path, online: online)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.pushNetwork(online: online, type: type)
                }
            }
        }
        monitor.start(queue: queue)

        Self.networkAlive[ObjectIdentifier(self)] = NetworkHolder(monitor: monitor)
    }

    private func pushNetwork(online: Bool, type: String) {
        guard let lumen = context.objectForKeyedSubscript("lumen"),
              let updater = lumen.objectForKeyedSubscript("_updateNetwork"),
              !updater.isUndefined, !updater.isNull else { return }
        _ = updater.call(withArguments: [online, type])
    }

    nonisolated private static func classify(path: NWPath, online: Bool) -> String {
        if !online { return "none" }
        if path.usesInterfaceType(.wifi) { return "wifi" }
        if path.usesInterfaceType(.cellular) { return "cellular" }
        if path.usesInterfaceType(.wiredEthernet) { return "wired" }
        return "other"
    }

    @MainActor
    private static var networkAlive: [ObjectIdentifier: NetworkHolder] = [:]
}

@MainActor
private final class NetworkHolder {
    let monitor: NWPathMonitor
    init(monitor: NWPathMonitor) {
        self.monitor = monitor
    }
    deinit {
        monitor.cancel()
    }
}
