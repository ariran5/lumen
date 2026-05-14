import Foundation
import JavaScriptCore

extension JSEngine {
    func installStorageBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }
        let storage = JSValue(newObjectIn: context)!

        // Per-origin namespace. Две табы acme.com шарят keys через единый
        // OriginContext; evil.com физически не видит наши ключи — у него
        // свой prefix с другим origin-хешом.
        let prefix = originContext.storagePrefix
        let originCtx = originContext
        // Капчурим context для throwJS внутри set — strong, т.к. блок
        // живёт в JSC и сам keep'ит context'у retained.
        let ctxRef = context

        let get: @convention(block) (String?) -> String? = { key in
            guard let key, !key.isEmpty else { return nil }
            return UserDefaults.standard.string(forKey: prefix + key)
        }

        let set: @convention(block) (String?, String?) -> Void = { key, value in
            guard let key, !key.isEmpty else { return }
            let storageKey = prefix + key
            if let value {
                // Block 5: quota enforcement. Throw'аем JS-exception если
                // запись превысит limit — апп получит обычный try/catch'абельный
                // error. Не обрезаем втихую: апп должен явно знать что данные
                // не сохранены.
                let limit = MainActor.assumeIsolated { StorageQuota.limit(for: originCtx) }
                if let reason = StorageQuota.denyReason(prefix: prefix,
                                                       keyWithPrefix: storageKey,
                                                       newValue: value,
                                                       limit: limit) {
                    if let exc = JSValue(newErrorFromMessage: reason, in: ctxRef) {
                        ctxRef.exception = exc
                    }
                    return
                }
                UserDefaults.standard.set(value, forKey: storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: storageKey)
            }
        }

        let remove: @convention(block) (String?) -> Void = { key in
            guard let key, !key.isEmpty else { return }
            UserDefaults.standard.removeObject(forKey: prefix + key)
        }

        let keys: @convention(block) () -> [String] = {
            UserDefaults.standard.dictionaryRepresentation().keys
                .filter { $0.hasPrefix(prefix) }
                .map { String($0.dropFirst(prefix.count)) }
        }

        let clear: @convention(block) () -> Void = {
            for key in UserDefaults.standard.dictionaryRepresentation().keys
                where key.hasPrefix(prefix) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        storage.setObject(get, forKeyedSubscript: "get" as NSString)
        storage.setObject(set, forKeyedSubscript: "set" as NSString)
        storage.setObject(remove, forKeyedSubscript: "remove" as NSString)
        storage.setObject(keys, forKeyedSubscript: "keys" as NSString)
        storage.setObject(clear, forKeyedSubscript: "clear" as NSString)

        lumen.setObject(storage, forKeyedSubscript: "storage" as NSString)
    }
}
