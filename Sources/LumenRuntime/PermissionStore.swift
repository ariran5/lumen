import Foundation
import UIKit

/// Per-origin permission grants. Source of truth — UserDefaults. Keys
/// are `lumen.permissions.<origin-shortHash>.<capability>` → `"granted"`
/// / `"denied"`. Absence of key = `.prompt`.
///
/// shortHash matches the one used in `OriginContext.storagePrefix`
/// — clear-site-data can wipe everything in one pass over both prefixes.
@MainActor
final class PermissionStore {
    static let shared = PermissionStore()

    private let defaults = UserDefaults.standard

    private init() {}

    private func key(_ origin: Origin, _ capability: Capability) -> String {
        "lumen.permissions.\(origin.shortHash).\(capability.rawValue)"
    }

    /// Current sticky decision without prompting. Safe to call frequently.
    func status(origin: Origin, capability: Capability) -> Grant {
        guard let raw = defaults.string(forKey: key(origin, capability)),
              let grant = Grant(rawValue: raw),
              grant.isDecided else {
            return .prompt
        }
        return grant
    }

    /// Persists the decision. Used by prompt after user answer, and
    /// directly by tests / settings UI.
    func set(origin: Origin, capability: Capability, grant: Grant) {
        let k = key(origin, capability)
        if grant.isDecided {
            defaults.set(grant.rawValue, forKey: k)
        } else {
            // .prompt = remove the key. Next request will ask again.
            defaults.removeObject(forKey: k)
        }
    }

    /// Resets grant to `.prompt` — next request will show UI again.
    func revoke(origin: Origin, capability: Capability) {
        defaults.removeObject(forKey: key(origin, capability))
    }

    /// Wipe all grants for an origin. For shell settings "Clear site data".
    func clear(origin: Origin) {
        let prefix = "lumen.permissions.\(origin.shortHash)."
        for k in defaults.dictionaryRepresentation().keys where k.hasPrefix(prefix) {
            defaults.removeObject(forKey: k)
        }
    }

    /// Main entry point for bridges: either return the existing grant, or
    /// show prompt and await a decision. `.prompt` is never returned
    /// outward — after `request` it's always `.granted` or `.denied`.
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
