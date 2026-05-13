import Foundation
import Observation

/// Multi-tab модель браузера. Держит порядок таб, активную табу, операции
/// open / close / switch. Каждый TabModel — независимое состояние
/// (mode, addressInput, etc).
///
/// Сейчас используется SwiftUI BrowserView'ом; в будущем тот же store
/// проброшен в JS shell через `lumen.tabs.*` для дог-фудинга.
@MainActor
@Observable
final class TabsStore {
    /// Browser-wide singleton. SwiftUI shell + JS-bridge (`lumen.tabs.*`)
    /// дёргают одну и ту же модель.
    static let shared = TabsStore()

    private(set) var tabs: [TabModel] = []
    var activeID: UUID?

    /// Дебаунс: несколько свойств меняющихся в одной runloop-итерации
    /// должны дать ОДИН fire("tabs"), а не N.
    @ObservationIgnored private var rebroadcastScheduled = false

    init() {
        let first = TabModel()
        tabs = [first]
        activeID = first.id
        startBroadcast()
    }

    /// Авто-broadcast в JS-канал 'tabs' через Observation. Любое изменение
    /// tabs/activeID/title/loading/URL у любой таб → fire("tabs") → все
    /// fast-app'ы с `lumen.tabs.subscribe(...)` получают callback.
    /// После каждого срабатывания re-arm'ится.
    private func startBroadcast() {
        withObservationTracking { [weak self] in
            guard let self else { return }
            _ = self.tabs.count
            _ = self.activeID
            for tab in self.tabs {
                _ = tab.displayTitle
                _ = tab.isLoading
                _ = tab.currentURL
            }
        } onChange: { [weak self] in
            // onChange может быть Sendable closure; но фактически он зовётся
            // synchronously внутри мутации, которая идёт на MainActor.
            MainActor.assumeIsolated {
                guard let self, !self.rebroadcastScheduled else { return }
                self.rebroadcastScheduled = true
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.rebroadcastScheduled = false
                    // Title визита приходит ПОЗЖЕ commit() (после загрузки страницы).
                    // Каждый tabs-broadcast — точка где можно докинуть title в
                    // history-запись. updateTitle идемпотентен: если у entry уже
                    // есть title, no-op.
                    for tab in self.tabs {
                        if !tab.pageTitle.isEmpty, let url = tab.currentURL {
                            HistoryStore.shared.updateTitle(
                                forURL: url.absoluteString,
                                title: tab.pageTitle
                            )
                        }
                    }
                    NativeNotifier.shared.fire("tabs")
                    self.startBroadcast()
                }
            }
        }
    }

    var activeTab: TabModel? {
        guard let activeID else { return tabs.first }
        return tabs.first { $0.id == activeID } ?? tabs.first
    }

    var activeIndex: Int? {
        guard let activeID else { return nil }
        return tabs.firstIndex { $0.id == activeID }
    }

    @discardableResult
    func open(url: String? = nil) -> TabModel {
        let tab = TabModel()
        if let url, !url.isEmpty {
            tab.addressInput = url
            tab.commit()
        }
        tabs.append(tab)
        activeID = tab.id
        return tab
    }

    func close(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = (activeID == id)
        tabs.remove(at: idx)

        // Никогда не оставляем 0 таб — пользователь должен видеть хотя бы стартовую.
        if tabs.isEmpty {
            let new = TabModel()
            tabs.append(new)
            activeID = new.id
            return
        }
        if wasActive {
            let neighbor = min(idx, tabs.count - 1)
            activeID = tabs[neighbor].id
        }
    }

    func switchTo(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeID = id
    }
}
