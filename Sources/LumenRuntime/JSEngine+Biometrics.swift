import Foundation
@preconcurrency import JavaScriptCore
import LocalAuthentication

/// `lumen.biometrics.{authenticate(reason), available()}` — Face ID / Touch ID
/// через `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`.
///
/// `available()` синхронно отвечает `'faceID' | 'touchID' | 'none'`.
/// `authenticate(reason)` возвращает `Promise<bool>` — resolve(true) при успехе,
/// resolve(false) при отказе/ошибке (включая cancel и lockout). reject не
/// используем намеренно: для UX почти всегда хочется булевую развилку, а не
/// try/catch ради cancel'а.
///
/// Требует `NSFaceIDUsageDescription` в Info.plist на устройствах с Face ID —
/// без неё iOS падает при первой попытке. Touch ID не требует separate key.
extension JSEngine {
    func installBiometricsBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }
        let biometrics = JSValue(newObjectIn: context)!

        let available: @convention(block) () -> String = {
            let ctx = LAContext()
            var err: NSError?
            guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
                return "none"
            }
            switch ctx.biometryType {
            case .faceID:  return "faceID"
            case .touchID: return "touchID"
            default:       return "none"
            }
        }

        let originRef = origin
        let nativeAuth: @convention(block) (String?, JSValue, JSValue) -> Void = { reason, resolve, _ in
            let reason = (reason?.isEmpty == false) ? reason! : "Authenticate"
            Task { @MainActor in
                // Per-origin Lumen-gate. Без него любой origin мог бы вызвать
                // системный Face ID/Touch ID prompt с произвольным текстом
                // «Authenticate to сделать что-то sketchy» — фишинг-вектор.
                let grant = await PermissionStore.shared.request(origin: originRef, capability: .biometric)
                guard grant == .granted else {
                    _ = resolve.call(withArguments: [false])
                    return
                }
                let ctx = LAContext()
                ctx.localizedFallbackTitle = ""
                ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                   localizedReason: reason) { success, _ in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            _ = resolve.call(withArguments: [success])
                        }
                    }
                }
            }
        }

        biometrics.setObject(available, forKeyedSubscript: "available" as NSString)
        biometrics.setObject(nativeAuth, forKeyedSubscript: "_nativeAuth" as NSString)
        lumen.setObject(biometrics, forKeyedSubscript: "biometrics" as NSString)

        let wrapper = """
        lumen.biometrics.authenticate = function (reason) {
          return new Promise(function (resolve, reject) {
            lumen.biometrics._nativeAuth(String(reason || 'Authenticate'), resolve, reject)
          })
        }
        """
        _ = context.evaluateScript(wrapper)
    }
}
