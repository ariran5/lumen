import Foundation

/// Per-origin allowlist for the fast-app's outgoing network traffic.
/// Applied to `fetch`, `lumen.ws`, and redirects inside fetch.
///
/// Default-allow:
/// - same host as Origin + any subdomain + any port.
///   Example: app `https://acme.com` can reach `https://acme.com`,
///   `https://api.acme.com:8443`, `wss://stream.acme.com`.
///
/// Manifest extends via `connect: [...]`:
/// - `"foo.com"` — exactly this host (no subdomains).
/// - `"*.cdn.com"` — any subdomain of `cdn.com` (but not `cdn.com` itself).
///   Symmetric with CSP: explicit wildcard must be explicit.
/// - `"*"` — allow-all (logged as warning, shell UI warning to be added).
///
/// What we do NOT check here (separate blocks):
/// - HTTPS-only enforcement — Block 4.
/// - Mixed content (HTTPS app → HTTP target) — Block 4.
/// - Storage quota / rate limits — Block 5.
/// - PSL for subdomains (`*.co.uk` must not match through `*.uk`).
///   MVP treats all suffixes as valid; PSL is a follow-up.
struct NetworkPolicy: Sendable {
    let origin: Origin

    /// Exact hosts from manifest (without `*.` prefix).
    private let exactHosts: Set<String>

    /// Suffix patterns from manifest (for `*.foo.com` stored as `foo.com`).
    private let subdomainSuffixes: [String]

    /// True if manifest has `connect: ["*"]` — allow-all.
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

    /// Check before opening a connection. `lumen://` origin (built-in
    /// shell pages) — never restricted.
    func allows(url: URL) -> Bool {
        if origin.scheme == "lumen" { return true }

        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(), !host.isEmpty else {
            return false
        }

        // Supported network schemes. file://, data:, blob: and similar
        // are not allowed in fetch — separate capabilities if needed.
        guard ["http", "https", "ws", "wss"].contains(scheme) else {
            return false
        }

        // Implicit: own host + any subdomain, any port, any scheme.
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
    /// Default policy for a fresh OriginContext before manifest is loaded.
    /// Allows only own host — fetch before eval(bundle.script)
    /// shouldn't happen in theory, but default safe.
    static func initial(for origin: Origin) -> NetworkPolicy {
        NetworkPolicy(origin: origin, manifestConnect: nil)
    }
}

/// Per-task delegate for fetch. Bound to `URLSessionTask.delegate`
/// (iOS 15+) and blocks cross-origin redirects not in the allowlist.
///
/// Used on `URLSession.shared` via a task-scoped delegate to avoid
/// spawning per-origin URLSessions.
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
