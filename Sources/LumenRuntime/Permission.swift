import Foundation

/// Capability'и которые мы gate'им на уровне Lumen — отдельно от OS-prompt'ов.
/// Каждый origin должен быть отдельно подтверждён юзером, даже если OS уже
/// дал permission приложению. Иначе один tab мог бы paspoorts в чужой
/// origin: «yet another untrusted site, мне нужна твоя камера».
///
/// Раздельные `camera` / `microphone` чтобы apps просящие только камеру не
/// получали микрофон бонусом (типичный mistake в браузерах).
enum Capability: String, CaseIterable, Sendable {
    case notifications
    case biometric
    case camera
    case microphone
    case photos
    case location
    case contacts

    /// Человекочитаемое имя для prompt'ов. Не локализуем пока — англ.
    var displayName: String {
        switch self {
        case .notifications: return "send notifications"
        case .biometric:     return "use Face ID / Touch ID"
        case .camera:        return "access your camera"
        case .microphone:    return "access your microphone"
        case .photos:        return "access your photos"
        case .location:      return "use your location"
        case .contacts:      return "access your contacts"
        }
    }
}

/// Три состояния grant'а. `prompt` = «юзер ещё не решал» — следующий запрос
/// покажет prompt. `granted` / `denied` — sticky decisions, sit in store
/// до явного `revoke` либо `clear-site-data`.
enum Grant: String, Sendable {
    case granted
    case denied
    case prompt

    /// Decision'ы которые мы persist'им. `.prompt` хранится как отсутствие
    /// ключа в UserDefaults — это и default value для нового origin.
    var isDecided: Bool { self == .granted || self == .denied }
}
