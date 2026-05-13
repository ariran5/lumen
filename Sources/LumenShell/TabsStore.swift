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

    init() {
        let first = TabModel()
        tabs = [first]
        activeID = first.id
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
