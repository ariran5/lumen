import UIKit
@preconcurrency import JavaScriptCore

extension JSEngine {
    func installRouterBridge(navController: UINavigationController) {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }
        let router = JSValue(newObjectIn: context)!

        let navRef = WeakNavRef(navController)

        let push: @convention(block) (JSValue?) -> Void = { config in
            guard let config, !config.isUndefined, !config.isNull else { return }
            let title = config.objectForKeyedSubscript("title")?.toString()
            let renderFn = config.objectForKeyedSubscript("render")
            let onPop = config.objectForKeyedSubscript("onPop")

            let cleanTitle: String? = (title?.isEmpty == false && title != "undefined") ? title : nil
            let cleanRender = (renderFn?.isObject == true) ? renderFn : nil
            let cleanPop = (onPop?.isObject == true) ? onPop : nil

            MainActor.assumeIsolated {
                guard let nav = navRef.value else { return }
                let page = LumenPageViewController(title: cleanTitle,
                                                   renderFn: cleanRender,
                                                   onPop: cleanPop)
                nav.pushViewController(page, animated: true)
            }
        }
        router.setObject(push, forKeyedSubscript: "push" as NSString)

        let pop: @convention(block) () -> Void = {
            MainActor.assumeIsolated {
                _ = navRef.value?.popViewController(animated: true)
            }
        }
        router.setObject(pop, forKeyedSubscript: "pop" as NSString)

        let popToRoot: @convention(block) () -> Void = {
            MainActor.assumeIsolated {
                _ = navRef.value?.popToRootViewController(animated: true)
            }
        }
        router.setObject(popToRoot, forKeyedSubscript: "popToRoot" as NSString)

        let setTitle: @convention(block) (String?) -> Void = { newTitle in
            MainActor.assumeIsolated {
                navRef.value?.topViewController?.title = newTitle
            }
        }
        router.setObject(setTitle, forKeyedSubscript: "setTitle" as NSString)

        lumen.setObject(router, forKeyedSubscript: "router" as NSString)
    }
}

@MainActor
private final class WeakNavRef {
    weak var value: UINavigationController?
    init(_ value: UINavigationController) { self.value = value }
}
