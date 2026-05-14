import Foundation

/// Per-origin allowlist для исходящего сетевого трафика fast-app'а.
/// Применяется к `fetch`, `lumen.ws`, и редиректам внутри fetch'а.
///
/// Default-allow:
/// - тот же host что у Origin'а + любые поддомены + любой порт.
///   Пример: app `https://acme.com` может ходить на `https://acme.com`,
///   `https://api.acme.com:8443`, `wss://stream.acme.com`.
///
/// Manifest extends через `connect: [...]`:
/// - `"foo.com"` — ровно этот host (без поддоменов).
/// - `"*.cdn.com"` — любой поддомен `cdn.com` (но не сам `cdn.com`).
///   Симметрично с CSP: explicit wildcard нужен явно.
/// - `"*"` — allow-all (логируется как warning, UI-warning в shell'е добавим).
///
/// Что НЕ проверяем здесь (отдельные блоки):
/// - HTTPS-only enforcement — Block 4.
/// - Mixed content (HTTPS app → HTTP target) — Block 4.
/// - Storage quota / rate limits — Block 5.
/// - PSL для поддоменов (`*.co.uk` не должен матчиться через `*.uk`).
///   MVP считает все суффиксы валидными; PSL — followup.
struct NetworkPolicy: Sendable {
    let origin: Origin

    /// Точные hosts из манифеста (без `*.` префикса).
    private let exactHosts: Set<String>

    /// Suffix-патерны из манифеста (для `*.foo.com` хранится `foo.com`).
    private let subdomainSuffixes: [String]

    /// True если в манифесте `connect: ["*"]` — allow-all.
    let allowAll: Bool

    init(origin: Origin, manifestConnect: [String]?) {
        self.origin = origin
        let entries = (manifestConnect ?? []).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        self.allowAll = entries.contains("*")
        var exact = Set<String>()
        var suffixes = [String]()
        for entry in entries where !entry.isEmpty && entry != "*" {
            if entry.hasPrefix("*.") {
                suffixes.append(String(entry.dropFirst(2)))
            } else {
                exact.insert(entry)
            }
        }
        self.exactHosts = exact
        self.subdomainSuffixes = suffixes
    }

    /// Проверка перед открытием соединения. `lumen://` origin (встроенные
    /// страницы shell'а) — никогда не ограничен.
    func allows(url: URL) -> Bool {
        if origin.scheme == "lumen" { return true }

        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(), !host.isEmpty else {
            return false
        }

        // Поддерживаемые сетевые схемы. file://, data:, blob: и прочее
        // в fetch не пускаем — отдельные капабилити при необходимости.
        guard ["http", "https", "ws", "wss"].contains(scheme) else {
            return false
        }

        // Implicit: own host + любые поддомены, любой порт, любая схема.
        if hostEqualsOrIsSubdomain(host: host, of: origin.host) {
            return true
        }

        if allowAll { return true }

        if exactHosts.contains(host) { return true }

        for suffix in subdomainSuffixes {
            if host.hasSuffix("." + suffix) { return true }
        }

        return false
    }

    private func hostEqualsOrIsSubdomain(host: String, of parent: String) -> Bool {
        if host == parent { return true }
        return host.hasSuffix("." + parent)
    }
}

extension NetworkPolicy {
    /// Default policy для свежего OriginContext'а до загрузки манифеста.
    /// Разрешает только собственный host — fetch до eval(bundle.script)
    /// теоретически не должен случаться, но default safe.
    static func initial(for origin: Origin) -> NetworkPolicy {
        NetworkPolicy(origin: origin, manifestConnect: nil)
    }
}

/// Per-task delegate для fetch'а. Привязывается к `URLSessionTask.delegate`
/// (iOS 15+) и блокирует cross-origin редиректы которые не входят в allowlist.
///
/// Используется на `URLSession.shared` через task-scoped delegate, чтобы не
/// плодить per-origin URLSession'ы.
final class NetworkRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let policy: NetworkPolicy

    init(policy: NetworkPolicy) {
        self.policy = policy
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, policy.allows(url: url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
