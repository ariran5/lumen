import CoreGraphics
import Foundation

public enum FlexDirection: Sendable { case row, column }
public enum FlexJustify: Sendable { case start, center, end, spaceBetween, spaceAround, spaceEvenly }
public enum FlexAlign: Sendable { case start, center, end, stretch }
public enum FlexPosition: Sendable { case relative, absolute }

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

    // Absolute positioning: ребёнок с position=absolute исключается из flow
    // родителя, позиционируется через top/right/bottom/left относительно
    // содержимого parent'а (padding учитывается). Z-order — порядок объявления.
    public var position: FlexPosition = .relative
    public var top: Double? = nil
    public var right: Double? = nil
    public var bottom: Double? = nil
    public var left: Double? = nil

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

        // Absolute children excluded from flow distribution; они получают
        // отдельный pass с позиционированием через top/right/bottom/left.
        let flowChildren = node.children.enumerated().filter {
            $0.element.style.position == .relative
        }
        let absoluteChildren = node.children.enumerated().filter {
            $0.element.style.position == .absolute
        }

        var fixedMain: Double = 0
        var totalFlex: Double = 0
        var resolvedMains: [Double] = Array(repeating: 0, count: node.children.count)
        var resolvedCrosses: [Double] = Array(repeating: 0, count: node.children.count)

        for (i, child) in flowChildren {
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
                // Нет ни explicit, ни flex — берём intrinsic размер. Для text
                // leaf'а это measure callback; для контейнера — bounding box
                // детей + padding + gap (рекурсивно).
                let intrinsic = intrinsicSize(child,
                                              available: CGSize(width: mainAvailable,
                                                                height: crossAvailable),
                                              isParentRow: isRow)
                let mainFromIntrinsic = isRow ? intrinsic.width : intrinsic.height
                resolvedMains[i] = clamp(mainFromIntrinsic, min: mainMin, max: mainMax)
                fixedMain += resolvedMains[i]
            }

            if let c = resolvedCrossExplicit {
                resolvedCrosses[i] = c
            } else if node.style.alignItems == .stretch {
                resolvedCrosses[i] = crossAvailable
            } else if let measure = child.measure {
                let m = measure(CGSize(width: isRow ? resolvedMains[i] : crossAvailable,
                                        height: isRow ? crossAvailable : resolvedMains[i]))
                resolvedCrosses[i] = clamp(isRow ? m.height : m.width, min: crossMin, max: crossMax)
            } else if !child.children.isEmpty {
                // Контейнер без explicit cross — измерим intrinsic.
                let intrinsic = intrinsicSize(child,
                                              available: CGSize(width: mainAvailable,
                                                                height: crossAvailable),
                                              isParentRow: isRow)
                let crossFromIntrinsic = isRow ? intrinsic.height : intrinsic.width
                resolvedCrosses[i] = clamp(crossFromIntrinsic, min: crossMin, max: crossMax)
            } else {
                resolvedCrosses[i] = 0
            }
        }

        let gapsTotal = node.style.gap * Double(max(0, flowChildren.count - 1))
        let remaining = max(0, mainAvailable - fixedMain - gapsTotal)

        if totalFlex > 0 {
            for (i, child) in flowChildren where child.style.flex > 0 {
                let share = remaining * (child.style.flex / totalFlex)
                let mainMin = isRow ? child.style.minWidth : child.style.minHeight
                let mainMax = isRow ? child.style.maxWidth : child.style.maxHeight
                resolvedMains[i] = clamp(share, min: mainMin, max: mainMax)
            }
        }

        // Sum только по flow-детям (absolute не contributes к flow distribution).
        let occupiedMain = flowChildren.reduce(0.0) { $0 + resolvedMains[$1.offset] } + gapsTotal
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
            if flowChildren.count > 1 {
                spacing = node.style.gap + freeMain / Double(flowChildren.count - 1)
            }
        case .spaceAround:
            spacing = node.style.gap + freeMain / Double(max(1, flowChildren.count))
            cursor = spacing / 2 - node.style.gap / 2
        case .spaceEvenly:
            spacing = node.style.gap + freeMain / Double(flowChildren.count + 1)
            cursor = spacing - node.style.gap
        }

        let mainBase = isRow ? origin.x + pad.left : origin.y + pad.top
        let crossBase = isRow ? origin.y + pad.top : origin.x + pad.left

        for (i, child) in flowChildren {
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

        // Absolute children: позиционируются по top/right/bottom/left
        // относительно content-box parent'а (т.е. с учётом padding).
        for (_, child) in absoluteChildren {
            let cs = child.style

            // Width
            let childWidth: Double
            if case .points(let v) = cs.width {
                childWidth = clamp(v, min: cs.minWidth, max: cs.maxWidth)
            } else if case .percent(let p) = cs.width {
                childWidth = clamp(contentW * p / 100, min: cs.minWidth, max: cs.maxWidth)
            } else if let l = cs.left, let r = cs.right {
                childWidth = clamp(max(0, contentW - l - r),
                                    min: cs.minWidth, max: cs.maxWidth)
            } else {
                let i = intrinsicSize(child,
                                      available: CGSize(width: contentW, height: contentH),
                                      isParentRow: isRow)
                childWidth = clamp(i.width, min: cs.minWidth, max: cs.maxWidth)
            }

            // Height
            let childHeight: Double
            if case .points(let v) = cs.height {
                childHeight = clamp(v, min: cs.minHeight, max: cs.maxHeight)
            } else if case .percent(let p) = cs.height {
                childHeight = clamp(contentH * p / 100, min: cs.minHeight, max: cs.maxHeight)
            } else if let t = cs.top, let b = cs.bottom {
                childHeight = clamp(max(0, contentH - t - b),
                                     min: cs.minHeight, max: cs.maxHeight)
            } else {
                let i = intrinsicSize(child,
                                      available: CGSize(width: contentW, height: contentH),
                                      isParentRow: isRow)
                childHeight = clamp(i.height, min: cs.minHeight, max: cs.maxHeight)
            }

            // Position. left имеет приоритет над right; top — над bottom.
            let xOffset: Double
            if let l = cs.left { xOffset = pad.left + l }
            else if let r = cs.right { xOffset = pad.left + contentW - childWidth - r }
            else { xOffset = pad.left }

            let yOffset: Double
            if let t = cs.top { yOffset = pad.top + t }
            else if let b = cs.bottom { yOffset = pad.top + contentH - childHeight - b }
            else { yOffset = pad.top }

            FlexLayoutEngine.layout(
                node: child,
                available: CGSize(width: childWidth, height: childHeight),
                origin: CGPoint(x: origin.x + xOffset, y: origin.y + yOffset)
            )
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

    /// Intrinsic (shrink-to-fit) размер узла. Не учитывает `flex` (потому что
    /// flex — это растяжение в свободном пространстве родителя, а тут мы
    /// меряем минимально необходимое). Учитывает explicit width/height,
    /// measure callback (для текста и т.п.), и рекурсивно — детей.
    ///
    /// `isParentRow` нужен только для clamp по min/max — сам intrinsic
    /// считается в координатах самого узла, не зависит от ориентации parent.
    fileprivate static func intrinsicSize(_ node: FlexNode,
                                          available: CGSize,
                                          isParentRow: Bool) -> CGSize {
        let explicitW = resolveExplicit(node.style.width,
                                        parent: available.width,
                                        min: node.style.minWidth,
                                        max: node.style.maxWidth)
        let explicitH = resolveExplicit(node.style.height,
                                        parent: available.height,
                                        min: node.style.minHeight,
                                        max: node.style.maxHeight)

        // Leaf: measure callback или 0.
        if node.children.isEmpty {
            if let measure = node.measure {
                let m = measure(available)
                return CGSize(
                    width: explicitW ?? clamp(m.width, min: node.style.minWidth, max: node.style.maxWidth),
                    height: explicitH ?? clamp(m.height, min: node.style.minHeight, max: node.style.maxHeight)
                )
            }
            return CGSize(width: explicitW ?? 0, height: explicitH ?? 0)
        }

        // Контейнер: bounding box детей + padding + gaps.
        let pad = node.style.padding
        let isRow = node.style.direction == .row
        let gap = node.style.gap
        let innerAvailable = CGSize(
            width: Swift.max(0, available.width - pad.left - pad.right),
            height: Swift.max(0, available.height - pad.top - pad.bottom)
        )

        var mainSum: Double = 0
        var crossMax: Double = 0
        let flowChildren = node.children.filter { $0.style.position == .relative }
        for (i, child) in flowChildren.enumerated() {
            // flex>0 ребёнок не имеет intrinsic размера в main axis (только
            // от родителя), но имеет свой cross. Для intrinsic main считаем
            // 0 — это shrink-to-fit, не grow-to-fill. Absolute дети исключены
            // целиком — они out-of-flow.
            let cs = intrinsicSize(child, available: innerAvailable, isParentRow: isRow)
            let childMain = isRow ? cs.width : cs.height
            let childCross = isRow ? cs.height : cs.width
            mainSum += (child.style.flex > 0) ? 0 : childMain
            if i > 0 { mainSum += gap }
            crossMax = Swift.max(crossMax, childCross)
        }

        let intrinsicMain = mainSum + (isRow ? pad.left + pad.right : pad.top + pad.bottom)
        let intrinsicCross = crossMax + (isRow ? pad.top + pad.bottom : pad.left + pad.right)
        let width: Double = isRow ? intrinsicMain : intrinsicCross
        let height: Double = isRow ? intrinsicCross : intrinsicMain

        return CGSize(
            width: explicitW ?? clamp(width, min: node.style.minWidth, max: node.style.maxWidth),
            height: explicitH ?? clamp(height, min: node.style.minHeight, max: node.style.maxHeight)
        )
    }
}
