import Foundation

extension URL {
    /// `host:port` для UI-отображения. Возвращает чистый host если порт
    /// дефолтный для схемы (URL.port = nil), иначе `host:port`.
    /// Для lumen://history → `lumen://history` (тоже отображаем prefix).
    var hostForDisplay: String {
        if scheme == "lumen", let h = host {
            return "lumen://\(h)"
        }
        guard let h = host else { return absoluteString }
        if let p = port { return "\(h):\(p)" }
        return h
    }
}
