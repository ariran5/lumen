import CoreGraphics
import Foundation

public enum FlexDirection: Sendable { case row, column }
public enum FlexJustify: Sendable { case start, center, end, spaceBetween, spaceAround, spaceEvenly }
public enum FlexAlign: Sendable { case start, center, end, stretch }

public enum FlexDimension: Sendable, Equatable {
    case auto
    case points(Double)
    case percent(Double)
}

public struct FlexInsets: Sendable, Equatable {
    public var top: Double
    public var right: Double
    public var bottom: Double
    public var left: Double

    public static let zero = FlexInsets(top: 0, right: 0, bottom: 0, left: 0)

    public init(top: Double = 0, right: Double = 0, bottom: Double = 0, left: Double = 0) {
        self.top = top; self.right = right; self.bottom = bottom; self.left = left
    }

    public init(uniform v: Double) { self.init(top: v, right: v, bottom: v, left: v) }
    public init(vertical v: Double, horizontal h: Double) {
        self.init(top: v, right: h, bottom: v, left: h)
    }
}

public struct FlexStyle: Sendable {
    public var direction: FlexDirection = .column
    public var justify: FlexJustify = .start
    public var alignItems: FlexAlign = .stretch
    public var width: FlexDimension = .auto
    public var height: FlexDimension = .auto
    public var minWidth: Double = 0
    public var maxWidth: Double = .infinity
    public var minHeight: Double = 0
    public var maxHeight: Double = .infinity
    public var flex: Double = 0
    public var padding: FlexInsets = .zero
    public var gap: Double = 0

    public init() {}
}

public final class FlexNode {
    public var style: FlexStyle
    public private(set) var children: [FlexNode] = []
    public private(set) weak var parent: FlexNode?

    public internal(set) var frame: CGRect = .zero
    public var measure: ((CGSize) -> CGSize)?

    public init(style: FlexStyle = FlexStyle()) {
        self.style = style
    }

    @discardableResult
    public func add(_ child: FlexNode) -> FlexNode {
        children.append(child)
        child.parent = self
        return self
    }

    public func removeAllChildren() {
        for c in children { c.parent = nil }
        children.removeAll()
    }

    public func calculateLayout(width: Double, height: Double) {
        FlexLayoutEngine.layout(node: self, available: CGSize(width: width, height: height), origin: .zero)
    }
}

enum FlexLayoutEngine {
    static func layout(node: FlexNode, available: CGSize, origin: CGPoint) {
        let resolvedWidth = resolveAxis(node.style.width,
                                        parent: available.width,
                                        min: node.style.minWidth,
                                        max: node.style.maxWidth,
                                        fallback: available.width)
        let resolvedHeight = resolveAxis(node.style.height,
                                         parent: available.height,
                                         min: node.style.minHeight,
                                         max: node.style.maxHeight,
                                         fallback: available.height)

        var width = resolvedWidth
        var height = resolvedHeight

        if node.children.isEmpty {
            if let measure = node.measure {
                let intrinsic = measure(CGSize(width: width, height: height))
                if node.style.width == .auto { width = clamp(intrinsic.width, min: node.style.minWidth, max: node.style.maxWidth) }
                if node.style.height == .auto { height = clamp(intrinsic.height, min: node.style.minHeight, max: node.style.maxHeight) }
            }
            node.frame = CGRect(origin: origin, size: CGSize(width: width, height: height))
            return
        }

        let pad = node.style.padding
        let contentW = max(0, width - pad.left - pad.right)
        let contentH = max(0, height - pad.top - pad.bottom)

        let isRow = node.style.direction == .row
        let mainAvailable = isRow ? contentW : contentH
        let crossAvailable = isRow ? contentH : contentW

        var fixedMain: Double = 0
        var totalFlex: Double = 0
        var resolvedMains: [Double] = Array(repeating: 0, count: node.children.count)
        var resolvedCrosses: [Double] = Array(repeating: 0, count: node.children.count)

        for (i, child) in node.children.enumerated() {
            let cs = child.style
            let mainDim = isRow ? cs.width : cs.height
            let crossDim = isRow ? cs.height : cs.width
            let mainMin = isRow ? cs.minWidth : cs.minHeight
            let mainMax = isRow ? cs.maxWidth : cs.maxHeight
            let crossMin = isRow ? cs.minHeight : cs.minWidth
            let crossMax = isRow ? cs.maxHeight : cs.maxWidth

            let resolvedMainExplicit = resolveExplicit(mainDim, parent: mainAvailable, min: mainMin, max: mainMax)
            let resolvedCrossExplicit = resolveExplicit(crossDim, parent: crossAvailable, min: crossMin, max: crossMax)

            if let m = resolvedMainExplicit {
                resolvedMains[i] = m
                fixedMain += m
            } else if cs.flex > 0 {
                totalFlex += cs.flex
            } else {
                if let measure = child.measure {
                    let probeMain = isRow ? mainAvailable : crossAvailable
                    let probeCross = isRow ? crossAvailable : mainAvailable
                    let m = measure(CGSize(width: isRow ? probeMain : probeCross,
                                            height: isRow ? probeCross : probeMain))
                    let mainFromMeasure = isRow ? m.width : m.height
                    resolvedMains[i] = clamp(mainFromMeasure, min: mainMin, max: mainMax)
                    fixedMain += resolvedMains[i]
                } else {
                    resolvedMains[i] = 0
                }
            }

            if let c = resolvedCrossExplicit {
                resolvedCrosses[i] = c
            } else if cs.alignItems == .stretch || node.style.alignItems == .stretch {
                resolvedCrosses[i] = crossAvailable
            } else if let measure = child.measure {
                let m = measure(CGSize(width: isRow ? resolvedMains[i] : crossAvailable,
                                        height: isRow ? crossAvailable : resolvedMains[i]))
                resolvedCrosses[i] = clamp(isRow ? m.height : m.width, min: crossMin, max: crossMax)
            } else {
                resolvedCrosses[i] = 0
            }
        }

        let gapsTotal = node.style.gap * Double(max(0, node.children.count - 1))
        let remaining = max(0, mainAvailable - fixedMain - gapsTotal)

        if totalFlex > 0 {
            for (i, child) in node.children.enumerated() where child.style.flex > 0 {
                let share = remaining * (child.style.flex / totalFlex)
                let mainMin = isRow ? child.style.minWidth : child.style.minHeight
                let mainMax = isRow ? child.style.maxWidth : child.style.maxHeight
                resolvedMains[i] = clamp(share, min: mainMin, max: mainMax)
            }
        }

        let occupiedMain = resolvedMains.reduce(0, +) + gapsTotal
        let freeMain = max(0, mainAvailable - occupiedMain)

        var cursor: Double
        var spacing: Double = node.style.gap

        switch node.style.justify {
        case .start:
            cursor = 0
        case .center:
            cursor = freeMain / 2
        case .end:
            cursor = freeMain
        case .spaceBetween:
            cursor = 0
            if node.children.count > 1 {
                spacing = node.style.gap + freeMain / Double(node.children.count - 1)
            }
        case .spaceAround:
            spacing = node.style.gap + freeMain / Double(max(1, node.children.count))
            cursor = spacing / 2 - node.style.gap / 2
        case .spaceEvenly:
            spacing = node.style.gap + freeMain / Double(node.children.count + 1)
            cursor = spacing - node.style.gap
        }

        let mainBase = isRow ? origin.x + pad.left : origin.y + pad.top
        let crossBase = isRow ? origin.y + pad.top : origin.x + pad.left

        for (i, child) in node.children.enumerated() {
            let childMain = resolvedMains[i]
            let childCross = resolvedCrosses[i]

            let crossOffset: Double
            let align = node.style.alignItems
            switch align {
            case .start, .stretch:
                crossOffset = 0
            case .center:
                crossOffset = (crossAvailable - childCross) / 2
            case .end:
                crossOffset = crossAvailable - childCross
            }

            let childOriginMain = mainBase + cursor
            let childOriginCross = crossBase + crossOffset

            let childOrigin = isRow
                ? CGPoint(x: childOriginMain, y: childOriginCross)
                : CGPoint(x: childOriginCross, y: childOriginMain)

            let childAvailable = isRow
                ? CGSize(width: childMain, height: childCross)
                : CGSize(width: childCross, height: childMain)

            FlexLayoutEngine.layout(node: child, available: childAvailable, origin: childOrigin)

            cursor += childMain + spacing
        }

        node.frame = CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    private static func resolveAxis(_ dim: FlexDimension,
                                    parent: Double,
                                    min: Double,
                                    max: Double,
                                    fallback: Double) -> Double {
        let raw: Double
        switch dim {
        case .auto: raw = fallback
        case .points(let v): raw = v
        case .percent(let p): raw = parent * (p / 100)
        }
        return clamp(raw, min: min, max: max)
    }

    private static func resolveExplicit(_ dim: FlexDimension,
                                        parent: Double,
                                        min: Double,
                                        max: Double) -> Double? {
        switch dim {
        case .auto: return nil
        case .points(let v): return clamp(v, min: min, max: max)
        case .percent(let p): return clamp(parent * (p / 100), min: min, max: max)
        }
    }

    private static func clamp(_ v: Double, min: Double, max: Double) -> Double {
        Swift.min(Swift.max(v, min), max)
    }
}
