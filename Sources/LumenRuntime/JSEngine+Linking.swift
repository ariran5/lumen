import Foundation
import JavaScriptCore
import UIKit

/// `lumen.linking.open(url)` / `canOpen(url)` — открыть mailto:/tel:/sms:/https:
/// или любой custom-scheme через `UIApplication.shared.open`.
///
/// `canOpen` для non-http схем требует `LSApplicationQueriesSchemes` в
/// Info.plist (mailto/tel/sms/instagram/...). `open` работает без декларации,
/// просто всегда возвращает success/false по результату.
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

        linking.setObject(open, forKeyedSubscript: "open" as NSString)
        linking.setObject(canOpen, forKeyedSubscript: "canOpen" as NSString)
        lumen.setObject(linking, forKeyedSubscript: "linking" as NSString)
    }
}
