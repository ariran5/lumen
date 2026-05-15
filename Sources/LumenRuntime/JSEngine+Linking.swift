import Foundation
import JavaScriptCore
import UIKit

/// `lumen.linking.open(url)` / `canOpen(url)` — open mailto:/tel:/sms:/https:
/// or any custom-scheme via `UIApplication.shared.open`.
///
/// `canOpen` for non-http schemes requires `LSApplicationQueriesSchemes` in
/// Info.plist (mailto/tel/sms/instagram/...). `open` works without declaration,
/// just always returns success/false based on the result.
///
/// `_consumePending` — drain the incoming URL queue (SwiftUI `.onOpenURL` →
/// `IncomingURLStore.enqueue`). JS wrapper `linking.onIncoming.subscribe(fn)`
/// in CoreFramework subscribes to channel `linking.incoming` and on each
/// fire reads accumulated URLs.
extension JSEngine {
    func installLinkingBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }
        let linking = JSValue(newObjectIn: context)!

        let open: @convention(block) (String?) -> Bool = { urlString in
            guard let urlString, let url = URL(string: urlString) else { return false }
            return MainActor.assumeIsolated {
                guard UIApplication.shared.canOpenURL(url) else { return false }
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                return true
            }
        }

        let canOpen: @convention(block) (String?) -> Bool = { urlString in
            guard let urlString, let url = URL(string: urlString) else { return false }
            return MainActor.assumeIsolated {
                UIApplication.shared.canOpenURL(url)
            }
        }

        let consumePending: @convention(block) () -> [String] = {
            MainActor.assumeIsolated {
                IncomingURLStore.shared.consume()
            }
        }

        linking.setObject(open, forKeyedSubscript: "open" as NSString)
        linking.setObject(canOpen, forKeyedSubscript: "canOpen" as NSString)
        linking.setObject(consumePending, forKeyedSubscript: "_consumePending" as NSString)
        lumen.setObject(linking, forKeyedSubscript: "linking" as NSString)
    }
}
