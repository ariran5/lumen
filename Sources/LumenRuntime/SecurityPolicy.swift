import Foundation

/// HTTPS-only gate for fast-app loading. Block 4 of Sandbox roadmap.
///
/// Reasoning: cleartext HTTP can't be trusted for content (MITM can
/// swap the bundle), and a fast-app gets access to platform APIs after
/// permission grant — that's stronger than web with CSP. Hence HTTPS-only.
///
/// Exceptions for local dev: `localhost`, `127.0.0.1`, `*.local`,
/// RFC1918 private nets (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`)
/// — without them iPhone-to-Mac on the same wifi can't reach the dev server.
///
/// Developer Mode flag (`UserDefaults.lumen.developerMode`) fully
/// disables the gate — for debugging preview domains with self-signed
/// certificates or temporary tunnels (ngrok usually wraps in https,
/// so it's a rare need).
enum SecurityPolicy {

    /// Schemes we treat as a "secure channel". Everything else
    /// must pass `isHostLocal` or Developer Mode.
    private static let secureSchemes: Set<String> = ["https", "lumen"]

    /// Check before `BundleLoader.load`. Returns nil if URL is ok,
    /// otherwise reasons that fall into the error so the shell shows the user
    /// why "it didn't load".
    static func denyReason(forBundleURL url: URL) -> String? {
        if let scheme = url.scheme?.lowercased(), secureSchemes.contains(scheme) {
            return nil
        }
        // http remains — allowed if local or Dev Mode.
        if isDeveloperMode { return nil }
        if let host = url.host, isHostLocal(host) { return nil }
        return "insecure scheme — fast-apps must be HTTPS (or local dev / Developer Mode)"
    }

    static var isDeveloperMode: Bool {
        get { UserDefaults.standard.bool(forKey: developerModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: developerModeKey) }
    }
    private static let developerModeKey = "lumen.developerMode"

    /// `localhost`, `127.x`, `*.local` (mDNS/Bonjour), RFC1918 private nets.
    /// LAN addresses like `192.168.x.x` / `10.x.x.x` also fall here, which
    /// we use to test from iPhone to laptop on the same wifi.
    static func isHostLocal(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" { return true }
        if h.hasSuffix(".local") { return true }
        return isPrivateIPv4(h)
    }

    /// Checks RFC1918 + loopback. IPv6 not yet covered — low risk
    /// (dev on link-local IPv6 is rare).
    private static func isPrivateIPv4(_ host: String) -> Bool {
        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        // 127.0.0.0/8 (loopback)
        if octets[0] == 127 { return true }
        // 10.0.0.0/8
        if octets[0] == 10 { return true }
        // 172.16.0.0/12
        if octets[0] == 172, (16...31).contains(octets[1]) { return true }
        // 192.168.0.0/16
        if octets[0] == 192, octets[1] == 168 { return true }
        return false
    }
}
