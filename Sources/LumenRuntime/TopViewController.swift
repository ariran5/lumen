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
        // Спускаемся через children. Это критично для случая когда наш UIKit
        // content (FastAppHost'овский UINavigationController) висит как child
        // VC у SwiftUI'евского UIHostingController. Если present'ить от host
        // controller'а — iOS 26 sheet'у морф edge'ей мешает SwiftUI слой
        // поверх, и transition отстаёт от drag'а ("догоняет"). Present от
        // самого UIKit VC обходит SwiftUI bridge.
        for child in controller.children {
            if let result = walk(child) {
                return result
            }
        }
        return controller
    }
}
