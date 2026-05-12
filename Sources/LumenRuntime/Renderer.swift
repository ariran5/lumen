import CoreGraphics
import Foundation
import QuartzCore

@MainActor
final class Renderer {
    let rootLayer: CALayer
    private var lastTree: RenderNode?

    private(set) var lastLayerCount: Int = 0
    private(set) var lastRenderMs: Double = 0

    init(rootLayer: CALayer) {
        self.rootLayer = rootLayer
        rootLayer.masksToBounds = true
    }

    func render(_ tree: RenderNode) {
        lastTree = tree
        relayout()
    }

    func relayout() {
        guard let tree = lastTree else { return }
        let size = rootLayer.bounds.size
        guard size.width > 0, size.height > 0 else { return }

        let start = CFAbsoluteTimeGetCurrent()

        let flex = buildFlex(tree)
        flex.calculateLayout(width: Double(size.width), height: Double(size.height))

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        rootLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        var counter = 0
        mount(node: tree, flex: flex, parent: rootLayer, parentOrigin: .zero, counter: &counter)
        lastLayerCount = counter

        CATransaction.commit()

        lastRenderMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
    }

    private func buildFlex(_ node: RenderNode) -> FlexNode {
        let f = FlexNode(style: node.style.flex)
        for child in node.children {
            f.add(buildFlex(child))
        }
        return f
    }

    private func mount(node: RenderNode,
                       flex: FlexNode,
                       parent: CALayer,
                       parentOrigin: CGPoint,
                       counter: inout Int) {
        let layer = CALayer()
        layer.frame = CGRect(
            x: flex.frame.minX - parentOrigin.x,
            y: flex.frame.minY - parentOrigin.y,
            width: flex.frame.width,
            height: flex.frame.height
        )
        applyVisualStyle(layer, style: node.style)
        parent.addSublayer(layer)
        counter += 1

        let myOrigin = CGPoint(x: flex.frame.minX, y: flex.frame.minY)
        for (cn, cf) in zip(node.children, flex.children) {
            mount(node: cn, flex: cf, parent: layer, parentOrigin: myOrigin, counter: &counter)
        }
    }

    private func applyVisualStyle(_ layer: CALayer, style: ViewStyle) {
        layer.backgroundColor = style.backgroundColor
        layer.cornerRadius = CGFloat(style.borderRadius)
        layer.opacity = Float(style.opacity)
        if let borderColor = style.borderColor {
            layer.borderColor = borderColor
            layer.borderWidth = CGFloat(style.borderWidth)
        }
        if style.borderRadius > 0 {
            layer.masksToBounds = true
        }
    }
}
