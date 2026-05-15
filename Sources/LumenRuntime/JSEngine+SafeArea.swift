import Foundation
import JavaScriptCore
import UIKit

extension JSEngine {
    func installSafeAreaBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }
        // Placeholder — CoreFramework will override after eval with reactive
        // signal-backed getters. Leave an empty object here so first
        // access from user code doesn't fail with undefined.
        if let initial = JSValue(newObjectIn: context) {
            initial.setObject(0, forKeyedSubscript: "top" as NSString)
            initial.setObject(0, forKeyedSubscript: "bottom" as NSString)
            initial.setObject(0, forKeyedSubscript: "left" as NSString)
            initial.setObject(0, forKeyedSubscript: "right" as NSString)
            lumen.setObject(initial, forKeyedSubscript: "safeArea" as NSString)
        }
    }

    /// Native side calls this when insets change
    /// (viewSafeAreaInsetsDidChange, rotation, keyboard). CoreFramework
    /// registered `lumen._updateSafeArea` which pushes to signals.
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
