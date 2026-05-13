import Foundation
import JavaScriptCore
import Security

/// `lumen.secureStorage.{get,set,remove}` — Keychain через `SecItem*`.
/// В отличие от `lumen.storage` (UserDefaults) — шифруется системой,
/// доступно после первого unlock, не уходит в iCloud backup по умолчанию.
/// Использовать для auth-токенов, паролей, API-ключей.
extension JSEngine {
    func installSecureStorageBridge() {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }
        let secureStorage = JSValue(newObjectIn: context)!
        let service = "com.lumen.secureStorage"

        let get: @convention(block) (String?) -> String? = { key in
            guard let key, !key.isEmpty else { return nil }
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecReturnData as String: true,
            ]
            var item: AnyObject?
            let status = withUnsafeMutablePointer(to: &item) {
                SecItemCopyMatching(query as CFDictionary, UnsafeMutablePointer($0))
            }
            guard status == errSecSuccess,
                  let data = item as? Data,
                  let str = String(data: data, encoding: .utf8) else { return nil }
            return str
        }

        let set: @convention(block) (String?, String?) -> Bool = { key, value in
            guard let key, !key.isEmpty else { return false }
            let data = (value ?? "").data(using: .utf8) ?? Data()

            // Idempotent: удалить старое значение и добавить новое.
            let delQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
            ]
            SecItemDelete(delQuery as CFDictionary)

            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ]
            let status = SecItemAdd(addQuery as CFDictionary, nil)
            return status == errSecSuccess
        }

        let remove: @convention(block) (String?) -> Void = { key in
            guard let key, !key.isEmpty else { return }
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
            ]
            SecItemDelete(query as CFDictionary)
        }

        secureStorage.setObject(get, forKeyedSubscript: "get" as NSString)
        secureStorage.setObject(set, forKeyedSubscript: "set" as NSString)
        secureStorage.setObject(remove, forKeyedSubscript: "remove" as NSString)
        lumen.setObject(secureStorage, forKeyedSubscript: "secureStorage" as NSString)
    }
}
