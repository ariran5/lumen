import CoreGraphics
import Foundation
import JavaScriptCore
import MapKit
import QuartzCore
import UIKit

/// Mounted-tree node. Mirrors RenderNode but holds a live
/// CALayer and current state — on this the diff can reuse
/// layers across renders without dropping sublayers/animations/contents.
@MainActor
final class MountedNode {
    var node: RenderNode
    var layer: CALayer
    var children: [MountedNode]
    var loadedImageSource: String?

    // virtualList overlay: UICollectionView sits as a subview of hostView,
    // its frame is driven by `layer` in absolute coordinates of rootLayer.
    var virtualListView: VirtualListView?
    var virtualListController: VirtualListController?

    // textInput overlay: native UITextField as a subview of hostView.
    var textInputView: LumenTextField?
    var textInputController: TextInputController?

    // scroll overlay: UIScrollView with a nested Renderer inside contentView.
    var scrollView: LumenScrollView?

    // blur overlay: UIVisualEffectView with a nested Renderer inside contentView.
    var blurView: LumenBlurView?

    // map overlay: MKMapView with region/pins/events.
    var mapView: LumenMapView?

    init(node: RenderNode, layer: CALayer) {
        self.node = node
        self.layer = layer
        self.children = []
    }
}

@MainActor
final class Renderer {
    enum ContentMode {
        /// Child nodes stretch to parent bounds (standard mode).
        case stretch
        /// Layout is computed with `height: .greatestFiniteMagnitude` — needed for
        /// scroll content where height is determined by the sum of children, not the parent.
        /// `computedContentHeight()` returns the actual height after layout.
        case scrollContent
    }

    let rootLayer: CALayer
    private weak var hostView: UIView?

    var contentMode: ContentMode = .stretch

    private var lastTree: RenderNode?
    private var mountedRoot: MountedNode?
    private var lastFlexRoot: FlexNode?

    private(set) var lastLayerCount: Int = 0
    private(set) var lastRenderMs: Double = 0
    private(set) var lastDiffMs: Double = 0

    /// Global node-id → MountedNode index. Used for fine-grained
    /// JS bindings: `lumen._patchProp(id, key, val)` finds the CALayer and
    /// applies one property without a full reconcile walk.
    @MainActor static var nodeIndex: [Int: WeakMountedRef] = [:]
    @MainActor
    final class WeakMountedRef {
        weak var node: MountedNode?
        weak var renderer: Renderer?
        init(_ n: MountedNode, _ r: Renderer) { self.node = n; self.renderer = r }
    }

    private var gestureRouter: GestureRouter?

    init(rootLayer: CALayer) {
        self.rootLayer = rootLayer
        rootLayer.masksToBounds = true
    }

    convenience init(hostView: UIView) {
        self.init(rootLayer: hostView.layer)
        self.hostView = hostView
        gestureRouter = GestureRouter(host: hostView, rootLayer: hostView.layer)
    }

    /// Hook called after `replaceChildren`/`relayout`. Used by
    /// LumenScrollView to recompute contentSize when a slot has changed
    /// the number of children.
    var onAfterLayout: (@MainActor () -> Void)?

    /// Callback after reconcile/replaceChildren with ids of nodes that
    /// were unmounted. JS side uses this to dispose
    /// per-node EffectScopes (see `nodeScopes` in CoreFramework).
    var onNodesDisposed: (@MainActor ([Int]) -> Void)?

    /// Accumulates ids between reconcile steps. Flushed at the end of
    /// `relayout()` and `replaceChildren()` as a single batch call.
    private var disposalBuffer: [Int] = []

    /// Replaces children of the node with the given id, mutates lastTree, and
    /// runs relayout. Used by Slot thunks via `lumen._replaceChildren`.
    func replaceChildren(id: Int, newChildren: [RenderNode]) {
        guard var tree = lastTree else { return }
        if Self.mutateChildren(&tree, id: id, newChildren: newChildren) {
            lastTree = tree
            relayout()
            onAfterLayout?()
            flushDisposalBuffer()
        }
    }

    /// Updates the node's text in lastTree + runs relayout. Without this
    /// patch only changes CATextLayer.string, leaving the old frame —
    /// long new text gets truncated to the old intrinsic.
    func patchText(id: Int, text: String) {
        guard var tree = lastTree else { return }
        if Self.mutateText(&tree, id: id, text: text) {
            lastTree = tree
            relayout()
            onAfterLayout?()
        }
    }

    private static func mutateText(_ node: inout RenderNode, id: Int, text: String) -> Bool {
        if node.id == id {
            node.text = text
            return true
        }
        for i in 0..<node.children.count {
            if mutateText(&node.children[i], id: id, text: text) {
                return true
            }
        }
        return false
    }

    private func flushDisposalBuffer() {
        guard !disposalBuffer.isEmpty else { return }
        let ids = disposalBuffer
        disposalBuffer.removeAll(keepingCapacity: true)
        onNodesDisposed?(ids)
    }

    private static func mutateChildren(_ node: inout RenderNode,
                                        id: Int,
                                        newChildren: [RenderNode]) -> Bool {
        if node.id == id {
            node.children = newChildren
            return true
        }
        for i in 0..<node.children.count {
            if mutateChildren(&node.children[i], id: id, newChildren: newChildren) {
                return true
            }
        }
        return false
    }

    /// Returns the maximum Y-extent of the root's children + bottom padding.
    /// Used by ScrollView to determine contentSize.
    func computedContentHeight() -> CGFloat {
        guard let root = lastFlexRoot else { return 0 }
        let maxY = root.children.map { $0.frame.maxY }.max() ?? 0
        return maxY + CGFloat(root.style.padding.bottom)
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
        mountedRoot = nil
        rootLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        gestureRouter?.clear()
    }

    func relayout() {
        guard let tree = lastTree else { return }
        var size = rootLayer.bounds.size
        guard size.width > 0 else { return }
        if contentMode == .scrollContent {
            // Scroll mode: height must not constrain layout. Children
            // get their intrinsic sizes and naturally stack from the top.
            size.height = .greatestFiniteMagnitude
        } else if size.height <= 0 {
            return
        }

        let start = CFAbsoluteTimeGetCurrent()

        let flex = buildFlex(tree)
        flex.calculateLayout(width: Double(size.width), height: Double(size.height))
        lastFlexRoot = flex

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        var counter = 0
        if let root = mountedRoot {
            reconcile(parent: rootLayer,
                      parentOrigin: .zero,
                      mounted: root,
                      next: tree,
                      flex: flex,
                      counter: &counter)
        } else {
            mountedRoot = mountFresh(parent: rootLayer,
                                     parentOrigin: .zero,
                                     node: tree,
                                     flex: flex,
                                     counter: &counter)
        }
        lastLayerCount = counter

        CATransaction.commit()

        // Z-order fix for UIView-backed nodes (ScrollView/Blur/VirtualList/Map/
        // TextInput). They all live as flat sublayers of `hostView` (not
        // nested in the layer-tree of the parent View), and `addSubview` always
        // puts the view on top. If TabBar.Glass mounted first and
        // then a ScrollView on another page, ScrollView covers
        // the TabBar and taps don't reach it.
        // Walk the tree DFS and align subview-order with the tree order.
        if let host = hostView, let root = mountedRoot {
            reorderEmbeddedViews(in: host, mount: root)
        }

        lastRenderMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        RenderMetrics.shared.record(lastRenderMs)

        flushDisposalBuffer()
    }

    /// Pre-order DFS: every UIView-backed node encountered is brought to the
    /// front of `host.subviews` via `bringSubviewToFront`. After the walk the last
    /// (deepest-rightmost) node ends up on top — matching
    /// child order in the RenderNode tree.
    private func reorderEmbeddedViews(in host: UIView, mount: MountedNode) {
        if let v = mount.scrollView      { host.bringSubviewToFront(v) }
        if let v = mount.blurView        { host.bringSubviewToFront(v) }
        if let v = mount.virtualListView { host.bringSubviewToFront(v) }
        if let v = mount.mapView         { host.bringSubviewToFront(v) }
        if let v = mount.textInputView   { host.bringSubviewToFront(v) }
        for child in mount.children {
            reorderEmbeddedViews(in: host, mount: child)
        }
    }

    // MARK: - Flex tree

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

    // MARK: - Fresh mount

    private func mountFresh(parent: CALayer,
                            parentOrigin: CGPoint,
                            node: RenderNode,
                            flex: FlexNode,
                            counter: inout Int) -> MountedNode {
        let layer = makeLayer(for: node)
        parent.addSublayer(layer)
        let mount = MountedNode(node: node, layer: layer)
        if let nid = node.id {
            Self.nodeIndex[nid] = WeakMountedRef(mount, self)
        }
        applyAll(layer: layer, mount: mount, node: node, flex: flex, parentOrigin: parentOrigin)
        counter += 1

        if node.kind == .virtualList {
            mountVirtualList(mount: mount, node: node, flex: flex)
            return mount  // virtualList has no CALayer children
        }

        if node.kind == .textInput {
            mountTextInput(mount: mount, node: node, flex: flex)
            return mount
        }

        if node.kind == .scroll {
            mountScroll(mount: mount, node: node, flex: flex)
            return mount
        }

        if node.kind == .blur {
            mountBlur(mount: mount, node: node, flex: flex)
            return mount
        }

        if node.kind == .map {
            mountMap(mount: mount, node: node, flex: flex)
            return mount
        }

        let myOrigin = CGPoint(x: flex.frame.minX, y: flex.frame.minY)
        for (cn, cf) in zip(node.children, flex.children) {
            let cm = mountFresh(parent: layer,
                                parentOrigin: myOrigin,
                                node: cn,
                                flex: cf,
                                counter: &counter)
            mount.children.append(cm)
        }
        return mount
    }

    private func mountVirtualList(mount: MountedNode, node: RenderNode, flex: FlexNode) {
        guard let host = hostView, let renderFn = node.listRenderFn else { return }
        let absoluteFrame = flex.frame
        let controller = VirtualListController(count: node.listCount,
                                               itemHeight: node.listItemHeight,
                                               renderFn: renderFn)
        let view = VirtualListView(controller: controller, frame: absoluteFrame)
        host.addSubview(view)
        mount.virtualListController = controller
        mount.virtualListView = view
    }

    private func mountScroll(mount: MountedNode, node: RenderNode, flex: FlexNode) {
        guard let host = hostView else { return }
        let frame = flex.frame
        let sv = LumenScrollView(frame: frame)
        sv.onScrollHandler = node.onScroll
        sv.configureRefresh(onRefresh: node.onRefresh)
        host.addSubview(sv)
        sv.renderContent(children: node.children, wrapperStyle: node.style)
        mount.scrollView = sv
    }

    private func mountMap(mount: MountedNode, node: RenderNode, flex: FlexNode) {
        guard let host = hostView else { return }
        let mv = LumenMapView(frame: flex.frame)
        mv.onRegionChange = node.onMapRegionChange
        mv.onPinTap = node.onMapPinTap
        mv.layer.cornerRadius = CGFloat(node.style.borderRadius)
        mv.layer.masksToBounds = node.style.borderRadius > 0
        mv.apply(region: node.mapRegion,
                 pins: node.mapPins,
                 mapType: Self.mkMapType(node.mapType))
        host.addSubview(mv)
        mount.mapView = mv
    }

    private static func mkMapType(_ s: String) -> MKMapType {
        switch s {
        case "satellite": return .satellite
        case "hybrid":    return .hybrid
        default:          return .standard
        }
    }

    private func mountBlur(mount: MountedNode, node: RenderNode, flex: FlexNode) {
        guard let host = hostView else { return }
        let frame = flex.frame
        let bv = LumenBlurView(frame: frame, intensity: node.blurIntensity)
        host.addSubview(bv)
        bv.update(intensity: node.blurIntensity,
                  children: node.children,
                  wrapperStyle: node.style)
        // corner radius/border are applied to the wrapper itself — the outer layer
        // handles the clip, and inside effectView the content renders.
        bv.layer.cornerRadius = CGFloat(node.style.borderRadius)
        bv.layer.masksToBounds = node.style.borderRadius > 0
        if let borderColor = node.style.borderColor {
            bv.layer.borderColor = borderColor
            bv.layer.borderWidth = CGFloat(node.style.borderWidth)
        }
        mount.blurView = bv
    }

    private func mountTextInput(mount: MountedNode, node: RenderNode, flex: FlexNode) {
        guard let host = hostView else { return }
        let field = LumenTextField(frame: flex.frame)
        let controller = TextInputController()
        controller.attach(field)
        controller.apply(value: node.inputValue,
                         placeholder: node.inputPlaceholder,
                         style: node.style,
                         keyboardType: node.inputKeyboardType,
                         returnKey: node.inputReturnKey,
                         autocapitalize: node.inputAutocapitalize,
                         autocorrect: node.inputAutocorrect,
                         secure: node.inputSecure,
                         onChange: node.onInputChange,
                         onSubmit: node.onInputSubmit,
                         onFocus: node.onInputFocus,
                         onBlur: node.onInputBlur)
        host.addSubview(field)
        mount.textInputView = field
        mount.textInputController = controller
    }

    // MARK: - Reconcile

    /// On reconcile the node id may change (build-time counter in JS
    /// re-issues ids on each mount-rerun). We update nodeIndex so
    /// per-prop effects for the new id find the right CALayer.
    ///
    /// For the same-id case we do NOT overwrite `mounted.node` entirely —
    /// its `.style` may have been updated by per-prop patches and is the
    /// canonical state of the layer. We do sync `text` (patchText
    /// mutates lastTree.text and expects mount to pick it up) and `source`.
    private func updateMountedNode(_ mounted: MountedNode, with next: RenderNode) {
        let sameId = mounted.node.id != nil && mounted.node.id == next.id
        if sameId {
            // Sync only what could come from tree mutations (patchText,
            // structural updates). Leave style/handlers to mount —
            // it holds state synchronized with per-prop patches.
            if mounted.node.text != next.text {
                mounted.node.text = next.text
            }
            if mounted.node.source != next.source {
                mounted.node.source = next.source
            }
            return
        }

        if let oldId = mounted.node.id, oldId != next.id {
            Self.nodeIndex.removeValue(forKey: oldId)
            // Old id is no longer used anywhere (layer reused, but id
            // belonged to a JS node now replaced). JS scope must
            // be disposed — otherwise orphan effects keep patching the layer
            // under an id that's no longer theirs.
            disposalBuffer.append(oldId)
        }
        if let newId = next.id, mounted.node.id != newId {
            Self.nodeIndex[newId] = WeakMountedRef(mounted, self)
        }
        mounted.node = next
    }

    private func reconcile(parent: CALayer,
                           parentOrigin: CGPoint,
                           mounted: MountedNode,
                           next: RenderNode,
                           flex: FlexNode,
                           counter: inout Int) {
        if mounted.node.kind != next.kind {
            // Type changed — tear down and remount at the same position
            // in parent.sublayers. Indexing inside parent is preserved,
            // because in parent's `reconcile` we walk index-by-index.
            removeMountTree(mounted)
            let layer = makeLayer(for: next)
            parent.addSublayer(layer)
            mounted.layer = layer
            mounted.children = []
            mounted.loadedImageSource = nil
            mounted.virtualListView = nil
            mounted.virtualListController = nil
            mounted.textInputView = nil
            mounted.textInputController = nil
            mounted.scrollView = nil
            mounted.blurView = nil
            mounted.mapView?.removeFromSuperview()
            mounted.mapView = nil
            applyAll(layer: layer, mount: mounted, node: next, flex: flex, parentOrigin: parentOrigin)
            counter += 1

            if next.kind == .virtualList {
                mountVirtualList(mount: mounted, node: next, flex: flex)
            } else if next.kind == .textInput {
                mountTextInput(mount: mounted, node: next, flex: flex)
            } else if next.kind == .scroll {
                mountScroll(mount: mounted, node: next, flex: flex)
            } else if next.kind == .blur {
                mountBlur(mount: mounted, node: next, flex: flex)
            } else if next.kind == .map {
                mountMap(mount: mounted, node: next, flex: flex)
            } else {
                let myOrigin = CGPoint(x: flex.frame.minX, y: flex.frame.minY)
                for (cn, cf) in zip(next.children, flex.children) {
                    let cm = mountFresh(parent: layer,
                                        parentOrigin: myOrigin,
                                        node: cn,
                                        flex: cf,
                                        counter: &counter)
                    mounted.children.append(cm)
                }
            }
            updateMountedNode(mounted, with: next)
            return
        }

        // Same kind: reuse the layer.
        //
        // If the node id hasn't changed — JS didn't rebuild the subtree, and
        // `next.style` is exactly the same style that was built at mount
        // (or in the last JS-rerun of this node). Real dynamic changes of
        // visual props (color, backgroundColor, opacity, …) go through
        // per-prop effects → `lumen._patchProp` → applyPatch, which already
        // updated the layer and `mount.node.style`.
        //
        // If we re-apply `next.style` here, we'd overwrite the layer back
        // from the tree's stale value — that fights with patches and causes
        // flicker (classic example: TabBar where siblings constantly rebuild
        // but the tab-bar slot does not → the outer tree's Text node keeps
        // a stale style.color which then overwrites the just-applied patch).
        //
        // Therefore at same-id reconcile we do ONLY geometry + text/image
        // content sync + gestures. Visual style apply is skipped.
        let sameId = mounted.node.id != nil && mounted.node.id == next.id
        if sameId {
            applyGeometryOnly(mount: mounted,
                              node: next,
                              flex: flex,
                              parentOrigin: parentOrigin)
        } else {
            applyAll(layer: mounted.layer,
                     mount: mounted,
                     node: next,
                     flex: flex,
                     parentOrigin: parentOrigin)
        }
        counter += 1

        if next.kind == .virtualList {
            reconcileVirtualList(mount: mounted, node: next, flex: flex)
            updateMountedNode(mounted, with: next)
            return
        }

        if next.kind == .textInput {
            reconcileTextInput(mount: mounted, node: next, flex: flex)
            updateMountedNode(mounted, with: next)
            return
        }

        if next.kind == .scroll {
            reconcileScroll(mount: mounted, node: next, flex: flex)
            updateMountedNode(mounted, with: next)
            return
        }

        if next.kind == .blur {
            reconcileBlur(mount: mounted, node: next, flex: flex)
            updateMountedNode(mounted, with: next)
            return
        }

        if next.kind == .map {
            reconcileMap(mount: mounted, node: next, flex: flex)
            updateMountedNode(mounted, with: next)
            return
        }

        // Index-based reconcile of children (no key-LIS yet).
        let myOrigin = CGPoint(x: flex.frame.minX, y: flex.frame.minY)
        let prevCount = mounted.children.count
        let nextCount = next.children.count
        let common = min(prevCount, nextCount)

        for i in 0..<common {
            reconcile(parent: mounted.layer,
                      parentOrigin: myOrigin,
                      mounted: mounted.children[i],
                      next: next.children[i],
                      flex: flex.children[i],
                      counter: &counter)
        }
        if nextCount > prevCount {
            for i in common..<nextCount {
                let cm = mountFresh(parent: mounted.layer,
                                    parentOrigin: myOrigin,
                                    node: next.children[i],
                                    flex: flex.children[i],
                                    counter: &counter)
                mounted.children.append(cm)
            }
        } else if prevCount > nextCount {
            for i in (common..<prevCount).reversed() {
                removeMountTree(mounted.children[i])
                mounted.children.remove(at: i)
            }
        }

        updateMountedNode(mounted, with: next)
    }

    private func removeMountTree(_ mount: MountedNode) {
        gestureRouter?.removeHandlers(for: mount.layer)
        AnimationManager.shared.unbindLayer(mount.layer)
        if let nid = mount.node.id {
            Self.nodeIndex.removeValue(forKey: nid)
            disposalBuffer.append(nid)
        }
        mount.layer.removeFromSuperlayer()
        mount.virtualListView?.removeFromSuperview()
        mount.virtualListView = nil
        mount.virtualListController = nil
        mount.textInputView?.removeFromSuperview()
        mount.textInputView = nil
        mount.textInputController = nil
        mount.scrollView?.removeFromSuperview()
        mount.scrollView = nil
        mount.blurView?.removeFromSuperview()
        mount.blurView = nil
        mount.mapView?.removeFromSuperview()
        mount.mapView = nil
        for child in mount.children {
            removeMountTree(child)
        }
    }

    private func reconcileMap(mount: MountedNode, node: RenderNode, flex: FlexNode) {
        let frame = flex.frame
        if let mv = mount.mapView {
            if mv.frame != frame { mv.frame = frame }
            mv.onRegionChange = node.onMapRegionChange
            mv.onPinTap = node.onMapPinTap
            mv.layer.cornerRadius = CGFloat(node.style.borderRadius)
            mv.layer.masksToBounds = node.style.borderRadius > 0
            mv.apply(region: node.mapRegion,
                     pins: node.mapPins,
                     mapType: Self.mkMapType(node.mapType))
        } else {
            mountMap(mount: mount, node: node, flex: flex)
        }
    }

    private func reconcileBlur(mount: MountedNode, node: RenderNode, flex: FlexNode) {
        let frame = flex.frame
        if let bv = mount.blurView {
            if bv.frame != frame { bv.frame = frame }
            bv.update(intensity: node.blurIntensity,
                      children: node.children,
                      wrapperStyle: node.style)
            bv.layer.cornerRadius = CGFloat(node.style.borderRadius)
            bv.layer.masksToBounds = node.style.borderRadius > 0
            if let borderColor = node.style.borderColor {
                bv.layer.borderColor = borderColor
                bv.layer.borderWidth = CGFloat(node.style.borderWidth)
            } else {
                bv.layer.borderWidth = 0
            }
        } else {
            mountBlur(mount: mount, node: node, flex: flex)
        }
    }

    private func reconcileScroll(mount: MountedNode, node: RenderNode, flex: FlexNode) {
        let frame = flex.frame
        if let sv = mount.scrollView {
            if sv.frame != frame { sv.frame = frame }
            sv.onScrollHandler = node.onScroll
            sv.configureRefresh(onRefresh: node.onRefresh)
            sv.renderContent(children: node.children, wrapperStyle: node.style)
        } else {
            mountScroll(mount: mount, node: node, flex: flex)
        }
    }

    private func reconcileTextInput(mount: MountedNode, node: RenderNode, flex: FlexNode) {
        let frame = flex.frame
        if let field = mount.textInputView {
            if field.frame != frame { field.frame = frame }
            mount.textInputController?.apply(
                value: node.inputValue,
                placeholder: node.inputPlaceholder,
                style: node.style,
                keyboardType: node.inputKeyboardType,
                returnKey: node.inputReturnKey,
                autocapitalize: node.inputAutocapitalize,
                autocorrect: node.inputAutocorrect,
                secure: node.inputSecure,
                onChange: node.onInputChange,
                onSubmit: node.onInputSubmit,
                onFocus: node.onInputFocus,
                onBlur: node.onInputBlur
            )
        } else {
            mountTextInput(mount: mount, node: node, flex: flex)
        }
    }

    private func reconcileVirtualList(mount: MountedNode, node: RenderNode, flex: FlexNode) {
        let absoluteFrame = flex.frame
        if let view = mount.virtualListView {
            if view.frame != absoluteFrame {
                view.frame = absoluteFrame
            }
            if let renderFn = node.listRenderFn {
                mount.virtualListController?.update(count: node.listCount,
                                                    itemHeight: node.listItemHeight,
                                                    renderFn: renderFn)
            }
        } else {
            // virtualList appeared on reconcile (e.g. after a kind swap
            // or for the first time) — mount it.
            mountVirtualList(mount: mount, node: node, flex: flex)
        }
    }

    // MARK: - Apply props

    private func applyAll(layer: CALayer,
                          mount: MountedNode,
                          node: RenderNode,
                          flex: FlexNode,
                          parentOrigin: CGPoint) {
        // bounds + position, not frame: the frame setter compensates for
        // transform, so translateX/Y wouldn't produce visible motion.
        // The custom hit-test walker (see GestureRouter) reads transformed
        // layer.frame, so hit-area follows the transform automatically.
        let bounds = CGRect(x: 0, y: 0,
                            width: flex.frame.width,
                            height: flex.frame.height)
        let position = CGPoint(
            x: flex.frame.midX - parentOrigin.x,
            y: flex.frame.midY - parentOrigin.y
        )
        if layer.bounds != bounds { layer.bounds = bounds }
        if layer.position != position { layer.position = position }

        applyVisualStyle(layer, style: node.style)

        if node.kind == .text, let textLayer = layer as? CATextLayer, let text = node.text {
            applyTextStyle(textLayer, text: text, style: node.style)
        }
        if node.kind == .image, let src = node.source {
            applyContentMode(layer, contentMode: node.style.contentMode)
            if mount.loadedImageSource != src {
                applyImage(layer: layer, source: src)
                mount.loadedImageSource = src
            }
        }

        applyGestures(layer: layer, node: node)
    }

    /// Subset of applyAll: only geometry/gestures/image-source/text-content,
    /// WITHOUT applying visual styles. Used during reconcile of a same-id
    /// node — styles are already in place from mount or the last per-prop
    /// patch, and overwriting them from (potentially stale) lastTree is wrong.
    /// Text content still syncs: patchText mutates lastTree.text, and here
    /// we sync layer + mount.node.text.
    private func applyGeometryOnly(mount: MountedNode,
                                   node: RenderNode,
                                   flex: FlexNode,
                                   parentOrigin: CGPoint) {
        let layer = mount.layer
        let bounds = CGRect(x: 0, y: 0,
                            width: flex.frame.width,
                            height: flex.frame.height)
        let position = CGPoint(
            x: flex.frame.midX - parentOrigin.x,
            y: flex.frame.midY - parentOrigin.y
        )
        if layer.bounds != bounds { layer.bounds = bounds }
        if layer.position != position { layer.position = position }

        // Text content sync: patchText mutates the tree, but layer.string
        // still holds the old text. Re-render using mount.node.style — that
        // holds per-prop patched colors/fonts, not the stale tree style.
        if node.kind == .text,
           let textLayer = layer as? CATextLayer,
           mount.node.text != node.text,
           let newText = node.text {
            applyTextStyle(textLayer, text: newText, style: mount.node.style)
        }

        // Image source sync — same idea.
        if node.kind == .image, let src = node.source {
            if mount.loadedImageSource != src {
                applyImage(layer: layer, source: src)
                mount.loadedImageSource = src
            }
        }

        applyGestures(layer: layer, node: node)
    }

    private func applyGestures(layer: CALayer, node: RenderNode) {
        if let router = gestureRouter {
            var g = LayerGestures()
            g.onTap = node.onTap
            g.onDoubleTap = node.onDoubleTap
            g.onLongPress = node.onLongPress
            g.onPan = node.onPan
            g.onSwipe = node.onSwipe
            g.onPinch = node.onPinch
            g.onRotate = node.onRotate
            router.setHandlers(g, for: layer)
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
        if let borderColor = style.borderColor {
            layer.borderColor = borderColor
            layer.borderWidth = CGFloat(style.borderWidth)
        } else {
            layer.borderWidth = 0
        }
        layer.masksToBounds = style.borderRadius > 0

        // transform + opacity: either delegate to AnimationManager (if there
        // are AnimatedValue bindings), or apply directly as before.
        if style.hasAnimBindings {
            var animIds: [AnimationManager.Property: Int] = [:]
            if let id = style.transform.translateXAnimId { animIds[.translateX] = id }
            if let id = style.transform.translateYAnimId { animIds[.translateY] = id }
            if let id = style.transform.scaleAnimId { animIds[.scale] = id }
            if let id = style.transform.scaleXAnimId { animIds[.scaleX] = id }
            if let id = style.transform.scaleYAnimId { animIds[.scaleY] = id }
            if let id = style.transform.rotateAnimId { animIds[.rotate] = id }
            if let id = style.opacityAnimId { animIds[.opacity] = id }

            AnimationManager.shared.bindLayer(
                layer,
                animIds: animIds,
                staticTranslateX: style.transform.translateX,
                staticTranslateY: style.transform.translateY,
                staticScale: style.transform.scale,
                staticScaleX: style.transform.scaleX,
                staticScaleY: style.transform.scaleY,
                staticRotate: style.transform.rotate,
                staticOpacity: style.opacity
            )
        } else {
            // In case the layer used to be animated but no longer is —
            // unbind so AnimatedValue.set doesn't mutate someone else's layer.
            AnimationManager.shared.unbindLayer(layer)
            layer.opacity = Float(style.opacity)

            let t = style.transform
            if t.isIdentity {
                layer.transform = CATransform3DIdentity
            } else {
                var m = CATransform3DIdentity
                m = CATransform3DTranslate(m, CGFloat(t.translateX), CGFloat(t.translateY), 0)
                if t.rotate != 0 {
                    m = CATransform3DRotate(m, CGFloat(t.rotate), 0, 0, 1)
                }
                let sx = t.scaleX * t.scale
                let sy = t.scaleY * t.scale
                if sx != 1 || sy != 1 {
                    m = CATransform3DScale(m, CGFloat(sx), CGFloat(sy), 1)
                }
                layer.transform = m
            }
        }
    }

    private func applyContentMode(_ layer: CALayer, contentMode: String) {
        switch contentMode {
        case "cover":    layer.contentsGravity = .resizeAspectFill
        case "contain":  layer.contentsGravity = .resizeAspect
        case "stretch":  layer.contentsGravity = .resize
        case "center":   layer.contentsGravity = .center
        default:         layer.contentsGravity = .resizeAspectFill
        }
        layer.masksToBounds = true
    }

    private func applyImage(layer: CALayer, source: String) {
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

}
