import Foundation

/// Per-origin контекст: разделяемое persistent-состояние всех таб одного
/// сайта. Один app в двух табах — один OriginContext. Закрытие таб'ы
/// не убивает контекст, пока ссылка хотя бы из одного engine'а живёт.
///
/// Сейчас держит namespace-префиксы для storage / Keychain / FS. Дальше
/// сюда же сложатся permission-grants, manifest hashes, quota tracking.
///
/// Получать через `OriginContextRegistry.shared.context(for: origin)` —
/// дедуплицирует по Origin, чтобы две табы одного сайта шарили
/// permission-решения и storage пространство.
@MainActor
final class OriginContext {
    let origin: Origin

    init(origin: Origin) {
        self.origin = origin
    }

    /// UserDefaults-префикс. `lumen.storage.<hash>.<userkey>` — старые
    /// глобальные ключи `lumen.storage.<key>` после миграции более не видны.
    var storagePrefix: String {
        "lumen.storage.\(origin.shortHash)."
    }

    /// Keychain service identifier. Все entries app'а живут под одним
    /// service'ом — `SecItemDelete` по service'у = wipe'нуть весь secure
    /// state app'а одним вызовом.
    var keychainService: String {
        "com.lumen.secureStorage.\(origin.shortHash)"
    }

    /// Корень FS-песочницы app'а под Documents/. Бридги (imagePicker,
    /// documentPicker, ...) кладут свои tmp-файлы внутрь.
    var documentsRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("apps", isDirectory: true)
            .appendingPathComponent(origin.shortHash, isDirectory: true)
    }

    /// Tmp-корень. Можно очищать целиком при logout / clear-site-data
    /// без потери persistent-данных.
    var tmpRoot: URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("apps", isDirectory: true)
            .appendingPathComponent(origin.shortHash, isDirectory: true)
    }
}

/// Singleton registry, дедуплицирует OriginContext по Origin. Две табы
/// одного сайта получают один и тот же контекст — permission-грант в
/// одной видно во второй.
@MainActor
final class OriginContextRegistry {
    static let shared = OriginContextRegistry()

    private var contexts: [Origin: OriginContext] = [:]

    func context(for origin: Origin) -> OriginContext {
        if let existing = contexts[origin] { return existing }
        let fresh = OriginContext(origin: origin)
        contexts[origin] = fresh
        return fresh
    }
}
