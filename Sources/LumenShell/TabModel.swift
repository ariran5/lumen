import Foundation
import Observation

enum TabMode: Equatable {
    case start
    case web(URL)
    case fastApp(URL)
}

@MainActor
@Observable
final class TabModel {
    var addressInput: String = ""
    var mode: TabMode = .start
    var isLoading: Bool = false
    var pageTitle: String = ""
    var canGoBack: Bool = false
    var canGoForward: Bool = false

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

        Task {
            let detection = await BundleLoader.probe(url: url)
            await MainActor.run {
                switch detection {
                case .fastApp:
                    self.mode = .fastApp(url)
                case .web:
                    self.mode = .web(url)
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
