import Foundation

struct LumenManifest: Decodable, Sendable {
    let name: String
    let version: String
    let entry: String
    let minRuntime: String?
    let dev: Bool?

    enum CodingKeys: String, CodingKey {
        case name, version, entry, dev
        case minRuntime = "min_runtime"
    }
}

struct LumenBundle: Sendable {
    let manifest: LumenManifest
    let script: String
    let origin: URL
}

enum BundleLoadError: LocalizedError {
    case invalidRoot
    case manifestUnavailable(URLResponse?)
    case manifestUnparseable(Error)
    case entryUnavailable(URLResponse?)
    case entryUndecodable

    var errorDescription: String? {
        switch self {
        case .invalidRoot: "invalid root URL"
        case .manifestUnavailable(let r): "manifest fetch failed — \(httpStatus(r))"
        case .manifestUnparseable(let e): "manifest JSON invalid — \(e.localizedDescription)"
        case .entryUnavailable(let r): "entry script fetch failed — \(httpStatus(r))"
        case .entryUndecodable: "entry script is not UTF-8"
        }
    }

    private func httpStatus(_ r: URLResponse?) -> String {
        if let http = r as? HTTPURLResponse { return "HTTP \(http.statusCode)" }
        return "no response"
    }
}

enum BundleProbe: Sendable, Equatable {
    case fastApp
    case web
}

/// Per-host TTL-кэш probe-результата. Чтобы не дёргать `/.well-known/lumen.json`
/// при каждом visit известного хоста.
@MainActor
final class BundleProbeCache {
    static let shared = BundleProbeCache()

    private struct Entry {
        let result: BundleProbe
        let timestamp: Date
    }

    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval = 86_400  // 24 часа

    func get(host: String) -> BundleProbe? {
        guard let entry = entries[host],
              Date().timeIntervalSince(entry.timestamp) < ttl else {
            return nil
        }
        return entry.result
    }

    func set(host: String, _ result: BundleProbe) {
        entries[host] = Entry(result: result, timestamp: Date())
    }

    func invalidate(host: String) {
        entries.removeValue(forKey: host)
    }
}

enum BundleLoader {
    static func probe(url: URL) async -> BundleProbe {
        if url.scheme == "lumen" { return .fastApp }
        let manifestURL = url.appendingPathComponent(".well-known/lumen.json")
        var req = URLRequest(url: manifestURL)
        req.timeoutInterval = 3
        req.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return .web }
            guard (try? JSONDecoder().decode(LumenManifest.self, from: data)) != nil else { return .web }
            return .fastApp
        } catch {
            return .web
        }
    }

    static func load(from root: URL) async throws -> LumenBundle {
        if root.scheme == "lumen" {
            return try loadBuiltin(url: root)
        }
        let manifestURL = root.appendingPathComponent(".well-known/lumen.json")
        var req = URLRequest(url: manifestURL)
        req.timeoutInterval = 5
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (manifestData, manifestResp) = try await URLSession.shared.data(for: req)
        if let http = manifestResp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BundleLoadError.manifestUnavailable(manifestResp)
        }

        let manifest: LumenManifest
        do {
            manifest = try JSONDecoder().decode(LumenManifest.self, from: manifestData)
        } catch {
            throw BundleLoadError.manifestUnparseable(error)
        }

        let entryURL = resolveEntry(manifest.entry, root: root, manifestURL: manifestURL)

        var entryReq = URLRequest(url: entryURL)
        entryReq.timeoutInterval = 10
        let (scriptData, scriptResp) = try await URLSession.shared.data(for: entryReq)
        if let http = scriptResp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BundleLoadError.entryUnavailable(scriptResp)
        }

        guard let script = String(data: scriptData, encoding: .utf8) else {
            throw BundleLoadError.entryUndecodable
        }

        return LumenBundle(manifest: manifest, script: script, origin: root)
    }

    private static func loadBuiltin(url: URL) throws -> LumenBundle {
        guard let host = url.host,
              let script = BuiltinFastApps.script(for: host) else {
            throw BundleLoadError.invalidRoot
        }
        let name = BuiltinFastApps.displayName(for: host) ?? host
        let manifest = LumenManifest(
            name: name,
            version: "0",
            entry: "inline",
            minRuntime: nil,
            dev: false
        )
        return LumenBundle(manifest: manifest, script: script, origin: url)
    }

    private static func resolveEntry(_ entry: String, root: URL, manifestURL: URL) -> URL {
        if let abs = URL(string: entry), abs.scheme != nil { return abs }
        if entry.hasPrefix("/") {
            var base = root
            base.appendPathComponent(entry.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            return base
        }
        return manifestURL.deletingLastPathComponent().appendingPathComponent(entry)
    }
}
