import Foundation
@preconcurrency import JavaScriptCore

/// `lumen.permissions.{status, request, revoke}` — управление per-origin
/// grant'ами. Bridge'и capability-API (camera, notifications, …) внутри
/// зовут `PermissionStore.request(origin, capability)` напрямую — этот
/// JS-API существует для случаев когда apps хотят явно показать prompt
/// перед взаимодействием (i.e. onboarding) или прочитать текущее состояние
/// чтобы скрыть UI элементы.
///
/// Capability'и — строки: `'notifications' | 'biometric' | 'camera' |
/// 'microphone' | 'photos' | 'location' | 'contacts'`.
///
/// API:
/// ```ts
/// const s = lumen.permissions.status('camera')            // 'granted' | 'denied' | 'prompt'
/// const g = await lumen.permissions.request('camera')      // 'granted' | 'denied'
/// lumen.permissions.revoke('camera')                       // → 'prompt' on next request
/// ```
extension JSEngine {
    func installPermissionsBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }
        let permissions = JSValue(newObjectIn: context)!
        let originRef = origin  // capture для async closure'ов

        let status: @convention(block) (String?) -> String = { rawCap in
            guard let rawCap, let cap = Capability(rawValue: rawCap) else {
                return "denied"  // неизвестный capability — безопасный default
            }
            return MainActor.assumeIsolated {
                PermissionStore.shared.status(origin: originRef, capability: cap).rawValue
            }
        }
        permissions.setObject(status, forKeyedSubscript: "status" as NSString)

        let nativeRequest: @convention(block) (String?, JSValue, JSValue) -> Void = { rawCap, resolve, reject in
            guard let rawCap, let cap = Capability(rawValue: rawCap) else {
                _ = reject.call(withArguments: ["unknown capability: \(rawCap ?? "<nil>")"])
                return
            }
            Task { @MainActor in
                let result = await PermissionStore.shared.request(origin: originRef, capability: cap)
                _ = resolve.call(withArguments: [result.rawValue])
            }
        }
        permissions.setObject(nativeRequest, forKeyedSubscript: "_nativeRequest" as NSString)

        let revoke: @convention(block) (String?) -> Void = { rawCap in
            guard let rawCap, let cap = Capability(rawValue: rawCap) else { return }
            MainActor.assumeIsolated {
                PermissionStore.shared.revoke(origin: originRef, capability: cap)
            }
        }
        permissions.setObject(revoke, forKeyedSubscript: "revoke" as NSString)

        lumen.setObject(permissions, forKeyedSubscript: "permissions" as NSString)

        // Promise-wrapper над _nativeRequest. JS-side чтобы не возиться с
        // JSPromise C-API в Swift'е.
        let wrapper = """
        lumen.permissions.request = function (capability) {
          return new Promise(function (resolve, reject) {
            lumen.permissions._nativeRequest(String(capability), resolve, reject)
          })
        }
        """
        _ = context.evaluateScript(wrapper)
    }
}
