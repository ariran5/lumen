import Foundation

/// Capabilities we gate at the Lumen level — separate from OS prompts.
/// Each origin must be separately approved by the user, even if the OS
/// already gave permission to the app. Otherwise one tab could impersonate
/// another origin: "yet another untrusted site, I need your camera".
///
/// Separate `camera` / `microphone` so apps asking only for camera don't
/// get microphone as a bonus (typical mistake in browsers).
enum Capability: String, CaseIterable, Sendable {
    case notifications
    case biometric
    case camera
    case microphone
    case photos
    case location
    case contacts

    /// Human-readable name for prompts. Not localized for now — English.
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

/// Three grant states. `prompt` = "user hasn't decided yet" — next request
/// will show prompt. `granted` / `denied` — sticky decisions, sit in store
/// until explicit `revoke` or `clear-site-data`.
enum Grant: String, Sendable {
    case granted
    case denied
    case prompt

    /// Decisions we persist. `.prompt` is stored as absence of
    /// the key in UserDefaults — that's also the default value for a new origin.
    var isDecided: Bool { self == .granted || self == .denied }
}
