import Foundation
@preconcurrency import JavaScriptCore

/// `lumen.permissions.{status, request, revoke}` — manage per-origin
/// grants. Capability-API bridges (camera, notifications, …) internally
/// call `PermissionStore.request(origin, capability)` directly — this
/// JS API exists for cases when apps want to explicitly show a prompt
/// before interaction (i.e. onboarding) or read current state
/// to hide UI elements.
///
/// Capabilities are strings: `'notifications' | 'biometric' | 'camera' |
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
        let originRef = origin  // capture for async closures

        let status: @convention(block) (String?) -> String = { rawCap in
            guard let rawCap, let cap = Capability(rawValue: rawCap) else {
                return "denied"  // unknown capability — safe default
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

        // Promise wrapper over _nativeRequest. JS-side to avoid dealing with
        // JSPromise C-API in Swift.
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
