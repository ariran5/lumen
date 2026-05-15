import Foundation

/// Block 5 — storage quota tracking per origin.
///
/// `lumen.storage.set(key, value)` calls `enforce(...)` before writing;
/// if the new entry + current usage exceeds the limit, throw a JS exception.
///
/// Size = UTF-8 bytes of key (with prefix) + UTF-8 bytes of value.
/// UserDefaults write overhead (binary plist) is not counted — overhead
/// is small, the user gets enough "own" bytes.
enum StorageQuota {

    /// Default hard cap — 100 MB. A specific origin can declare
    /// less via `manifest.storage_quota`. More is not yet allowed without
    /// a permission upgrade flow (TODO).
    static let defaultBytes: Int = 100 * 1024 * 1024

    /// Hard ceiling even for manifest-declared quotas. Protection against
    /// `storage_quota: "100GB"` in a malicious manifest.
    static let hardMaxBytes: Int = 1 * 1024 * 1024 * 1024  // 1 GB

    /// Parses a string from manifest: `"100MB"`, `"1GB"`, `"512KB"`,
    /// `"1024"` (raw bytes). Case-insensitive, whitespace ok.
    /// Returns nil if parsing failed — caller falls back to
    /// `defaultBytes`.
    static func parse(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let s = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard !s.isEmpty else { return nil }

        let multipliers: [(String, Int)] = [
            ("GB", 1024 * 1024 * 1024),
            ("MB", 1024 * 1024),
            ("KB", 1024),
            ("B", 1),
        ]

        for (suffix, mult) in multipliers where s.hasSuffix(suffix) {
            let num = s.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
            if let value = Double(num), value >= 0 {
                return min(Int(value * Double(mult)), hardMaxBytes)
            }
            return nil
        }

        // No suffix — treat as raw bytes.
        if let raw = Int(s), raw >= 0 {
            return min(raw, hardMaxBytes)
        }
        return nil
    }

    /// Computed limit for an origin: manifest override → or default.
    /// Manifest override capped by `hardMaxBytes`.
    @MainActor
    static func limit(for context: OriginContext) -> Int {
        // OriginContext.storageQuota available after applyManifest.
        if let manifestLimit = context.storageQuota { return manifestLimit }
        return defaultBytes
    }

    /// Sum of UTF-8 bytes of all current UserDefaults entries with the given
    /// prefix. O(n) over all defaults keys — tolerable since
    /// called only in `set`. If this becomes a bottleneck — cache
    /// running total in OriginContext and update via delta updates.
    static func currentUsage(prefix: String, defaults: UserDefaults = .standard) -> Int {
        var total = 0
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(prefix) {
            total += key.utf8.count
            if let s = value as? String {
                total += s.utf8.count
            } else if let data = value as? Data {
                total += data.count
            } else {
                // Other types (Int/Bool) — clearly small, count 16
                // bytes as round-up. Storage API only stores Strings,
                // so in prod this branch shouldn't fire.
                total += 16
            }
        }
        return total
    }

    /// Checks whether there's room for a new entry. If the key
    /// already exists — we count "cost" as the size diff (old
    /// entry will be overwritten, freeing its bytes).
    ///
    /// Returns nil if write is ok, or a string with the reason for
    /// a JS exception.
    static func denyReason(prefix: String,
                           keyWithPrefix: String,
                           newValue: String,
                           limit: Int,
                           defaults: UserDefaults = .standard) -> String? {
        let current = currentUsage(prefix: prefix, defaults: defaults)
        let oldEntrySize: Int = {
            guard let existing = defaults.string(forKey: keyWithPrefix) else { return 0 }
            return keyWithPrefix.utf8.count + existing.utf8.count
        }()
        let newEntrySize = keyWithPrefix.utf8.count + newValue.utf8.count
        let projected = current - oldEntrySize + newEntrySize
        if projected > limit {
            return "storage quota exceeded (\(projected) > \(limit) bytes)"
        }
        return nil
    }
}
