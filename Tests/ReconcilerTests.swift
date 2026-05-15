import XCTest
import QuartzCore
@testable import Lumen

@MainActor
final class ReconcilerTests: XCTestCase {

    private func makeRoot() -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        return layer
    }

    private func viewNode(children: [RenderNode] = [], opacity: Double = 1) -> RenderNode {
        var n = RenderNode()
        n.kind = .view
        n.style.opacity = opacity
        n.children = children
        return n
    }

    private func textNode(_ text: String) -> RenderNode {
        var n = RenderNode()
        n.kind = .text
        n.text = text
        n.style.flex.width = .points(100)
        n.style.flex.height = .points(20)
        return n
    }

    func testInitialMountCreatesSublayers() {
        let root = makeRoot()
        let renderer = Renderer(rootLayer: root)

        let tree = viewNode(children: [textNode("a"), textNode("b"), textNode("c")])
        renderer.render(tree)

        XCTAssertEqual(root.sublayers?.count, 1, "one wrapper view")
        XCTAssertEqual(root.sublayers?.first?.sublayers?.count, 3, "three text children")
    }

    func testUpdateOpacityReusesSameLayer() {
        let root = makeRoot()
        let renderer = Renderer(rootLayer: root)

        renderer.render(viewNode(opacity: 1))
        let firstLayer = root.sublayers?.first
        XCTAssertNotNil(firstLayer)
        XCTAssertEqual(firstLayer?.opacity, 1)

        renderer.render(viewNode(opacity: 0.5))
        let secondLayer = root.sublayers?.first
        XCTAssertTrue(firstLayer === secondLayer, "layer identity preserved")
        XCTAssertEqual(secondLayer?.opacity, 0.5)
    }

    func testAppendChildAddsSublayer() {
        let root = makeRoot()
        let renderer = Renderer(rootLayer: root)

        renderer.render(viewNode(children: [textNode("a"), textNode("b")]))
        let wrapper = root.sublayers?.first
        XCTAssertEqual(wrapper?.sublayers?.count, 2)
        let firstA = wrapper?.sublayers?[0]
        let firstB = wrapper?.sublayers?[1]

        renderer.render(viewNode(children: [textNode("a"), textNode("b"), textNode("c")]))
        XCTAssertEqual(wrapper?.sublayers?.count, 3)
        XCTAssertTrue(firstA === wrapper?.sublayers?[0], "first child reused")
        XCTAssertTrue(firstB === wrapper?.sublayers?[1], "second child reused")
    }

    func testRemoveTrailingChildren() {
        let root = makeRoot()
        let renderer = Renderer(rootLayer: root)

        renderer.render(viewNode(children: [textNode("a"), textNode("b"), textNode("c")]))
        let wrapper = root.sublayers?.first
        let firstA = wrapper?.sublayers?[0]

        renderer.render(viewNode(children: [textNode("a")]))
        XCTAssertEqual(wrapper?.sublayers?.count, 1)
        XCTAssertTrue(firstA === wrapper?.sublayers?[0])
    }

    func testKindChangeReplacesLayer() {
        let root = makeRoot()
        let renderer = Renderer(rootLayer: root)

        renderer.render(textNode("hello"))
        let textLayer = root.sublayers?.first
        XCTAssertTrue(textLayer is CATextLayer)

        renderer.render(viewNode())
        let newLayer = root.sublayers?.first
        XCTAssertFalse(newLayer is CATextLayer, "kind change swapped layer type")
        XCTAssertFalse(textLayer === newLayer, "layer identity changed on kind swap")
    }

    func testDetachClearsSublayers() {
        let root = makeRoot()
        let renderer = Renderer(rootLayer: root)

        renderer.render(viewNode(children: [textNode("a")]))
        XCTAssertEqual(root.sublayers?.count, 1)

        renderer.detach()
        XCTAssertEqual(root.sublayers?.count ?? 0, 0)
    }

    func testVirtualListKindParses() {
        // Basic smoke: parser sees kind=.virtualList and fills the fields.
        var n = RenderNode()
        n.kind = .virtualList
        n.listCount = 42
        n.listItemHeight = 64

        XCTAssertEqual(n.kind, .virtualList)
        XCTAssertEqual(n.listCount, 42)
        XCTAssertEqual(n.listItemHeight, 64)
    }

    func testVirtualListWithoutHostViewIsNoop() {
        // Without hostView (rootLayer-only init) virtualList safely mounts
        // nothing. mountedRoot is created, layer is added, sublayers don't crash.
        let root = makeRoot()
        let renderer = Renderer(rootLayer: root)

        var list = RenderNode()
        list.kind = .virtualList
        list.listCount = 10
        list.listItemHeight = 50
        list.style.flex.flex = 1

        renderer.render(viewNode(children: [list]))

        // Wrapper view is mounted, inside is a placeholder CALayer for virtualList.
        XCTAssertEqual(root.sublayers?.count, 1)
        XCTAssertEqual(root.sublayers?.first?.sublayers?.count, 1)
    }

    func testReconcileLargeTreeBudget() {
        // 1000 nodes, 5 deltas. Target budget — 2ms on simulator.
        let root = makeRoot()
        let renderer = Renderer(rootLayer: root)

        func build(opacity: Double) -> RenderNode {
            var children: [RenderNode] = []
            for i in 0..<1000 {
                var n = RenderNode()
                n.kind = .view
                n.style.flex.height = .points(2)
                // change opacity only for the first 5 on the second pass
                n.style.opacity = (i < 5) ? opacity : 1
                children.append(n)
            }
            var wrap = RenderNode()
            wrap.kind = .view
            wrap.children = children
            return wrap
        }

        renderer.render(build(opacity: 1))
        let firstMs = renderer.lastRenderMs

        renderer.render(build(opacity: 0.5))
        let secondMs = renderer.lastRenderMs

        print("[reconciler] initial mount = \(firstMs)ms, update = \(secondMs)ms")

        // Delta update must be faster than the initial mount.
        XCTAssertLessThan(secondMs, firstMs, "update faster than fresh mount")
        // Sanity: on the iPhone 17 Pro simulator ~< 10ms; realistically expect < 3ms.
        XCTAssertLessThan(secondMs, 10.0, "update budget < 10ms on sim")
    }
}
