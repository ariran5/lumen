import Foundation
import JavaScriptCore

extension JSEngine {
    func installStorageBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }
        let storage = JSValue(newObjectIn: context)!

        let prefix = "lumen.storage."

        let get: @convention(block) (String?) -> String? = { key in
            guard let key, !key.isEmpty else { return nil }
            return UserDefaults.standard.string(forKey: prefix + key)
        }

        let set: @convention(block) (String?, String?) -> Void = { key, value in
            guard let key, !key.isEmpty else { return }
            let storageKey = prefix + key
            if let value {
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
