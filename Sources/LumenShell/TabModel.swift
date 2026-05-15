import Foundation
import Observation

enum TabMode: Equatable {
    case start
    case web(URL)
    case fastApp(URL)
}

/// Visibility of the shell URL chrome in a tab. Controlled by the fast-app's
/// manifest (`chrome` field in `.well-known/lumen.json`).
enum ChromeMode: String, Equatable {
    case compact   // default — 46pt disc with favicon
    case full      // full address bar
    case hidden    // fully hidden (for apps with their own bottom UI)
}

/// Navigation direction — drives the slide-transition animation in the shell.
enum NavDirection {
    case forward   // push: forward (new page from the right edge)
    case back      // pop:  back (current slides out to the right)
}

@MainActor
@Observable
final class TabModel: Identifiable {
    static let homeURL = URL(string: "lumen://home")!

    let id: UUID = UUID()
    var addressInput: String = ""
    var mode: TabMode = .fastApp(homeURL)
    var chromeMode: ChromeMode = .compact
    var isLoading: Bool = false
    var pageTitle: String = ""
    var canGoBack: Bool = false
    var canGoForward: Bool = false

    /// Per-tab URL stack for outer navigation. `commit()` pushes the previous
    /// URL here; `goBack()` pops it. Home is not pushed (it's the base).
    private(set) var urlStack: [URL] = []

    /// Per-tab fast-app runtime (JSEngine + UIKit host) — survives SwiftUI
    /// rebuilds across tab switches, so JS state / signals / module
    /// memory are not lost. Released when TabsStore.close drops this
    /// TabModel from the array. Lazily created in FastAppHost.
    @ObservationIgnored var runtime: TabRuntime?

    /// Flag so `goBack()` doesn't push the URL back onto the stack when reusing `commit()`.
    private var isBackNavigating: Bool = false

    /// Last transition direction — read by TabContent to pick the
    /// asymmetric slide-transition (forward — right to left, back — reverse).
    var lastNavDirection: NavDirection = .forward

    /// Short display title — fallback chain: pageTitle > host:port > "New Tab".
    var displayTitle: String {
        if !pageTitle.isEmpty { return pageTitle }
        if let url = currentURL { return url.hostForDisplay }
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
        // Reset chromeMode — each new fast-app must declare
        // its mode explicitly via the manifest after loadBundle.
        chromeMode = .compact
        // New URL → old runtime is stale, drop it. ARC will free the engine.
        // (If url is the same — the runtime below is not recreated; FastAppHost
        // reuses the existing instance.)
        if currentURL != url {
            runtime = nil
        }

        // Direction for slide-animation. goBack() raises its own flag and
        // sets .back before calling commit().
        if !isBackNavigating {
            lastNavDirection = .forward
        }

        // Push current URL onto the stack before navigating (unless this is back-nav
        // or a duplicate). Home is not pushed — it's the base, always the return target.
        if !isBackNavigating,
           let current = currentURL,
           current != url,
           current != Self.homeURL,
           urlStack.last != current {
            urlStack.append(current)
        }

        // Internal lumen:// pages (history, settings, ...) load as a
        // fast-app immediately, without probe and without recording in history.
        if url.scheme == "lumen" {
            mode = .fastApp(url)
            return
        }

        HistoryStore.shared.record(url: url, title: pageTitle)

        let host = url.host ?? url.absoluteString

        // Cache hit — instant decision, no probe round-trip.
        if let cached = BundleProbeCache.shared.get(host: host) {
            switch cached {
            case .fastApp: mode = .fastApp(url)
            case .web: mode = .web(url)
            }
            return
        }

        // Cache miss: priority-probe. Keep the old mode (with progress bar) until
        // probe responds or 800ms. If probe says .fastApp — mount the app
        // directly, no JSON-flash through WebView. Otherwise → .web (probe
        // continues in background and may upgrade to .fastApp when it returns).
        isLoading = true
        let target = url

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self else { return }
            guard self.addressInput == target.absoluteString else { return }
            if self.modeMatches(target) { return }
            self.mode = .web(target)
        }

        Task { [weak self] in
            let result = await BundleLoader.probe(url: target)
            BundleProbeCache.shared.set(host: host, result)
            await MainActor.run {
                guard let self else { return }
                guard self.addressInput == target.absoluteString else { return }
                switch result {
                case .fastApp:
                    self.mode = .fastApp(target)
                case .web:
                    if !self.modeMatches(target) {
                        self.mode = .web(target)
                    }
                }
                self.isLoading = false
            }
        }
    }

    /// true if the current mode already points to this URL.
    private func modeMatches(_ url: URL) -> Bool {
        switch mode {
        case .fastApp(let u), .web(let u): return u == url
        case .start: return false
        }
    }

    func goHome() {
        lastNavDirection = .back
        mode = .fastApp(Self.homeURL)
        addressInput = ""
        urlStack.removeAll()
    }

    /// Pop the last URL from the stack. If the stack is empty — go home. Used
    /// by the edge-swipe gesture to return from sub-fast-apps to the main view.
    func goBack() {
        lastNavDirection = .back
        guard let prev = urlStack.popLast() else {
            goHome()
            return
        }
        isBackNavigating = true
        addressInput = prev.absoluteString
        commit()
        isBackNavigating = false
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
