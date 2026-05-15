import Foundation
import JavaScriptCore
import UIKit

/// `lumen.share({text, url})` — standard iOS share sheet via
/// `UIActivityViewController`. Accepts any combination of text/url.
/// On iPad popover anchor is screen-centered (via arrowDirections=[]).
extension JSEngine {
    func installShareBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }

        let share: @convention(block) (JSValue?) -> Void = { config in
            MainActor.assumeIsolated {
                Self.presentShare(config: config)
            }
        }
        lumen.setObject(share, forKeyedSubscript: "share" as NSString)
    }

    @MainActor
    private static func presentShare(config: JSValue?) {
        var items: [Any] = []
        if let text = config?.objectForKeyedSubscript("text")?.toString(),
           !text.isEmpty, text != "undefined" {
            items.append(text)
        }
        if let urlString = config?.objectForKeyedSubscript("url")?.toString(),
           !urlString.isEmpty, urlString != "undefined",
           let url = URL(string: urlString) {
            items.append(url)
        }
        guard !items.isEmpty else { return }

        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        guard let presenter = TopViewController.find() else { return }

        if let popover = vc.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.midY,
                                        width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        let onDone = config?.objectForKeyedSubscript("onDone")
        if let onDone, !onDone.isUndefined {
            vc.completionWithItemsHandler = { activity, completed, _, _ in
                _ = onDone.call(withArguments: [completed, activity?.rawValue ?? NSNull()])
            }
        }

        presenter.present(vc, animated: true)
    }
}
