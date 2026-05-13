import Foundation
import JavaScriptCore
import UIKit

extension JSEngine {
    func installSafeAreaBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }
        // Placeholder — CoreFramework переопределит после eval'а на реактивные
        // signal-backed геттеры. Здесь оставляем пустой объект, чтобы первое
        // обращение из user-code не падало с undefined.
        if let initial = JSValue(newObjectIn: context) {
            initial.setObject(0, forKeyedSubscript: "top" as NSString)
            initial.setObject(0, forKeyedSubscript: "bottom" as NSString)
            initial.setObject(0, forKeyedSubscript: "left" as NSString)
            initial.setObject(0, forKeyedSubscript: "right" as NSString)
            lumen.setObject(initial, forKeyedSubscript: "safeArea" as NSString)
        }
    }

    /// Native сторона дёргает эту функцию когда insets меняются
    /// (viewSafeAreaInsetsDidChange, rotation, keyboard). CoreFramework
    /// зарегистрировал `lumen._updateSafeArea` который пушит в signals.
    func updateSafeArea(_ insets: UIEdgeInsets) {
        guard let lumen = context.objectForKeyedSubscript("lumen"),
              let updater = lumen.objectForKeyedSubscript("_updateSafeArea"),
              !updater.isUndefined, !updater.isNull else { return }
        _ = updater.call(withArguments: [
            Double(insets.top),
            Double(insets.bottom),
            Double(insets.left),
            Double(insets.right),
        ])
    }
}
