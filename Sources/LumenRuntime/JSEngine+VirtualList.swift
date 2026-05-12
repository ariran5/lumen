import Foundation
import JavaScriptCore
import UIKit

extension JSEngine {
    func installVirtualListBridge(onCreate: @escaping @MainActor (VirtualListController) -> Void) {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }

        let virtualList: @convention(block) (JSValue?) -> Void = { config in
            guard let config, !config.isUndefined, !config.isNull else { return }

            let countV = config.objectForKeyedSubscript("count")
            let count = Int(countV?.toInt32() ?? 0)

            let heightV = config.objectForKeyedSubscript("itemHeight")
            let itemHeight = CGFloat(heightV?.toDouble() ?? 50)

            guard let renderFn = config.objectForKeyedSubscript("render"),
                  renderFn.isObject else { return }

            let controller = VirtualListController(count: count,
                                                   itemHeight: itemHeight,
                                                   renderFn: renderFn)
            MainActor.assumeIsolated {
                onCreate(controller)
            }
        }
        lumen.setObject(virtualList, forKeyedSubscript: "virtualList" as NSString)
    }
}
