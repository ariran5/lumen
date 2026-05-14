import Foundation
import UIKit

/// Per-origin permission grants. Source of truth — UserDefaults. Ключи
/// устроены `lumen.permissions.<origin-shortHash>.<capability>` → `"granted"`
/// / `"denied"`. Отсутствие ключа = `.prompt`.
///
/// shortHash совпадает с тем что используется в `OriginContext.storagePrefix`
/// — clear-site-data может wipe'нуть всё за раз перебором по обоим префиксам.
@MainActor
final class PermissionStore {
    static let shared = PermissionStore()

    private let defaults = UserDefaults.standard

    private init() {}

    private func key(_ origin: Origin, _ capability: Capability) -> String {
        "lumen.permissions.\(origin.shortHash).\(capability.rawValue)"
    }

    /// Текущее sticky-решение без prompt'инга. Безопасно зовётся часто.
    func status(origin: Origin, capability: Capability) -> Grant {
        guard let raw = defaults.string(forKey: key(origin, capability)),
              let grant = Grant(rawValue: raw),
              grant.isDecided else {
            return .prompt
        }
        return grant
    }

    /// Persist'ит decision. Используется prompt'ом после ответа юзера, и
    /// напрямую тестами / settings UI.
    func set(origin: Origin, capability: Capability, grant: Grant) {
        let k = key(origin, capability)
        if grant.isDecided {
            defaults.set(grant.rawValue, forKey: k)
        } else {
            // .prompt = удалить ключ. Следующий request снова спросит.
            defaults.removeObject(forKey: k)
        }
    }

    /// Возвращает grant в `.prompt` — следующий request покажет UI снова.
    func revoke(origin: Origin, capability: Capability) {
        defaults.removeObject(forKey: key(origin, capability))
    }

    /// Wipe всех grant'ов для origin'а. Для shell settings «Clear site data».
    func clear(origin: Origin) {
        let prefix = "lumen.permissions.\(origin.shortHash)."
        for k in defaults.dictionaryRepresentation().keys where k.hasPrefix(prefix) {
            defaults.removeObject(forKey: k)
        }
    }

    /// Главный entry-point для bridge'ей: либо вернуть зашедший grant, либо
    /// показать prompt и подождать решение. `.prompt` никогда не возвращается
    /// наружу — после `request` всегда `.granted` или `.denied`.
    func request(origin: Origin, capability: Capability) async -> Grant {
        switch status(origin: origin, capability: capability) {
        case .granted: return .granted
        case .denied:  return .denied
        case .prompt:
            let result = await PermissionPrompt.show(origin: origin, capability: capability)
            set(origin: origin, capability: capability, grant: result)
            return result
        }
    }
}
