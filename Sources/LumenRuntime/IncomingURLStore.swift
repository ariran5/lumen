import Foundation

/// Global queue of incoming deep-link URLs.
///
/// `LumenApp.onOpenURL` → `enqueue(_:)` → pings `NativeNotifier`
/// channel `linking.incoming`. JS wrapper `lumen.linking.onIncoming.subscribe(fn)`
/// (see CoreFramework) on fire drains pending URLs via
/// `lumen.linking._consumePending()` and invokes callbacks.
///
/// Cold-start case: URL arrived before JS bundle loaded and subscribed —
/// queue holds URLs, JS reads them on first subscribe.
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
