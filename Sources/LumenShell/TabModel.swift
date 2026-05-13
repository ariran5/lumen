import Foundation
import Observation

enum TabMode: Equatable {
    case start
    case web(URL)
    case fastApp(URL)
}

@MainActor
@Observable
final class TabModel: Identifiable {
    let id: UUID = UUID()
    var addressInput: String = ""
    var mode: TabMode = .start
    var isLoading: Bool = false
    var pageTitle: String = ""
    var canGoBack: Bool = false
    var canGoForward: Bool = false

    /// Short display title — fallback chain: pageTitle > host > "New Tab".
    var displayTitle: String {
        if !pageTitle.isEmpty { return pageTitle }
        if let host = currentURL?.host { return host }
        return "New Tab"
    }

    var currentURL: URL? {
        switch mode {
        case .start: return nil
        case .web(let url), .fastApp(let url): return url
        }
    }

    func commit() {
        let trimmed = addressInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            mode = .start
            return
        }
        guard let url = Self.normalize(addressInput) else { return }
        addressInput = url.absoluteString

        let host = url.host ?? url.absoluteString

        // Cache hit — мгновенное решение.
        if let cached = BundleProbeCache.shared.get(host: host) {
            switch cached {
            case .fastApp: mode = .fastApp(url)
            case .web: mode = .web(url)
            }
            return
        }

        // Cache miss: оптимистично запускаем WebView (загрузка идёт параллельно),
        // probe — в фоне с таймаутом. Если manifest найден до того как
        // пользователь ушёл с этой страницы → swap на FastApp.
        mode = .web(url)

        Task { [weak self] in
            let detection = await BundleLoader.probe(url: url)
            await MainActor.run {
                BundleProbeCache.shared.set(host: host, detection)
                guard let self else { return }
                // Применяем swap только если пользователь всё ещё на том же URL.
                guard case .web(let currentURL) = self.mode, currentURL == url else { return }
                if detection == .fastApp {
                    self.mode = .fastApp(url)
                }
            }
        }
    }

    func goHome() {
        mode = .start
        addressInput = ""
    }

    static func normalize(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let scheme = url.scheme, !scheme.isEmpty,
           url.host != nil {
            return url
        }

        let looksLikeDomain = trimmed.contains(".") && !trimmed.contains(" ")
        if looksLikeDomain, let url = URL(string: "https://\(trimmed)") {
            return url
        }

        let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://duckduckgo.com/?q=\(query)")
    }
}
