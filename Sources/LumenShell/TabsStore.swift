import Foundation
import Observation

/// Multi-tab model of the browser. Holds tab order, active tab, and operations
/// open / close / switch. Each TabModel is independent state
/// (mode, addressInput, etc).
///
/// Currently used by SwiftUI BrowserView; in the future the same store
/// is exposed to the JS shell via `lumen.tabs.*` for dogfooding.
@MainActor
@Observable
final class TabsStore {
    /// Browser-wide singleton. SwiftUI shell + JS bridge (`lumen.tabs.*`)
    /// hit the same model.
    static let shared = TabsStore()

    private(set) var tabs: [TabModel] = []
    var activeID: UUID?

    /// Debounce: multiple properties changing in one runloop iteration
    /// must produce ONE fire("tabs"), not N.
    @ObservationIgnored private var rebroadcastScheduled = false

    init() {
        let first = TabModel()
        tabs = [first]
        activeID = first.id
        startBroadcast()
    }

    /// Auto-broadcast to the JS 'tabs' channel via Observation. Any change
    /// to tabs/activeID/title/loading/URL of any tab → fire("tabs") → every
    /// fast-app with `lumen.tabs.subscribe(...)` gets a callback.
    /// Re-arms after each firing.
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
            // onChange may be a Sendable closure; but in practice it's called
            // synchronously inside a mutation that runs on MainActor.
            MainActor.assumeIsolated {
                guard let self, !self.rebroadcastScheduled else { return }
                self.rebroadcastScheduled = true
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.rebroadcastScheduled = false
                    // The visit title arrives AFTER commit() (once the page loads).
                    // Every tabs-broadcast is a point where we can attach the title to
                    // the history record. updateTitle is idempotent: if the entry already
                    // has a title, no-op.
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

        // Never leave 0 tabs — the user must see at least the start tab.
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
