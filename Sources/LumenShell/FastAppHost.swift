import SwiftUI
import UIKit

/// SwiftUI wrapper over the per-tab fast-app runtime. The JSEngine + UIKit
/// hierarchy itself lives in `TabModel.runtime` (TabRuntime) — this View only
/// attaches/detaches the nav-controller in the SwiftUI tree.
///
/// Multi-tab: when switching tabs SwiftUI discards the old FastAppHost
/// and creates a new one for the active tab. makeUIViewController returns
/// runtime.nav of the same TabModel — UIKit re-parents the nav, JSEngine
/// keeps running without a reload.
struct FastAppHost: UIViewControllerRepresentable {
    @Bindable var tab: TabModel
    let url: URL

    func makeUIViewController(context: Context) -> UINavigationController {
        let runtime = ensureRuntime()
        return runtime.nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // Engine may not yet be subscribed to loadIfNeeded if view bounds
        // at this step are still 0 (rare). loadIfNeeded is idempotent.
        tab.runtime?.loadIfNeeded()
    }

    static func dismantleUIViewController(_ uiViewController: UINavigationController,
                                          coordinator: Void) {
        // SwiftUI calls dismantle when removing the representation. The nav
        // itself is retained by TabModel.runtime — it survives this call and
        // returns in a new makeUIViewController when we come back to this tab.
        // Nothing else needed: UIKit cleanly does
        // willMove(toParent: nil) when the parent removes us from children.
    }

    /// Creates a TabRuntime if the tab doesn't have one yet. Wires callbacks
    /// back into TabModel.
    private func ensureRuntime() -> TabRuntime {
        if let existing = tab.runtime, existing.url == url {
            return existing
        }
        let rt = TabRuntime(url: url, tabID: tab.id)
        rt.onBundleName = { [weak tab] name in
            tab?.pageTitle = name
        }
        rt.onChromeMode = { [weak tab] mode in
            tab?.chromeMode = mode
        }
        tab.runtime = rt
        return rt
    }
}
