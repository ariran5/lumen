import Foundation

struct LumenManifest: Decodable, Sendable {
    let name: String
    let version: String
    let entry: String
    let minRuntime: String?

    enum CodingKeys: String, CodingKey {
        case name, version, entry
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

enum BundleLoader {
    static func load(from root: URL) async throws -> LumenBundle {
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
