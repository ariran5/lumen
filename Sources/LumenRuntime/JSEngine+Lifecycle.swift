import Foundation
import JavaScriptCore
import UIKit

/// `lumen.appState` — reactive signal of app lifecycle.
/// Values: `'active' | 'inactive' | 'background'`.
///
/// CoreFramework wraps it as a signal — accessing `lumen.appState` from
/// a thunk prop makes the node a subscriber, and the fast-app re-renders
/// on entering/leaving background.
extension JSEngine {
    func installLifecycleBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }

        lumen.setObject(Self.currentAppState(), forKeyedSubscript: "_appStateInitial" as NSString)

        let holder = LifecycleObservers()
        let nc = NotificationCenter.default

        let push: @MainActor (String) -> Void = { [weak self] state in
            self?.pushAppState(state)
        }

        holder.tokens.append(nc.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { push("active") }
        })
        holder.tokens.append(nc.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { push("inactive") }
        })
        holder.tokens.append(nc.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { push("background") }
        })

        Self.lifecycleAlive[ObjectIdentifier(self)] = holder
    }

    private func pushAppState(_ state: String) {
        guard let lumen = context.objectForKeyedSubscript("lumen"),
              let updater = lumen.objectForKeyedSubscript("_updateAppState"),
              !updater.isUndefined, !updater.isNull else { return }
        _ = updater.call(withArguments: [state])
    }

    private static func currentAppState() -> String {
        switch UIApplication.shared.applicationState {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "active"
        }
    }

    @MainActor
    private static var lifecycleAlive: [ObjectIdentifier: LifecycleObservers] = [:]
}

// JSEngine lives till process end; observers can validly be held without explicit
// removeObserver. No deinit — Swift 6 strict concurrency won't allow
// non-Sendable [NSObjectProtocol] from a non-isolated deinit, and hacking
// `@unchecked Sendable` just for a perfect tear-down isn't worth it.
@MainActor
private final class LifecycleObservers {
    var tokens: [NSObjectProtocol] = []
}
