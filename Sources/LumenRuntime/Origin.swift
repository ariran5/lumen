import Foundation
import CryptoKit

/// Web-style origin: scheme + host + port. Base unit of isolation
/// between fast-apps. Two URLs with the same Origin are one app:
/// they share storage, permissions, FS root. Different Origins — full
/// isolation, like different sites in a browser.
///
/// Port is normalized: default (443 for https, 80 for http) → nil,
/// so `https://acme.com` and `https://acme.com:443` are considered one
/// origin.
///
/// Special origins:
/// - `lumen://host/...` → scheme=lumen, host=host, port=nil — for built-in
///   shell pages (home, settings, history). Each lumen-host is its own origin.
/// - `Origin.system` — for cases when origin is unknown (loading before init bundle).
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

    /// Fallback origin for built-in shell contexts without URL.
    static let system = Origin(scheme: "lumen", host: "system", port: nil)

    var description: String {
        if let port { return "\(scheme)://\(host):\(port)" }
        return "\(scheme)://\(host)"
    }

    /// Stable short hash (12 hex chars from SHA-256), safe for filesystem
    /// paths, UserDefaults keys, Keychain service identifiers.
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
