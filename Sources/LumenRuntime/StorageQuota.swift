import Foundation

/// Block 5 — storage quota tracking per origin.
///
/// `lumen.storage.set(key, value)` зовёт `enforce(...)` перед записью;
/// если новая запись + текущее used превышает limit, бросаем JS-exception.
///
/// Size = UTF-8 bytes of key (с prefix'ом) + UTF-8 bytes of value.
/// UserDefaults overhead на запись (binary plist) не учитываем — overhead
/// мал, пользователю достаточно «своих» байтов.
enum StorageQuota {

    /// Hard cap по умолчанию — 100 MB. Конкретный origin может объявить
    /// меньше через `manifest.storage_quota`. Больше — пока нельзя без
    /// permission upgrade flow (TODO).
    static let defaultBytes: Int = 100 * 1024 * 1024

    /// Жёсткий потолок даже для manifest-declared квот. Защита от
    /// `storage_quota: "100GB"` в злонамеренном манифесте.
    static let hardMaxBytes: Int = 1 * 1024 * 1024 * 1024  // 1 GB

    /// Парсит строку из манифеста: `"100MB"`, `"1GB"`, `"512KB"`,
    /// `"1024"` (raw bytes). Регистр case-insensitive, whitespace ok.
    /// Возвращает nil если не распарсилось — caller fallback'ом возьмёт
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

        // Без суффикса — трактуем как raw bytes.
        if let raw = Int(s), raw >= 0 {
            return min(raw, hardMaxBytes)
        }
        return nil
    }

    /// Computed-limit для origin'а: manifest override → или default.
    /// Manifest-override capped by `hardMaxBytes`.
    @MainActor
    static func limit(for context: OriginContext) -> Int {
        // OriginContext.storageQuota доступен после applyManifest.
        if let manifestLimit = context.storageQuota { return manifestLimit }
        return defaultBytes
    }

    /// Сумма UTF-8-байтов всех текущих UserDefaults entries с заданным
    /// prefix'ом. O(n) по всем ключам defaults'а — терпимо т.к.
    /// вызывается только в `set`. Если станет узким местом — кэшируем
    /// running total в OriginContext и обновляем дельта-апдейтами.
    static func currentUsage(prefix: String, defaults: UserDefaults = .standard) -> Int {
        var total = 0
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(prefix) {
            total += key.utf8.count
            if let s = value as? String {
                total += s.utf8.count
            } else if let data = value as? Data {
                total += data.count
            } else {
                // Прочие типы (Int/Bool) — заведомо мелкие, считаем 16
                // байт как round-up. Storage API кладёт только String'и,
                // так что в проде эта ветка не должна срабатывать.
                total += 16
            }
        }
        return total
    }

    /// Проверяет хватит ли места под добавление новой записи. Если ключ
    /// уже существует — мы считаем «расход» как разницу размеров (старая
    /// запись будет overwrite'нута, освобождая свои байты).
    ///
    /// Возвращает nil если можно писать, либо строку с reason'ом для
    /// JS-exception'а.
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
