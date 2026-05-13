import Foundation
import JavaScriptCore
import UIKit

/// `lumen.appState` — реактивный сигнал жизненного цикла приложения.
/// Значения: `'active' | 'inactive' | 'background'`.
///
/// CoreFramework заворачивает в signal — обращение `lumen.appState` из
/// thunk-prop'а делает узел подписчиком, и фастапп перерисуется при
/// заходе в фон / выходе из фона.
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

// JSEngine живёт до конца процесса; observer'ы валидно держать без явного
// removeObserver. Не делаем deinit — Swift 6 strict concurrency не пускает
// non-Sendable [NSObjectProtocol] из non-isolated deinit, а городить
// `@unchecked Sendable` ради идеального тира-дауна не оправдано.
@MainActor
private final class LifecycleObservers {
    var tokens: [NSObjectProtocol] = []
}
