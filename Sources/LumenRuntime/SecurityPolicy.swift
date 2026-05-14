import Foundation

/// HTTPS-only gate для fast-app загрузки. Block 4 of Sandbox roadmap.
///
/// Reasoning: cleartext HTTP'у нельзя доверять content (MITM может
/// подменить bundle), а fast-app получает доступ к platform API'ям после
/// permission grant — это сильнее чем web с CSP. Поэтому HTTPS-only.
///
/// Исключения для local dev: `localhost`, `127.0.0.1`, `*.local`,
/// RFC1918 private nets (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`)
/// — без них iPhone-к-Mac на одной wifi не подключится к dev-server'у.
///
/// Developer Mode флаг (`UserDefaults.lumen.developerMode`) полностью
/// отключает gate — для отладки preview-доменов с самоподписанными
/// сертификатами или временных tunnel'ов (ngrok'и обычно https'ом
/// прикрываются, поэтому редкая нужда).
enum SecurityPolicy {

    /// Schemes которые мы рассматриваем как «безопасный канал». Всё
    /// остальное должно пройти через `isHostLocal` либо Developer Mode.
    private static let secureSchemes: Set<String> = ["https", "lumen"]

    /// Проверка перед `BundleLoader.load`. Возвращает nil если URL ok,
    /// иначе reason'ы которые упадут в error чтобы шелл показал юзеру
    /// причину «почему не загрузилось».
    static func denyReason(forBundleURL url: URL) -> String? {
        if let scheme = url.scheme?.lowercased(), secureSchemes.contains(scheme) {
            return nil
        }
        // http остался — допустимо если local либо Dev Mode.
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
    /// Сюда же попадают типичные dev-IP вида `192.168.0.107` с которыми
    /// тестим с iPhone на ноутбук в той же wifi.
    static func isHostLocal(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" { return true }
        if h.hasSuffix(".local") { return true }
        return isPrivateIPv4(h)
    }

    /// Проверяет RFC1918 + loopback. IPv6 пока не покрываем — рисков
    /// мало (dev на link-local IPv6 редкость).
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
