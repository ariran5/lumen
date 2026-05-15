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
        if let presented = controller.presentedViewController {
            return walk(presented) ?? controller
        }
        if let nav = controller as? UINavigationController {
            return walk(nav.visibleViewController) ?? nav
        }
        if let tab = controller as? UITabBarController {
            return walk(tab.selectedViewController) ?? tab
        }
        // Descend through children. Critical for the case when our UIKit
        // content (FastAppHost's UINavigationController) hangs as a child
        // VC of a SwiftUI UIHostingController. Presenting from the host
        // controller — iOS 26 sheet's edge morph is blocked by the SwiftUI
        // layer on top, and transition lags behind the drag ("catches up").
        // Present from the UIKit VC itself bypasses the SwiftUI bridge.
        for child in controller.children {
            if let result = walk(child) {
                return result
            }
        }
        return controller
    }
}
