import Foundation
import UIKit

/// Модальный UIAlertController «<host> wants to <capability>». Однократный
/// вопрос — ответ персистится `PermissionStore`'ом и больше не задаётся
/// до явного `revoke`.
///
/// Не fast-app-рендереный — присентим через `TopViewController.find()`,
/// поверх любого fast-app content'а, как system alert.
@MainActor
enum PermissionPrompt {

    /// Показывает alert и ждёт ответа. `.granted` если юзер тапнул Allow,
    /// `.denied` иначе (включая swipe-to-dismiss и фоновое прерывание).
    /// `.prompt` отсюда не выходит — это всегда decided answer.
    static func show(origin: Origin, capability: Capability) async -> Grant {
        await withCheckedContinuation { (cont: CheckedContinuation<Grant, Never>) in
            present(origin: origin, capability: capability) { grant in
                cont.resume(returning: grant)
            }
        }
    }

    private static func present(origin: Origin,
                                capability: Capability,
                                completion: @escaping (Grant) -> Void) {
        guard let host = TopViewController.find() else {
            // Без presenting controller'а вернуть denied как safest default.
            // Шансов что это произойдёт мало — fast-app живёт под VC'эхой.
            completion(.denied)
            return
        }

        let title = "\(origin.host) wants to \(capability.displayName)"
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)

        // Allow первой кнопкой — но не дефолтной. Дефолтная (highlighted) —
        // Don't Allow: давит на «осторожный» путь при случайном Enter'е.
        alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in
            completion(.granted)
        })
        let dontAllow = UIAlertAction(title: "Don't Allow", style: .cancel) { _ in
            completion(.denied)
        }
        alert.addAction(dontAllow)
        alert.preferredAction = dontAllow

        host.present(alert, animated: true)
    }
}
