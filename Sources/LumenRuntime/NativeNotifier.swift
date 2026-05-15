import Foundation

/// Push channel from Swift to JS. Any native store (HistoryStore, TabsStore, ...)
/// after mutation calls `NativeNotifier.shared.fire("history")`, and all
/// registered JS callbacks across all live JSEngines get invoked.
///
/// This is the backbone of native-side reactivity: source-of-truth lives in Swift,
/// JS subscribes via `lumen._notify.subscribe(channel, fn)` (see
/// `JSEngine+Notify.swift`). On the JS side callback typically does
/// `signal.value = lumen.X.list()` — and Vapor effects re-render
/// specific slots.
@MainActor
final class NativeNotifier {
    static let shared = NativeNotifier()

    private var engines: [WeakEngine] = []

    private init() {}

    func register(_ engine: JSEngine) {
        cleanup()
        engines.append(WeakEngine(engine))
    }

    func fire(_ channel: String) {
        cleanup()
        for w in engines {
            w.engine?.dispatchNotify(channel: channel)
        }
    }

    private func cleanup() {
        engines.removeAll { $0.engine == nil }
    }
}

@MainActor
private final class WeakEngine {
    weak var engine: JSEngine?
    init(_ e: JSEngine) { self.engine = e }
}
