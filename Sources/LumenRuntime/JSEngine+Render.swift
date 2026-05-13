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

        // Per-node EffectScope cleanup: после reconcile рендерер batch'ит
        // снятые с маунта ids и пушит их в JS, который dispose'ит их
        // scope'ы. Без этого orphan effect'ы продолжали бы патчить layer'ы
        // по уже мёртвым id'шникам.
        renderer.onNodesDisposed = { [weak self] ids in
            guard let self else { return }
            guard let lumen = self.context.objectForKeyedSubscript("lumen"),
                  let dispose = lumen.objectForKeyedSubscript("_disposeNodes"),
                  !dispose.isUndefined else { return }
            _ = dispose.call(withArguments: [ids])
        }
    }
}
