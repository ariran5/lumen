import Foundation
import Observation

enum TabMode: Equatable {
    case start
    case web(URL)
    case fastApp(URL)
}

/// Видимость shell URL-chrome'а в табе. Управляется manifest'ом
/// fast-app'а (поле `chrome` в `.well-known/lumen.json`).
enum ChromeMode: String, Equatable {
    case compact   // default — 46pt disc с favicon
    case full      // полная адресная строка
    case hidden    // полностью скрыт (для apps со своим bottom UI)
}

/// Направление навигации — определяет анимацию slide-перехода в shell.
enum NavDirection {
    case forward   // push: вперёд (новая страница из правого края)
    case back      // pop:  назад (текущая уезжает вправо)
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

    /// Per-tab URL стек для outer navigation. `commit()` пушит сюда
    /// предыдущий URL; `goBack()` поппит. Дом не пушим (он база).
    private(set) var urlStack: [URL] = []

    /// Per-tab fast-app runtime (JSEngine + UIKit host) — выживает SwiftUI
    /// rebuild'ы при tab switch'е, поэтому JS state / signals / module
    /// memory не теряются. Освобождается когда TabsStore.close выбрасывает
    /// этот TabModel из массива. Лениво создаётся в FastAppHost.
    @ObservationIgnored var runtime: TabRuntime?

    /// Флаг чтобы `goBack()` не пушил URL обратно в стек при reuse `commit()`.
    private var isBackNavigating: Bool = false

    /// Последнее направление перехода — читается TabContent'ом чтобы выбрать
    /// asymmetric slide-transition (forward — справа влево, back — наоборот).
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
        // Сбрасываем chromeMode — каждый новый fast-app должен заявить
        // свой режим явно через manifest после loadBundle.
        chromeMode = .compact
        // Новый URL → старый runtime stale, выкидываем. ARC освободит engine.
        // (Если url тот же — runtime ниже не создаётся заново, FastAppHost
        // reuse'ит existing instance.)
        if currentURL != url {
            runtime = nil
        }

        // Direction для slide-анимации. goBack() поднимает свой флаг и сам
        // выставляет .back до вызова commit().
        if !isBackNavigating {
            lastNavDirection = .forward
        }

        // Push текущего URL в стек перед навигацией (если это не back-навигация
        // и не дубликат). Дом не пушим — он база, к нему всегда возврат.
        if !isBackNavigating,
           let current = currentURL,
           current != url,
           current != Self.homeURL,
           urlStack.last != current {
            urlStack.append(current)
        }

        // Внутренние lumen:// страницы (history, settings, ...) грузим как
        // fast-app сразу, без probe и без записи в историю.
        if url.scheme == "lumen" {
            mode = .fastApp(url)
            return
        }

        HistoryStore.shared.record(url: url, title: pageTitle)

        let host = url.host ?? url.absoluteString

        // Cache hit — мгновенное решение, без probe-round-trip'а.
        if let cached = BundleProbeCache.shared.get(host: host) {
            switch cached {
            case .fastApp: mode = .fastApp(url)
            case .web: mode = .web(url)
            }
            return
        }

        // Cache miss: priority-probe. Держим старый mode (с прогресс-баром) до
        // ответа probe или 800мс. Если probe сказал .fastApp — монтируем app
        // напрямую, никакого JSON-flash через WebView. Иначе → .web (probe
        // продолжается в фоне и может upgrade до .fastApp когда вернётся).
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

    /// true если текущий mode уже указывает на этот URL.
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

    /// Pop последнего URL из стека. Если стек пуст — go home. Используется
    /// edge-swipe жестом для возврата с sub-fast-app'ов на главную.
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
