import SwiftUI
import UIKit

/// SwiftUI обёртка над per-tab fast-app runtime. Сам JSEngine + UIKit
/// hierarchy живёт в `TabModel.runtime` (TabRuntime) — этот View лишь
/// прикрепляет/откладывает nav-controller в SwiftUI tree.
///
/// Multi-tab: при переключении табов SwiftUI выкидывает старый FastAppHost
/// и создаёт новый для активной таб'ы. makeUIViewController возвращает
/// runtime.nav того же TabModel'а — UIKit re-parent'ит nav, JSEngine
/// продолжает работать без перезагрузки.
struct FastAppHost: UIViewControllerRepresentable {
    @Bindable var tab: TabModel
    let url: URL

    func makeUIViewController(context: Context) -> UINavigationController {
        let runtime = ensureRuntime()
        return runtime.nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // Engine может быть ещё не подписан на loadIfNeeded если view bounds
        // на этом шаге уже 0 (rare). loadIfNeeded идемпотентен.
        tab.runtime?.loadIfNeeded()
    }

    static func dismantleUIViewController(_ uiViewController: UINavigationController,
                                          coordinator: Void) {
        // SwiftUI зовёт dismantle когда уносит представление. Сам nav
        // удерживается из TabModel.runtime — он переживёт этот зов и
        // вернётся в новом makeUIViewController при возвращении на эту табу.
        // Дополнительно ничего не нужно: UIKit аккуратно сделает
        // willMove(toParent: nil) когда родитель уберёт нас из children.
    }

    /// Создаёт TabRuntime если у таба его ещё нет. Привязывает callback'и
    /// обратно в TabModel.
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
