import Foundation
import UIKit

/// Modal UIAlertController "<host> wants to <capability>". One-shot
/// question — answer is persisted by `PermissionStore` and never asked again
/// until explicit `revoke`.
///
/// Not fast-app-rendered — presented via `TopViewController.find()`,
/// over any fast-app content, like a system alert.
@MainActor
enum PermissionPrompt {

    /// Shows alert and awaits answer. `.granted` if user tapped Allow,
    /// `.denied` otherwise (including swipe-to-dismiss and background interruption).
    /// `.prompt` never returns from here — it's always a decided answer.
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
            // Without a presenting controller return denied as the safest default.
            // Unlikely to happen — fast-app lives under a VC.
            completion(.denied)
            return
        }

        let title = "\(origin.host) wants to \(capability.displayName)"
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)

        // Allow as the first button — but not the default. Default (highlighted) —
        // Don't Allow: nudges toward the "cautious" path on accidental Enter.
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
