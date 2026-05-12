import UIKit

@MainActor
enum TopViewController {
    static func find() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })

        return walk(keyWindow?.rootViewController)
    }

    private static func walk(_ controller: UIViewController?) -> UIViewController? {
        guard let controller else { return nil }
        if let nav = controller as? UINavigationController {
            return walk(nav.visibleViewController) ?? nav
        }
        if let tab = controller as? UITabBarController {
            return walk(tab.selectedViewController) ?? tab
        }
        if let presented = controller.presentedViewController {
            return walk(presented)
        }
        return controller
    }
}
