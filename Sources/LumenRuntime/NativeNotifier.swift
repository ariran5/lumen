import Foundation

/// Push-канал из Swift в JS. Любой native-store (HistoryStore, TabsStore, ...)
/// после мутации делает `NativeNotifier.shared.fire("history")`, и все
/// зарегистрированные JS-callback'и во всех живых JSEngine получают вызов.
///
/// Это бэкбон native-side реактивности: source-of-truth живёт в Swift,
/// JS подписывается через `lumen._notify.subscribe(channel, fn)` (см.
/// `JSEngine+Notify.swift`). На JS-стороне callback обычно делает
/// `signal.value = lumen.X.list()` — и Vapor effect'ы перерисовывают
/// конкретные слоты.
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
