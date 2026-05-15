import JavaScriptCore
import QuartzCore
import UIKit

/// Handler cache per CALayer. Renderer updates on every mount/reconcile.
@MainActor
struct LayerGestures {
    var onTap: JSValue?
    var onDoubleTap: JSValue?
    var onLongPress: JSValue?
    var onPan: JSValue?
    var onSwipe: JSValue?
    var onPinch: JSValue?
    var onRotate: JSValue?

    var hasAny: Bool {
        onTap != nil || onDoubleTap != nil || onLongPress != nil ||
        onPan != nil || onSwipe != nil || onPinch != nil || onRotate != nil
    }
}

/// One per rootLayer: attaches all needed UIGestureRecognizers to hostView
/// and on each firing does a hit-test through the CALayer tree, finds the target node,
/// calls the matching JS handler with an event object.
///
/// Advantage — N recognizers on hostView, not N×K on each layer.
@MainActor
final class GestureRouter: NSObject, UIGestureRecognizerDelegate {

    private weak var host: UIView?
    private weak var rootLayer: CALayer?
    private var handlers: [ObjectIdentifier: LayerGestures] = [:]

    private var singleTap: UITapGestureRecognizer?
    private var doubleTap: UITapGestureRecognizer?
    private var longPress: UILongPressGestureRecognizer?
    private var pan: UIPanGestureRecognizer?
    private var pinch: UIPinchGestureRecognizer?
    private var rotate: UIRotationGestureRecognizer?
    private var swipes: [UISwipeGestureRecognizer] = []

    // pan "captures" the layer on .began and holds it until cycle end,
    // so coordinates stay relative to the same node
    private weak var panLayer: CALayer?

    private static var routerKey: UInt8 = 0

    init(host: UIView, rootLayer: CALayer) {
        self.host = host
        self.rootLayer = rootLayer
        super.init()
        install()
        // gesture recognizers refer to target via unowned — need a strong ref,
        // otherwise after Renderer deinit the a11y scanner hits a dangling pointer.
        objc_setAssociatedObject(host, &GestureRouter.routerKey,
                                  self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    func setHandlers(_ gestures: LayerGestures, for layer: CALayer) {
        let key = ObjectIdentifier(layer)
        if gestures.hasAny {
            handlers[key] = gestures
        } else {
            handlers.removeValue(forKey: key)
        }
    }

    func removeHandlers(for layer: CALayer) {
        handlers.removeValue(forKey: ObjectIdentifier(layer))
    }

    func clear() {
        handlers.removeAll(keepingCapacity: false)
    }

    // MARK: - Setup

    private func install() {
        guard let host else { return }

        // Single tap — without require(toFail: doubleTap), fires immediately.
        // DoubleTap is removed for now because on real hardware its recognizer
        // conflicts with single tap and steals events. Will return later via
        // custom touch handling.
        let st = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        st.cancelsTouchesInView = false
        st.delegate = self
        host.addGestureRecognizer(st)
        singleTap = st

        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        lp.minimumPressDuration = 0.45
        lp.cancelsTouchesInView = false
        lp.delegate = self
        host.addGestureRecognizer(lp)
        longPress = lp

        let pn = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pn.cancelsTouchesInView = false
        pn.delegate = self
        // tap must "win" against pan for micro finger movements on nodes
        // that specifically have onTap. This is solved via
        // gestureRecognizerShouldBegin below — pan won't activate on nodes
        // without onPan, so the "pan steals tap" conflict only appears
        // when one node has both onTap and onPan (rare case).
        host.addGestureRecognizer(pn)
        pan = pn

        let pi = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pi.cancelsTouchesInView = false
        pi.delegate = self
        host.addGestureRecognizer(pi)
        pinch = pi

        let ro = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
        ro.cancelsTouchesInView = false
        ro.delegate = self
        host.addGestureRecognizer(ro)
        rotate = ro

        for dir: UISwipeGestureRecognizer.Direction in [.left, .right, .up, .down] {
            let sw = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            sw.direction = dir
            sw.cancelsTouchesInView = false
            sw.delegate = self
            host.addGestureRecognizer(sw)
            swipes.append(sw)
        }
    }

    /// Recognizer activates only if under the initial touch point there's
    /// a node with the matching handler. This removes interference between
    /// pan / swipe / pinch — each only fires on its "own" nodes.
    nonisolated func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let view = gestureRecognizer.view else { return true }
        let point = gestureRecognizer.location(in: view)

        return MainActor.assumeIsolated {
            guard let rootLayer = self.rootLayer else { return true }

            let predicate: (LayerGestures) -> Bool
            if gestureRecognizer is UIPanGestureRecognizer {
                predicate = { $0.onPan != nil }
            } else if gestureRecognizer is UISwipeGestureRecognizer {
                predicate = { $0.onSwipe != nil }
            } else if gestureRecognizer is UIPinchGestureRecognizer {
                predicate = { $0.onPinch != nil }
            } else if gestureRecognizer is UIRotationGestureRecognizer {
                predicate = { $0.onRotate != nil }
            } else if gestureRecognizer is UILongPressGestureRecognizer {
                predicate = { $0.onLongPress != nil }
            } else if gestureRecognizer is UITapGestureRecognizer {
                predicate = { $0.onTap != nil }
            } else {
                return true
            }
            return self.hitTest(rootLayer: rootLayer, point: point, where: predicate) != nil
        }
    }

    // Delegate: allow pinch+rotate simultaneously (typical gesture), others
    // are mutually exclusive (UIKit defaults).
    nonisolated func gestureRecognizer(_ a: UIGestureRecognizer,
                                       shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool {
        let aIsPinchRot = a is UIPinchGestureRecognizer || a is UIRotationGestureRecognizer
        let bIsPinchRot = b is UIPinchGestureRecognizer || b is UIRotationGestureRecognizer
        return aIsPinchRot && bIsPinchRot
    }

    // MARK: - Tap family

    @objc private func handleSingleTap(_ r: UITapGestureRecognizer) {
        guard let view = r.view, let rootLayer else { return }
        let p = r.location(in: view)
        if let (layer, _) = hitTest(rootLayer: rootLayer, point: p, where: { $0.onTap != nil }) {
            fire(handlers[ObjectIdentifier(layer)]?.onTap, with: tapEvent(layer: layer, hostPoint: p, view: view))
        }
    }

    @objc private func handleDoubleTap(_ r: UITapGestureRecognizer) {
        guard let view = r.view, let rootLayer else { return }
        let p = r.location(in: view)
        if let (layer, _) = hitTest(rootLayer: rootLayer, point: p, where: { $0.onDoubleTap != nil }) {
            fire(handlers[ObjectIdentifier(layer)]?.onDoubleTap, with: tapEvent(layer: layer, hostPoint: p, view: view))
        }
    }

    @objc private func handleLongPress(_ r: UILongPressGestureRecognizer) {
        guard r.state == .began else { return }
        guard let view = r.view, let rootLayer else { return }
        let p = r.location(in: view)
        if let (layer, _) = hitTest(rootLayer: rootLayer, point: p, where: { $0.onLongPress != nil }) {
            fire(handlers[ObjectIdentifier(layer)]?.onLongPress,
                 with: tapEvent(layer: layer, hostPoint: p, view: view))
        }
    }

    // MARK: - Pan

    @objc private func handlePan(_ r: UIPanGestureRecognizer) {
        guard let view = r.view, let rootLayer else { return }

        let hostPoint = r.location(in: view)
        let translation = r.translation(in: view)
        let velocity = r.velocity(in: view)

        switch r.state {
        case .began:
            if let (layer, _) = hitTest(rootLayer: rootLayer, point: hostPoint, where: { $0.onPan != nil }) {
                panLayer = layer
            } else {
                panLayer = nil
                return
            }
            dispatchPan(state: "start", hostPoint: hostPoint,
                        translation: translation, velocity: velocity, view: view)
        case .changed:
            dispatchPan(state: "changed", hostPoint: hostPoint,
                        translation: translation, velocity: velocity, view: view)
        case .ended:
            dispatchPan(state: "ended", hostPoint: hostPoint,
                        translation: translation, velocity: velocity, view: view)
            panLayer = nil
        case .cancelled, .failed:
            dispatchPan(state: "cancelled", hostPoint: hostPoint,
                        translation: translation, velocity: velocity, view: view)
            panLayer = nil
        default:
            break
        }
    }

    private func dispatchPan(state: String,
                              hostPoint: CGPoint,
                              translation: CGPoint,
                              velocity: CGPoint,
                              view: UIView) {
        guard let layer = panLayer else { return }
        let local = view.layer.convert(hostPoint, to: layer)
        let event: [String: Any] = [
            "state": state,
            "x": Double(local.x),
            "y": Double(local.y),
            "dx": Double(translation.x),
            "dy": Double(translation.y),
            "vx": Double(velocity.x),
            "vy": Double(velocity.y),
        ]
        fire(handlers[ObjectIdentifier(layer)]?.onPan, with: event)
    }

    // MARK: - Swipe

    @objc private func handleSwipe(_ r: UISwipeGestureRecognizer) {
        guard let view = r.view, let rootLayer else { return }
        let hostPoint = r.location(in: view)
        guard let (layer, _) = hitTest(rootLayer: rootLayer, point: hostPoint,
                                       where: { $0.onSwipe != nil }) else { return }
        let dirString: String
        switch r.direction {
        case .left: dirString = "left"
        case .right: dirString = "right"
        case .up: dirString = "up"
        case .down: dirString = "down"
        default: dirString = "unknown"
        }
        let local = view.layer.convert(hostPoint, to: layer)
        let event: [String: Any] = [
            "direction": dirString,
            "x": Double(local.x),
            "y": Double(local.y),
        ]
        fire(handlers[ObjectIdentifier(layer)]?.onSwipe, with: event)
    }

    // MARK: - Pinch / Rotate

    @objc private func handlePinch(_ r: UIPinchGestureRecognizer) {
        guard let view = r.view, let rootLayer else { return }
        let p = r.location(in: view)
        guard let (layer, _) = hitTest(rootLayer: rootLayer, point: p,
                                       where: { $0.onPinch != nil }) else { return }
        let event: [String: Any] = [
            "state": phaseString(r.state),
            "scale": Double(r.scale),
            "velocity": Double(r.velocity),
        ]
        fire(handlers[ObjectIdentifier(layer)]?.onPinch, with: event)
    }

    @objc private func handleRotate(_ r: UIRotationGestureRecognizer) {
        guard let view = r.view, let rootLayer else { return }
        let p = r.location(in: view)
        guard let (layer, _) = hitTest(rootLayer: rootLayer, point: p,
                                       where: { $0.onRotate != nil }) else { return }
        let event: [String: Any] = [
            "state": phaseString(r.state),
            "rotation": Double(r.rotation),
            "velocity": Double(r.velocity),
        ]
        fire(handlers[ObjectIdentifier(layer)]?.onRotate, with: event)
    }

    private func phaseString(_ s: UIGestureRecognizer.State) -> String {
        switch s {
        case .began: return "start"
        case .changed: return "changed"
        case .ended: return "ended"
        case .cancelled, .failed: return "cancelled"
        default: return "unknown"
        }
    }

    // MARK: - Hit test + dispatch

    private func tapEvent(layer: CALayer, hostPoint: CGPoint, view: UIView) -> [String: Any] {
        let local = view.layer.convert(hostPoint, to: layer)
        return ["x": Double(local.x), "y": Double(local.y)]
    }

    /// Custom hit-test: recursively find the deepest layer under the point
    /// that has the needed handler registered. Apple's CALayer.hitTest
    /// expects point in superlayer's coord system — in our case that's
    /// inconvenient and behavior is unstable. Our walker is explicit and precise.
    private func hitTest(rootLayer: CALayer, point: CGPoint,
                         where match: (LayerGestures) -> Bool) -> (CALayer, LayerGestures)? {
        return walk(layer: rootLayer, pointInLayer: point, match: match)
    }

    private func walk(layer: CALayer, pointInLayer: CGPoint,
                       match: (LayerGestures) -> Bool) -> (CALayer, LayerGestures)? {
        // First search children (deepest first, natural z-order),
        // then self.
        if let sublayers = layer.sublayers {
            for sublayer in sublayers.reversed() {
                guard sublayer.frame.contains(pointInLayer) else { continue }
                let sublayerPoint = CGPoint(
                    x: pointInLayer.x - sublayer.frame.minX,
                    y: pointInLayer.y - sublayer.frame.minY
                )
                if let result = walk(layer: sublayer,
                                     pointInLayer: sublayerPoint,
                                     match: match) {
                    return result
                }
            }
        }
        if let g = handlers[ObjectIdentifier(layer)], match(g) {
            return (layer, g)
        }
        return nil
    }

    private func fire(_ handler: JSValue?, with event: [String: Any]) {
        guard let handler else { return }
        _ = handler.call(withArguments: [event])
    }
}
