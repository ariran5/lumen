import Foundation
import JavaScriptCore
import UIKit

/// `lumen.statusBar.style({theme?, hidden?})` — overrides UIStatusBarStyle.
///
/// `theme`: `'dark' | 'light' | 'auto'` — meaning ink color of the status bar
/// (light text on dark bg / dark text on light bg / system default).
/// `hidden`: bool — hide entirely.
///
/// Реализация: global mutable `StatusBarConfig.current`, читаемый из
/// `LumenPageViewController.preferredStatusBarStyle` / `prefersStatusBarHidden`.
/// Update пихает значение и зовёт `setNeedsStatusBarAppearanceUpdate` на
/// активной фастаппе.
@MainActor
final class StatusBarConfig {
    static var current = StatusBarConfig()

    var style: UIStatusBarStyle = .default
    var hidden: Bool = false

    /// Сброс к системному — вызывается при mount нового fast-app, чтобы
    /// предыдущий выбор не утекал между фастаппами.
    static func reset() {
        current.style = .default
        current.hidden = false
        invalidate()
    }

    static func invalidate() {
        TopViewController.find()?.setNeedsStatusBarAppearanceUpdate()
    }
}

extension JSEngine {
    func installStatusBarBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }
        let statusBar = JSValue(newObjectIn: context)!

        // Reset на свежем bridge install — новый engine не должен наследовать
        // настройку предыдущего fast-app'а.
        MainActor.assumeIsolated { StatusBarConfig.reset() }

        let setStyle: @convention(block) (JSValue?) -> Void = { config in
            guard let config, !config.isUndefined, !config.isNull else { return }
            let themeVal = config.objectForKeyedSubscript("theme")
            let hiddenVal = config.objectForKeyedSubscript("hidden")

            MainActor.assumeIsolated {
                if let themeVal, !themeVal.isUndefined, !themeVal.isNull,
                   let theme = themeVal.toString() {
                    switch theme {
                    case "dark":  StatusBarConfig.current.style = .darkContent
                    case "light": StatusBarConfig.current.style = .lightContent
                    case "auto":  StatusBarConfig.current.style = .default
                    default: break
                    }
                }
                if let hiddenVal, !hiddenVal.isUndefined, !hiddenVal.isNull,
                   hiddenVal.isBoolean {
                    StatusBarConfig.current.hidden = hiddenVal.toBool()
                }
                StatusBarConfig.invalidate()
            }
        }
        statusBar.setObject(setStyle, forKeyedSubscript: "style" as NSString)
        lumen.setObject(statusBar, forKeyedSubscript: "statusBar" as NSString)
    }
}
