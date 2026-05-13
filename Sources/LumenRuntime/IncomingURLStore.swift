import Foundation

/// Глобальная очередь incoming deep-link URLs.
///
/// `LumenApp.onOpenURL` → `enqueue(_:)` → стучимся в `NativeNotifier`
/// канал `linking.incoming`. JS-обёртка `lumen.linking.onIncoming.subscribe(fn)`
/// (см. CoreFramework) при срабатывании drain'ит pending URL'ы через
/// `lumen.linking._consumePending()` и вызывает callback'и.
///
/// Cold-start кейс: URL пришёл до того, как JS-bundle загрузился и подписался —
/// очередь хранит URLs, при первой subscribe'е JS их вычитает.
@MainActor
final class IncomingURLStore {
    static let shared = IncomingURLStore()

    private var pending: [String] = []

    private init() {}

    func enqueue(_ url: String) {
        pending.append(url)
        NativeNotifier.shared.fire("linking.incoming")
    }

    func consume() -> [String] {
        let r = pending
        pending = []
        return r
    }
}
