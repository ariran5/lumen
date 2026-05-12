import CoreGraphics
import Foundation
import JavaScriptCore
import QuartzCore
import UIKit

@MainActor
final class Renderer {
    let rootLayer: CALayer
    private weak var hostView: UIView?

    private var lastTree: RenderNode?

    private(set) var lastLayerCount: Int = 0
    private(set) var lastRenderMs: Double = 0

    private var tapHandlers: [ObjectIdentifier: JSValue] = [:]

    init(rootLayer: CALayer) {
        self.rootLayer = rootLayer
        rootLayer.masksToBounds = true
    }

    convenience init(hostView: UIView) {
        self.init(rootLayer: hostView.layer)
        self.hostView = hostView
        installTapGesture(on: hostView)
    }

    func render(_ tree: RenderNode) {
        lastTree = tree
        relayout()
    }

    /// Stop the renderer from re-applying its last tree (used when something
    /// else takes over the host view, e.g. lumen.virtualList mounts a
    /// UICollectionView as a subview).
    func detach() {
        lastTree = nil
        rootLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        tapHandlers.removeAll(keepingCapacity: false)
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
        tapHandlers.removeAll(keepingCapacity: true)
        var counter = 0
        mount(node: tree, flex: flex, parent: rootLayer, parentOrigin: .zero, counter: &counter)
        lastLayerCount = counter

        CATransaction.commit()

        lastRenderMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
    }

    private func buildFlex(_ node: RenderNode) -> FlexNode {
        let f = FlexNode(style: node.style.flex)
        if node.kind == .text, let text = node.text {
            let style = node.style
            f.measure = { available in
                TextMeasure.measure(text: text, style: style, maxWidth: available.width)
            }
        }
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
        let layer = makeLayer(for: node)
        layer.frame = CGRect(
            x: flex.frame.minX - parentOrigin.x,
            y: flex.frame.minY - parentOrigin.y,
            width: flex.frame.width,
            height: flex.frame.height
        )
        applyVisualStyle(layer, style: node.style)
        if node.kind == .text, let textLayer = layer as? CATextLayer, let text = node.text {
            applyTextStyle(textLayer, text: text, style: node.style)
        }
        if node.kind == .image, let src = node.source {
            applyImage(layer: layer, source: src, style: node.style)
        }
        if let onTap = node.onTap {
            tapHandlers[ObjectIdentifier(layer)] = onTap
        }
        parent.addSublayer(layer)
        counter += 1

        let myOrigin = CGPoint(x: flex.frame.minX, y: flex.frame.minY)
        for (cn, cf) in zip(node.children, flex.children) {
            mount(node: cn, flex: cf, parent: layer, parentOrigin: myOrigin, counter: &counter)
        }
    }

    private func makeLayer(for node: RenderNode) -> CALayer {
        switch node.kind {
        case .text:
            let layer = CATextLayer()
            layer.contentsScale = UIScreen.main.scale
            return layer
        default:
            return CALayer()
        }
    }

    private func applyTextStyle(_ layer: CATextLayer, text: String, style: ViewStyle) {
        layer.string = TextMeasure.attributedString(text, style: style)
        layer.isWrapped = true
        layer.truncationMode = .end
        layer.alignmentMode = textAlignmentMode(style.textAlign)
    }

    private func textAlignmentMode(_ s: String) -> CATextLayerAlignmentMode {
        switch s {
        case "center":  return .center
        case "right":   return .right
        case "justify": return .justified
        default:        return .left
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

    private func applyImage(layer: CALayer, source: String, style: ViewStyle) {
        switch style.contentMode {
        case "cover":    layer.contentsGravity = .resizeAspectFill
        case "contain":  layer.contentsGravity = .resizeAspect
        case "stretch":  layer.contentsGravity = .resize
        case "center":   layer.contentsGravity = .center
        default:         layer.contentsGravity = .resizeAspectFill
        }
        layer.masksToBounds = true

        guard let url = URL(string: source), let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else { return }

        let target = layer.bounds.size
        ImageLoader.shared.loadImage(url: url, targetSize: target) { [weak layer] image in
            guard let layer, let cgImage = image?.cgImage else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.contents = cgImage
            CATransaction.commit()
        }
    }

    // MARK: Tap handling

    private func installTapGesture(on host: UIView) {
        let proxy = TapProxy(owner: self)
        let recognizer = UITapGestureRecognizer(target: proxy, action: #selector(TapProxy.handle(_:)))
        recognizer.cancelsTouchesInView = false
        host.addGestureRecognizer(recognizer)
        // Keep proxy alive as long as the recognizer is alive. Without this,
        // the proxy is released when Renderer is deinit'd while the recognizer
        // is still attached to the host's view, and accessibility scans crash
        // following the unowned target ref.
        objc_setAssociatedObject(recognizer,
                                  &Renderer.tapProxyKey,
                                  proxy,
                                  .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private static var tapProxyKey: UInt8 = 0

    fileprivate func handleTap(at point: CGPoint) {
        guard !tapHandlers.isEmpty else { return }

        var current: CALayer? = rootLayer.hitTest(point)

        while let layer = current {
            if let handler = tapHandlers[ObjectIdentifier(layer)] {
                _ = handler.call(withArguments: [])
                return
            }
            current = layer.superlayer
        }
    }
}

@MainActor
private final class TapProxy: NSObject {
    weak var owner: Renderer?
    init(owner: Renderer) { self.owner = owner }

    @objc func handle(_ recognizer: UITapGestureRecognizer) {
        guard let owner, let view = recognizer.view else { return }
        let point = recognizer.location(in: view)
        owner.handleTap(at: point)
    }
}
