import Foundation
import JavaScriptCore
import UIKit

/// `lumen.actionSheet({title, message, actions, onSelect, onCancel})`.
/// `actions: Array<{label, style: 'default'|'destructive'|'cancel'}>`.
/// `onSelect(index)` дёргается с индексом выбранного action (0-based).
/// Cancel-кнопка добавляется автоматически если в actions её нет.
extension JSEngine {
    func installActionSheetBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }

        let actionSheet: @convention(block) (JSValue?) -> Void = { config in
            MainActor.assumeIsolated {
                Self.presentActionSheet(config: config)
            }
        }
        lumen.setObject(actionSheet, forKeyedSubscript: "actionSheet" as NSString)
    }

    @MainActor
    private static func presentActionSheet(config: JSValue?) {
        let titleRaw = config?.objectForKeyedSubscript("title")?.toString() ?? ""
        let messageRaw = config?.objectForKeyedSubscript("message")?.toString() ?? ""
        let title = (titleRaw.isEmpty || titleRaw == "undefined") ? nil : titleRaw
        let message = (messageRaw.isEmpty || messageRaw == "undefined") ? nil : messageRaw

        let onSelect = config?.objectForKeyedSubscript("onSelect")
        let onCancel = config?.objectForKeyedSubscript("onCancel")

        let alert = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)

        var hasUserCancel = false
        if let actionsArr = config?.objectForKeyedSubscript("actions"),
           actionsArr.isArray,
           let count = actionsArr.objectForKeyedSubscript("length")?.toNumber()?.intValue {
            for i in 0..<count {
                guard let action = actionsArr.atIndex(i) else { continue }
                let label = action.objectForKeyedSubscript("label")?.toString() ?? "Action \(i)"
                let styleStr = action.objectForKeyedSubscript("style")?.toString() ?? "default"
                let style: UIAlertAction.Style
                switch styleStr {
                case "destructive": style = .destructive
                case "cancel":      style = .cancel;      hasUserCancel = true
                default:            style = .default
                }
                let index = i
                alert.addAction(UIAlertAction(title: label, style: style) { _ in
                    if style == .cancel {
                        if let onCancel, !onCancel.isUndefined {
                            _ = onCancel.call(withArguments: [])
                        }
                    } else if let onSelect, !onSelect.isUndefined {
                        _ = onSelect.call(withArguments: [index])
                    }
                })
            }
        }

        if !hasUserCancel {
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                if let onCancel, !onCancel.isUndefined { _ = onCancel.call(withArguments: []) }
            })
        }

        guard let presenter = TopViewController.find() else { return }
        if let popover = alert.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.maxY - 1,
                                        width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(alert, animated: true)
    }
}
