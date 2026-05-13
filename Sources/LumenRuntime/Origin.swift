import Foundation
import CryptoKit

/// Web-style origin: scheme + host + port. Базовая единица изоляции
/// между fast-app'ами. Два URL с одинаковым Origin'ом — это один app:
/// они шарят storage, permissions, FS-корень. Разные Origin — полная
/// изоляция, как разные сайты в браузере.
///
/// Порт нормализуется: дефолтный (443 для https, 80 для http) → nil,
/// чтобы `https://acme.com` и `https://acme.com:443` считались одним
/// origin'ом.
///
/// Спец-origin'ы:
/// - `lumen://host/...` → scheme=lumen, host=host, port=nil — для встроенных
///   shell-страниц (home, settings, history). Каждый lumen-host — свой origin.
/// - `Origin.system` — для cases когда origin неизвестен (загрузка до init bundle'а).
struct Origin: Hashable, Sendable, CustomStringConvertible {
    let scheme: String
    let host: String
    let port: Int?

    init(scheme: String, host: String, port: Int? = nil) {
        self.scheme = scheme.lowercased()
        self.host = host.lowercased()
        self.port = Self.normalizePort(port, scheme: self.scheme)
    }

    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty else { return nil }
        self.scheme = scheme
        self.host = host
        self.port = Self.normalizePort(url.port, scheme: scheme)
    }

    /// Fallback origin для built-in shell-контекстов без URL.
    static let system = Origin(scheme: "lumen", host: "system", port: nil)

    var description: String {
        if let port { return "\(scheme)://\(host):\(port)" }
        return "\(scheme)://\(host)"
    }

    /// Stable short hash (12 hex chars from SHA-256), safe для filesystem
    /// path'ов, UserDefaults-ключей, Keychain service identifiers.
    var shortHash: String {
        let canonical = description
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizePort(_ port: Int?, scheme: String) -> Int? {
        guard let port else { return nil }
        if scheme == "https", port == 443 { return nil }
        if scheme == "http", port == 80 { return nil }
        if scheme == "wss", port == 443 { return nil }
        if scheme == "ws", port == 80 { return nil }
        return port
    }
}
