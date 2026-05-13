import Foundation
import JavaScriptCore
import UIKit

/// `lumen.appearance.theme` — реактивный сигнал темы (`'dark' | 'light'`).
///
/// Источник правды — `UIWindowScene.traitCollection.userInterfaceStyle`.
/// На iOS 17+ trait change observer фаерит при смене системной темы
/// в реальном времени; на старте — читаем текущее значение.
extension JSEngine {
    func installAppearanceBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }

        lumen.setObject(Self.currentTheme(), forKeyedSubscript: "_themeInitial" as NSString)

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }

        let registration = scene.registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            [weak self] (_: UIWindowScene, _: UITraitCollection) in
            MainActor.assumeIsolated { self?.pushTheme(Self.currentTheme()) }
        }

        Self.appearanceAlive[ObjectIdentifier(self)] = AppearanceHolder(registration: registration)
    }

    private func pushTheme(_ theme: String) {
        guard let lumen = context.objectForKeyedSubscript("lumen"),
              let updater = lumen.objectForKeyedSubscript("_updateTheme"),
              !updater.isUndefined, !updater.isNull else { return }
        _ = updater.call(withArguments: [theme])
    }

    private static func currentTheme() -> String {
        let style: UIUserInterfaceStyle
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            style = scene.traitCollection.userInterfaceStyle
        } else {
            style = UITraitCollection.current.userInterfaceStyle
        }
        return style == .dark ? "dark" : "light"
    }

    @MainActor
    private static var appearanceAlive: [ObjectIdentifier: AppearanceHolder] = [:]
}

@MainActor
private final class AppearanceHolder {
    let registration: any UITraitChangeRegistration
    init(registration: any UITraitChangeRegistration) {
        self.registration = registration
    }
}
