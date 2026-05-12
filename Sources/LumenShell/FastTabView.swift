import SwiftUI
import UIKit

struct FastTabView: UIViewRepresentable {
    let script: String
    let onMetrics: ((Int, Double) -> Void)?

    init(script: String, onMetrics: ((Int, Double) -> Void)? = nil) {
        self.script = script
        self.onMetrics = onMetrics
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(script: script, onMetrics: onMetrics)
    }

    func makeUIView(context: Context) -> UIView {
        let v = LumenContainerView()
        v.backgroundColor = .systemBackground
        v.coordinator = context.coordinator

        let renderer = Renderer(rootLayer: v.layer)
        let engine = JSEngine()
        engine.installRenderBridge(renderer: renderer)

        context.coordinator.engine = engine
        context.coordinator.renderer = renderer
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.script = script
    }

    @MainActor
    final class Coordinator {
        var engine: JSEngine?
        var renderer: Renderer?
        var script: String
        var onMetrics: ((Int, Double) -> Void)?
        var didRunScript = false

        init(script: String, onMetrics: ((Int, Double) -> Void)?) {
            self.script = script
            self.onMetrics = onMetrics
        }

        func onLayout() {
            guard let engine, let renderer else { return }
            if !didRunScript {
                didRunScript = true
                _ = engine.eval(script)
            } else {
                renderer.relayout()
            }
            onMetrics?(renderer.lastLayerCount, renderer.lastRenderMs)
        }
    }
}

private final class LumenContainerView: UIView {
    weak var coordinator: FastTabView.Coordinator?
    private var lastBounds: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if bounds.size != lastBounds {
            lastBounds = bounds.size
            coordinator?.onLayout()
        }
    }
}
