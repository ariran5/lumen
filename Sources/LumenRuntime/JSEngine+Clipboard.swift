import Foundation
import JavaScriptCore
import UIKit

extension JSEngine {
    func installClipboardBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }
        let clipboard = JSValue(newObjectIn: context)!

        let copy: @convention(block) (String?) -> Void = { text in
            MainActor.assumeIsolated {
                UIPasteboard.general.string = text ?? ""
            }
        }

        let paste: @convention(block) () -> String? = {
            MainActor.assumeIsolated {
                UIPasteboard.general.string
            }
        }

        let has: @convention(block) () -> Bool = {
            MainActor.assumeIsolated {
                UIPasteboard.general.hasStrings
            }
        }

        clipboard.setObject(copy, forKeyedSubscript: "copy" as NSString)
        clipboard.setObject(paste, forKeyedSubscript: "paste" as NSString)
        clipboard.setObject(has, forKeyedSubscript: "has" as NSString)

        lumen.setObject(clipboard, forKeyedSubscript: "clipboard" as NSString)
    }
}
