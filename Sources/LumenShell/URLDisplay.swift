import Foundation

extension URL {
    /// `host:port` for UI display. Returns plain host if the port is
    /// the scheme default (URL.port = nil), otherwise `host:port`.
    /// For lumen://history → `lumen://history` (the prefix is shown too).
    var hostForDisplay: String {
        if scheme == "lumen", let h = host {
            return "lumen://\(h)"
        }
        guard let h = host else { return absoluteString }
        if let p = port { return "\(h):\(p)" }
        return h
    }
}
