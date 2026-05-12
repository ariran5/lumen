import Foundation
import JavaScriptCore

extension JSEngine {
    func installRenderBridge(renderer: Renderer) {
        guard let lumen = context.objectForKeyedSubscript("lumen") else { return }

        let render: @convention(block) (JSValue?) -> Void = { [weak renderer, weak self] tree in
            guard let renderer, let tree else { return }
            guard let node = RenderNode.parse(tree) else {
                MainActor.assumeIsolated {
                    self?.onLog?(.error, "lumen.render: invalid tree")
                }
                return
            }
            MainActor.assumeIsolated {
                renderer.render(node)
            }
        }
        lumen.setObject(render, forKeyedSubscript: "render" as NSString)
    }
}
