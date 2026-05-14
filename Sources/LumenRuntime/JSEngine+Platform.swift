import Foundation
import JavaScriptCore
import UIKit

@MainActor
final class TimerStore {
    static let shared = TimerStore()
    private var timers: [Int: DispatchSourceTimer] = [:]
    private var nextID: Int = 0

    func schedule(after ms: Double, _ block: @escaping () -> Void) -> Int {
        nextID += 1
        let id = nextID
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + max(0, ms) / 1000.0)
        timer.setEventHandler { [weak self] in
            block()
            self?.timers.removeValue(forKey: id)
        }
        timers[id] = timer
        timer.resume()
        return id
    }

    func cancel(_ id: Int) {
        timers.removeValue(forKey: id)?.cancel()
    }
}

extension JSEngine {
    func installPlatformBridges() {
        installBottomSheet()
        installAlert()
        installActionSheetBridge()
        installHaptics()
        installTimers()
        installFetchBridge()
        installStorageBridge()
        installSecureStorageBridge()
        installClipboardBridge()
        installLinkingBridge()
        installShareBridge()
        installImagePickerBridge()
        installDocumentPickerBridge()
        installWebSocketBridge()
        installBenchBridge()
        installAnimationBridge()
        installSafeAreaBridge()
        installLifecycleBridge()
        installAppearanceBridge()
        installNetworkBridge()
        installBiometricsBridge()
        installStatusBarBridge()
        installNotificationsBridge()
        installPatchBridge()
        installNotifyBridge()
        installHistoryBridge()
        installPermissionsBridge()
    }

    private func installBottomSheet() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }

        let bottomSheet: @convention(block) (JSValue?) -> Void = { config in
            guard let config, !config.isUndefined, !config.isNull else { return }

            let contentValue = config.objectForKeyedSubscript("content")
            guard let contentValue, !contentValue.isUndefined,
                  let contentNode = RenderNode.parse(contentValue) else { return }

            let heightToken = config.objectForKeyedSubscript("height")?.toString() ?? "medium"
            let onCloseValue = config.objectForKeyedSubscript("onClose")

            MainActor.assumeIsolated {
                Self.presentBottomSheet(content: contentNode,
                                        heightToken: heightToken,
                                        onCloseValue: onCloseValue)
            }
        }
        lumen.setObject(bottomSheet, forKeyedSubscript: "bottomSheet" as NSString)
    }

    @MainActor
    private static func presentBottomSheet(content: RenderNode,
                                           heightToken: String,
                                           onCloseValue: JSValue?) {
        let sheetVC = BottomSheetViewController(content: content)
        sheetVC.modalPresentationStyle = .pageSheet

        if let sheet = sheetVC.sheetPresentationController {
            switch heightToken {
            case "small":
                sheet.detents = [.custom { _ in 240 }, .medium()]
            case "large":
                sheet.detents = [.large()]
            case "full":
                sheet.detents = [.large()]
                sheetVC.modalPresentationStyle = .overFullScreen
            default:
                sheet.detents = [.medium(), .large()]
            }
            sheet.prefersGrabberVisible = true
            // НЕ ставим preferredCornerRadius — на iOS 26 system делает
            // per-corner morph (top corners остаются rounded при edge-attach
            // к .large, side/bottom corners выпрямляются). Наш explicit value
            // фиксирует все 4 угла одинаково и ломает этот morph.
        }

        if let onCloseValue, !onCloseValue.isUndefined {
            sheetVC.onDismiss = {
                _ = onCloseValue.call(withArguments: [])
            }
        }

        TopViewController.find()?.present(sheetVC, animated: true)
    }

    private func installAlert() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }

        let alertFn: @convention(block) (JSValue?) -> Void = { config in
            let title = config?.objectForKeyedSubscript("title")?.toString() ?? ""
            let message = config?.objectForKeyedSubscript("message")?.toString() ?? ""
            let onOK = config?.objectForKeyedSubscript("onOK")

            MainActor.assumeIsolated {
                let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                    if let onOK, !onOK.isUndefined { _ = onOK.call(withArguments: []) }
                })
                TopViewController.find()?.present(alert, animated: true)
            }
        }
        lumen.setObject(alertFn, forKeyedSubscript: "alert" as NSString)
    }

    private func installHaptics() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }

        let haptics: @convention(block) (String?) -> Void = { style in
            MainActor.assumeIsolated {
                Self.fireHaptic(style ?? "medium")
            }
        }
        lumen.setObject(haptics, forKeyedSubscript: "haptics" as NSString)
    }

    @MainActor
    private static func fireHaptic(_ style: String) {
        switch style {
        case "light":   UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case "heavy":   UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case "rigid":   UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case "soft":    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "warning": UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case "error":   UINotificationFeedbackGenerator().notificationOccurred(.error)
        default:        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private func installTimers() {
        let setTimeout: @convention(block) (JSValue?, Double) -> Int = { callback, ms in
            guard let callback, callback.isObject else { return -1 }
            return MainActor.assumeIsolated {
                TimerStore.shared.schedule(after: ms) {
                    _ = callback.call(withArguments: [])
                }
            }
        }

        let clearTimeout: @convention(block) (Int) -> Void = { id in
            MainActor.assumeIsolated {
                TimerStore.shared.cancel(id)
            }
        }

        context.setObject(setTimeout, forKeyedSubscript: "setTimeout" as NSString)
        context.setObject(clearTimeout, forKeyedSubscript: "clearTimeout" as NSString)
    }
}
