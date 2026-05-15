import Foundation
import QuartzCore
import UIKit

/// Registry AnimatedValue ↔ CALayer + off-main animations via CABasicAnimation /
/// CASpringAnimation. Main feature — animations run on the render server
/// (backboardd) independently of the main thread: even if JS stalls for 200ms,
/// motion doesn't stutter.
///
/// The binding `(layer, property) → animId` is set by the renderer on apply,
/// removed on removeMountTree. When AnimatedValue.set / .animateTo / .stop
/// is called from JS, AnimationManager iterates all bound layers and
/// applies the new value (with or without animation).
@MainActor
final class AnimationManager {
    static let shared = AnimationManager()

    enum Property: String, Hashable {
        case translateX, translateY, scale, scaleX, scaleY, rotate, opacity
        var isTransform: Bool { self != .opacity }
    }

    /// One CALayer's bindings to animatable properties. Static values
    /// are needed as fallback when composing the transform — if out of 3 transform fields
    /// only translateX is animated, Y/scale/rotate come from statics.
    private struct LayerState {
        weak var layer: CALayer?
        var animIds: [Property: Int] = [:]
        var staticTranslateX: Double = 0
        var staticTranslateY: Double = 0
        var staticScale: Double = 1
        var staticScaleX: Double = 1
        var staticScaleY: Double = 1
        var staticRotate: Double = 0
        var staticOpacity: Double = 1
    }

    private struct AnimNode {
        var current: Double
        var layerIds: Set<ObjectIdentifier> = []
    }

    private var nodes: [Int: AnimNode] = [:]
    private var layers: [ObjectIdentifier: LayerState] = [:]

    // MARK: - Lifecycle

    func register(id: Int, initial: Double) {
        if nodes[id] == nil {
            nodes[id] = AnimNode(current: initial)
        }
    }

    func release(id: Int) {
        // Bindings remain on the layers side; they drop on unbindLayer.
        nodes.removeValue(forKey: id)
    }

    /// Full reset — called on hot-reload when we drop JSEngine.
    /// Otherwise on next load ids start at 1 and clash with old entries.
    func reset() {
        nodes.removeAll(keepingCapacity: false)
        layers.removeAll(keepingCapacity: false)
    }

    func current(id: Int) -> Double {
        nodes[id]?.current ?? 0
    }

    // MARK: - Renderer integration

    /// Registers a layer with the given set of animated bindings + static
    /// fallbacks. Fully overwrites state for this layer.
    /// After registration applies composed transform/opacity immediately
    /// (without animation) — this is initial mount or reconcile snapshot.
    func bindLayer(_ layer: CALayer,
                   animIds: [Property: Int],
                   staticTranslateX: Double,
                   staticTranslateY: Double,
                   staticScale: Double,
                   staticScaleX: Double,
                   staticScaleY: Double,
                   staticRotate: Double,
                   staticOpacity: Double) {
        let lid = ObjectIdentifier(layer)

        // Detach old animId bindings: remove reference from node.layerIds
        if let old = layers[lid] {
            for (_, animId) in old.animIds {
                nodes[animId]?.layerIds.remove(lid)
            }
        }

        let state = LayerState(layer: layer,
                               animIds: animIds,
                               staticTranslateX: staticTranslateX,
                               staticTranslateY: staticTranslateY,
                               staticScale: staticScale,
                               staticScaleX: staticScaleX,
                               staticScaleY: staticScaleY,
                               staticRotate: staticRotate,
                               staticOpacity: staticOpacity)
        layers[lid] = state

        for (_, animId) in animIds {
            nodes[animId, default: AnimNode(current: 0)].layerIds.insert(lid)
        }

        applyComposed(layerId: lid, animated: false, animId: nil, duration: 0, easing: "linear")
    }

    func unbindLayer(_ layer: CALayer) {
        let lid = ObjectIdentifier(layer)
        if let state = layers[lid] {
            for (_, animId) in state.animIds {
                nodes[animId]?.layerIds.remove(lid)
            }
        }
        layers.removeValue(forKey: lid)
    }

    // MARK: - AnimatedValue API

    func set(id: Int, value: Double) {
        guard var node = nodes[id] else { return }
        node.current = value
        nodes[id] = node
        for layerId in node.layerIds {
            // Remove any in-flight animation for this animId (set overrides animation)
            removeAnimations(layerId: layerId, animId: id)
            applyComposed(layerId: layerId,
                          animated: false,
                          animId: id,
                          duration: 0,
                          easing: "linear")
        }
    }

    func animateTo(id: Int, value: Double, duration: Double, easing: String) {
        guard var node = nodes[id] else { return }
        node.current = value
        nodes[id] = node
        for layerId in node.layerIds {
            applyComposed(layerId: layerId,
                          animated: true,
                          animId: id,
                          duration: duration,
                          easing: easing)
        }
    }

    func stop(id: Int) {
        guard var node = nodes[id] else { return }

        // Capture the presentation value from the first live binding,
        // so JS-side .current() sees the actual visual position.
        var presentationValue: Double?
        outer: for layerId in node.layerIds {
            guard let state = layers[layerId], let layer = state.layer else { continue }
            for (prop, aid) in state.animIds where aid == id {
                if let v = readPresentation(layer: layer, property: prop, state: state) {
                    presentationValue = v
                    break outer
                }
            }
        }

        if let pv = presentationValue {
            node.current = pv
            nodes[id] = node
        }

        for layerId in node.layerIds {
            removeAnimations(layerId: layerId, animId: id)
            applyComposed(layerId: layerId,
                          animated: false,
                          animId: id,
                          duration: 0,
                          easing: "linear")
        }
    }

    // MARK: - Composition

    /// Composite transform + opacity for one layer:
    ///   - if property is animated → take nodes[animId].current
    ///   - otherwise → static fallback
    /// Applies either instantly (CATransaction disable) or as
    /// CABasicAnimation/CASpringAnimation from presentation → new.
    private func applyComposed(layerId: ObjectIdentifier,
                               animated: Bool,
                               animId: Int?,
                               duration: Double,
                               easing: String) {
        guard let state = layers[layerId], let layer = state.layer else { return }

        let newTransform = composedTransform(state: state)
        let newOpacity = composedOpacity(state: state)

        if !animated {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if !CATransform3DEqualToTransform(layer.transform, newTransform) {
                layer.transform = newTransform
            }
            if layer.opacity != newOpacity {
                layer.opacity = newOpacity
            }
            CATransaction.commit()
            return
        }

        guard let animId else { return }

        // Which properties this particular animId animates on this layer?
        var animatesTransform = false
        var animatesOpacity = false
        for (prop, aid) in state.animIds where aid == animId {
            if prop == .opacity { animatesOpacity = true }
            else { animatesTransform = true }
        }

        let presentation = layer.presentation()
        let fromTransform: CATransform3D = presentation?.transform ?? layer.transform
        let fromOpacity: Float = presentation?.opacity ?? layer.opacity

        // First set the new model (without implicit animations),
        // then overlay explicit CABasicAnimation from presentation → new.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = newTransform
        layer.opacity = newOpacity
        CATransaction.commit()

        if animatesTransform {
            addAnimation(layer: layer,
                         keyPath: "transform",
                         from: NSValue(caTransform3D: fromTransform),
                         to: NSValue(caTransform3D: newTransform),
                         duration: duration,
                         easing: easing,
                         key: "lumen-anim-\(animId)-t")
        }
        if animatesOpacity {
            addAnimation(layer: layer,
                         keyPath: "opacity",
                         from: NSNumber(value: fromOpacity),
                         to: NSNumber(value: newOpacity),
                         duration: duration,
                         easing: easing,
                         key: "lumen-anim-\(animId)-o")
        }
    }

    private func composedTransform(state: LayerState) -> CATransform3D {
        let tx = animOrStatic(state.animIds[.translateX], static: state.staticTranslateX)
        let ty = animOrStatic(state.animIds[.translateY], static: state.staticTranslateY)
        let s  = animOrStatic(state.animIds[.scale],      static: state.staticScale)
        let sx = animOrStatic(state.animIds[.scaleX],     static: state.staticScaleX)
        let sy = animOrStatic(state.animIds[.scaleY],     static: state.staticScaleY)
        let r  = animOrStatic(state.animIds[.rotate],     static: state.staticRotate)

        var m = CATransform3DIdentity
        m = CATransform3DTranslate(m, CGFloat(tx), CGFloat(ty), 0)
        if r != 0 { m = CATransform3DRotate(m, CGFloat(r), 0, 0, 1) }
        let totalSX = sx * s
        let totalSY = sy * s
        if totalSX != 1 || totalSY != 1 {
            m = CATransform3DScale(m, CGFloat(totalSX), CGFloat(totalSY), 1)
        }
        return m
    }

    private func composedOpacity(state: LayerState) -> Float {
        Float(animOrStatic(state.animIds[.opacity], static: state.staticOpacity))
    }

    private func animOrStatic(_ animId: Int?, static staticVal: Double) -> Double {
        guard let id = animId else { return staticVal }
        return nodes[id]?.current ?? staticVal
    }

    // MARK: - Presentation read-out

    /// Read the current visual value for the given property from the
    /// layer's presentation. Used in .stop() — otherwise removing the
    /// CABasicAnimation would snap the layer to model-value (target).
    private func readPresentation(layer: CALayer,
                                  property: Property,
                                  state: LayerState) -> Double? {
        guard let p = layer.presentation() else { return nil }
        switch property {
        case .opacity:
            return Double(p.opacity)
        case .translateX:
            return Double(p.transform.m41)
        case .translateY:
            return Double(p.transform.m42)
        case .scale, .scaleX:
            let m = p.transform
            let sx = sqrt(Double(m.m11 * m.m11 + m.m12 * m.m12))
            return sx
        case .scaleY:
            let m = p.transform
            let sy = sqrt(Double(m.m21 * m.m21 + m.m22 * m.m22))
            return sy
        case .rotate:
            return Double(atan2(Double(p.transform.m12), Double(p.transform.m11)))
        }
    }

    // MARK: - Animation helpers

    private func removeAnimations(layerId: ObjectIdentifier, animId: Int) {
        guard let state = layers[layerId], let layer = state.layer else { return }
        layer.removeAnimation(forKey: "lumen-anim-\(animId)-t")
        layer.removeAnimation(forKey: "lumen-anim-\(animId)-o")
    }

    private func addAnimation(layer: CALayer,
                              keyPath: String,
                              from: Any,
                              to: Any,
                              duration: Double,
                              easing: String,
                              key: String) {
        let anim: CABasicAnimation
        if easing == "spring" {
            let spring = CASpringAnimation(keyPath: keyPath)
            spring.mass = 1
            spring.stiffness = 200
            spring.damping = 18
            spring.initialVelocity = 0
            // settling duration is auto-computed by CA based on spring parameters
            spring.duration = spring.settlingDuration
            anim = spring
        } else {
            let ba = CABasicAnimation(keyPath: keyPath)
            ba.duration = max(0.001, duration / 1000.0)
            switch easing {
            case "linear":
                ba.timingFunction = CAMediaTimingFunction(name: .linear)
            case "easeIn":
                ba.timingFunction = CAMediaTimingFunction(name: .easeIn)
            case "easeInOut":
                ba.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            case "easeOut":
                fallthrough
            default:
                ba.timingFunction = CAMediaTimingFunction(name: .easeOut)
            }
            anim = ba
        }

        anim.fromValue = from
        anim.toValue = to
        anim.fillMode = .removed
        anim.isRemovedOnCompletion = true

        layer.removeAnimation(forKey: key)
        layer.add(anim, forKey: key)
    }
}
