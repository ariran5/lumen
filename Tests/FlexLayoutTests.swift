import XCTest
@testable import Lumen

final class FlexLayoutTests: XCTestCase {

    func testRowOfThreeFixedSquares() {
        var root = FlexStyle()
        root.direction = .row
        let r = FlexNode(style: root)

        for _ in 0..<3 {
            var s = FlexStyle()
            s.width = .points(40)
            s.height = .points(40)
            r.add(FlexNode(style: s))
        }

        r.calculateLayout(width: 300, height: 100)

        XCTAssertEqual(r.children[0].frame, CGRect(x: 0,  y: 0, width: 40, height: 40))
        XCTAssertEqual(r.children[1].frame, CGRect(x: 40, y: 0, width: 40, height: 40))
        XCTAssertEqual(r.children[2].frame, CGRect(x: 80, y: 0, width: 40, height: 40))
    }

    func testColumnWithFlex() {
        var root = FlexStyle()
        root.direction = .column
        let r = FlexNode(style: root)

        var top = FlexStyle();    top.height = .points(50)
        var mid = FlexStyle();    mid.flex = 1
        var bot = FlexStyle();    bot.height = .points(30)

        r.add(FlexNode(style: top))
        r.add(FlexNode(style: mid))
        r.add(FlexNode(style: bot))

        r.calculateLayout(width: 200, height: 200)

        XCTAssertEqual(r.children[0].frame, CGRect(x: 0, y: 0,   width: 200, height: 50))
        XCTAssertEqual(r.children[1].frame, CGRect(x: 0, y: 50,  width: 200, height: 120))
        XCTAssertEqual(r.children[2].frame, CGRect(x: 0, y: 170, width: 200, height: 30))
    }

    func testPaddingShrinksContent() {
        var root = FlexStyle()
        root.direction = .row
        root.padding = FlexInsets(uniform: 10)
        let r = FlexNode(style: root)

        var child = FlexStyle()
        child.flex = 1
        r.add(FlexNode(style: child))

        r.calculateLayout(width: 100, height: 100)

        XCTAssertEqual(r.children[0].frame,
                       CGRect(x: 10, y: 10, width: 80, height: 80))
    }

    func testJustifyCenter() {
        var root = FlexStyle()
        root.direction = .row
        root.justify = .center
        let r = FlexNode(style: root)

        var c = FlexStyle()
        c.width = .points(40); c.height = .points(40)
        r.add(FlexNode(style: c))
        r.add(FlexNode(style: c))

        r.calculateLayout(width: 200, height: 100)

        XCTAssertEqual(r.children[0].frame.minX, 60, accuracy: 0.01)
        XCTAssertEqual(r.children[1].frame.minX, 100, accuracy: 0.01)
    }

    func testSpaceBetweenWithGap() {
        var root = FlexStyle()
        root.direction = .row
        root.justify = .spaceBetween
        let r = FlexNode(style: root)

        var c = FlexStyle()
        c.width = .points(20); c.height = .points(20)
        r.add(FlexNode(style: c))
        r.add(FlexNode(style: c))
        r.add(FlexNode(style: c))

        r.calculateLayout(width: 200, height: 50)

        XCTAssertEqual(r.children[0].frame.minX, 0,   accuracy: 0.01)
        XCTAssertEqual(r.children[1].frame.minX, 90,  accuracy: 0.01)
        XCTAssertEqual(r.children[2].frame.minX, 180, accuracy: 0.01)
    }

    func testAlignCenterCrossAxis() {
        var root = FlexStyle()
        root.direction = .row
        root.alignItems = .center
        let r = FlexNode(style: root)

        var c = FlexStyle()
        c.width = .points(40); c.height = .points(40)
        r.add(FlexNode(style: c))

        r.calculateLayout(width: 200, height: 200)

        XCTAssertEqual(r.children[0].frame.minY, 80, accuracy: 0.01)
        XCTAssertEqual(r.children[0].frame.maxY, 120, accuracy: 0.01)
    }

    func testNestedRowInColumn() {
        var rootStyle = FlexStyle()
        rootStyle.direction = .column
        let root = FlexNode(style: rootStyle)

        var headerStyle = FlexStyle()
        headerStyle.height = .points(60)
        let header = FlexNode(style: headerStyle)

        var bodyStyle = FlexStyle()
        bodyStyle.flex = 1
        bodyStyle.direction = .row
        let body = FlexNode(style: bodyStyle)

        var sideStyle = FlexStyle()
        sideStyle.width = .points(80)
        let side = FlexNode(style: sideStyle)

        var contentStyle = FlexStyle()
        contentStyle.flex = 1
        let content = FlexNode(style: contentStyle)

        body.add(side)
        body.add(content)
        root.add(header)
        root.add(body)

        root.calculateLayout(width: 400, height: 300)

        XCTAssertEqual(header.frame,  CGRect(x: 0,  y: 0,   width: 400, height: 60))
        XCTAssertEqual(body.frame,    CGRect(x: 0,  y: 60,  width: 400, height: 240))
        XCTAssertEqual(side.frame,    CGRect(x: 0,  y: 60,  width: 80,  height: 240))
        XCTAssertEqual(content.frame, CGRect(x: 80, y: 60,  width: 320, height: 240))
    }

    // MARK: - Intrinsic sizing (shrink-to-fit, P2.3)

    func testIntrinsicRowFromChildren() {
        // A container without explicit width should take its size from children + padding + gap.
        // Parent uses alignItems=.start, otherwise the CSS-default stretch grows the cross axis.
        var rs = FlexStyle()
        rs.direction = .row
        rs.padding = FlexInsets(uniform: 8)
        rs.gap = 6
        let r = FlexNode(style: rs)

        var a = FlexStyle(); a.width = .points(30); a.height = .points(40)
        var b = FlexStyle(); b.width = .points(50); b.height = .points(20)
        r.add(FlexNode(style: a))
        r.add(FlexNode(style: b))

        var parentStyle = FlexStyle()
        parentStyle.direction = .row
        parentStyle.alignItems = .start
        let parent = FlexNode(style: parentStyle)
        parent.add(r)
        parent.calculateLayout(width: 500, height: 200)

        // r main = 30 + 6 + 50 + pad.left + pad.right = 30 + 6 + 50 + 16 = 102
        // r cross = max(40, 20) + pad.top + pad.bottom = 40 + 16 = 56
        XCTAssertEqual(r.frame.width, 102, accuracy: 0.5)
        XCTAssertEqual(r.frame.height, 56, accuracy: 0.5)
    }

    func testIntrinsicColumnFromChildren() {
        var ps = FlexStyle()
        ps.direction = .row
        ps.alignItems = .start
        let parent = FlexNode(style: ps)

        var cs = FlexStyle()
        cs.direction = .column
        cs.gap = 4
        let col = FlexNode(style: cs)

        var a = FlexStyle(); a.width = .points(80); a.height = .points(15)
        var b = FlexStyle(); b.width = .points(60); b.height = .points(25)
        col.add(FlexNode(style: a))
        col.add(FlexNode(style: b))
        parent.add(col)

        parent.calculateLayout(width: 400, height: 200)

        // col width = max(80, 60) = 80
        // col height = 15 + 4 + 25 = 44
        XCTAssertEqual(col.frame.width, 80, accuracy: 0.5)
        XCTAssertEqual(col.frame.height, 44, accuracy: 0.5)
    }

    func testIntrinsicWithTextMeasure() {
        // Container with a single text leaf — must get its size from measure.
        var ps = FlexStyle()
        ps.direction = .row
        ps.alignItems = .start
        let parent = FlexNode(style: ps)

        var ws = FlexStyle()
        ws.padding = FlexInsets(uniform: 4)
        let wrapper = FlexNode(style: ws)

        let text = FlexNode(style: FlexStyle())
        text.measure = { _ in CGSize(width: 90, height: 18) }
        wrapper.add(text)
        parent.add(wrapper)

        parent.calculateLayout(width: 500, height: 200)

        // wrapper.height = 18 + 4 + 4 = 26 (column default direction)
        // wrapper.width = 90 + 4 + 4 = 98
        XCTAssertEqual(wrapper.frame.width, 98, accuracy: 0.5)
        XCTAssertEqual(wrapper.frame.height, 26, accuracy: 0.5)
    }
}
