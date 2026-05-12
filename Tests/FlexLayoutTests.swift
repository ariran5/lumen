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
}
