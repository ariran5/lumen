import Foundation
@preconcurrency import JavaScriptCore
import LocalAuthentication

/// `lumen.biometrics.{authenticate(reason), available()}` — Face ID / Touch ID
/// via `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`.
///
/// `available()` synchronously returns `'faceID' | 'touchID' | 'none'`.
/// `authenticate(reason)` returns `Promise<bool>` — resolve(true) on success,
/// resolve(false) on denial/error (including cancel and lockout). reject is
/// intentionally not used: for UX you almost always want a boolean fork, not
/// try/catch just for cancel.
///
/// Requires `NSFaceIDUsageDescription` in Info.plist on Face ID devices —
/// without it iOS crashes on first attempt. Touch ID doesn't need a separate key.
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
                // Per-origin Lumen gate. Without it any origin could trigger
                // the system Face ID/Touch ID prompt with arbitrary text
                // "Authenticate to do something sketchy" — phishing vector.
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
