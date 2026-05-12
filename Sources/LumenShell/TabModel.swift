import Foundation
import Observation

@MainActor
@Observable
final class TabModel {
    var addressInput: String = ""
    var currentURL: URL?
    var isLoading: Bool = false
    var pageTitle: String = ""
    var canGoBack: Bool = false
    var canGoForward: Bool = false

    func commit() {
        guard let url = Self.normalize(addressInput) else { return }
        currentURL = url
        addressInput = url.absoluteString
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
