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

        // Per-node EffectScope cleanup: after reconcile renderer batches
        // unmounted ids and pushes them to JS, which disposes their
        // scopes. Without this orphan effects would keep patching layers
        // by already-dead ids.
        renderer.onNodesDisposed = { [weak self] ids in
            guard let self else { return }
            guard let lumen = self.context.objectForKeyedSubscript("lumen"),
                  let dispose = lumen.objectForKeyedSubscript("_disposeNodes"),
                  !dispose.isUndefined else { return }
            _ = dispose.call(withArguments: [ids])
        }
    }
}
