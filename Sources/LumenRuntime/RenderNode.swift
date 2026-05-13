import CoreGraphics
import Foundation
import JavaScriptCore

struct RenderNode {
    enum Kind: String {
        case view, text, image, scroll, pressable, virtualList, textInput, blur
    }

    var kind: Kind = .view
    var key: String?
    var style: ViewStyle = ViewStyle()
    var text: String?
    var source: String?
    var children: [RenderNode] = []

    // Gestures
    var onTap: JSValue?
    var onDoubleTap: JSValue?
    var onLongPress: JSValue?
    var onPan: JSValue?
    var onSwipe: JSValue?
    var onPinch: JSValue?
    var onRotate: JSValue?

    // virtualList-specific
    var listCount: Int = 0
    var listItemHeight: CGFloat = 50
    var listRenderFn: JSValue?

    // textInput-specific
    var inputValue: String = ""
    var inputPlaceholder: String?
    var inputKeyboardType: String?
    var inputReturnKey: String?
    var inputAutocapitalize: String?
    var inputAutocorrect: Bool?
    var inputSecure: Bool?
    var onInputChange: JSValue?
    var onInputSubmit: JSValue?
    var onInputFocus: JSValue?
    var onInputBlur: JSValue?

    // blur-specific
    var blurIntensity: String = "regular"

    // scroll-specific
    var onScroll: JSValue?
}

private let gestureProps = [
    "onTap", "onDoubleTap", "onLongPress",
    "onPan", "onSwipe", "onPinch", "onRotate",
]

extension RenderNode {
    static func parse(_ value: JSValue) -> RenderNode? {
        guard value.isObject, !value.isNull, !value.isUndefined else { return nil }
        return parseValue(value)
    }

    private static func parseValue(_ value: JSValue) -> RenderNode {
        var node = RenderNode()

        if let type = string(value, "type"), let k = Kind(rawValue: type) {
            node.kind = k
        }
        if let key = string(value, "key") {
            node.key = key
        }
        if let styleVal = subscript_(value, "style"), styleVal.isObject {
            if let styleDict = styleVal.toDictionary() as? [String: Any] {
                node.style = parseStyle(styleDict)
            }
        }
        if let text = string(value, "text") {
            node.text = text
        }
        if let src = string(value, "source") {
            node.source = src
        }
        for name in gestureProps {
            if let v = subscript_(value, name), v.isObject {
                switch name {
                case "onTap": node.onTap = v
                case "onDoubleTap": node.onDoubleTap = v
                case "onLongPress": node.onLongPress = v
                case "onPan": node.onPan = v
                case "onSwipe": node.onSwipe = v
                case "onPinch": node.onPinch = v
                case "onRotate": node.onRotate = v
                default: break
                }
            }
        }

        if node.kind == .virtualList {
            if let countVal = subscript_(value, "count") {
                node.listCount = Int(countVal.toInt32())
            }
            if let heightVal = subscript_(value, "itemHeight") {
                node.listItemHeight = CGFloat(heightVal.toDouble())
            }
            if let renderVal = subscript_(value, "render"), renderVal.isObject {
                node.listRenderFn = renderVal
            }
        }

        if node.kind == .blur {
            if let i = string(value, "intensity") { node.blurIntensity = i }
        }

        if node.kind == .scroll {
            if let v = subscript_(value, "onScroll"), v.isObject {
                node.onScroll = v
            }
        }

        if node.kind == .textInput {
            node.inputValue = string(value, "value") ?? ""
            node.inputPlaceholder = string(value, "placeholder")
            node.inputKeyboardType = string(value, "keyboardType")
            node.inputReturnKey = string(value, "returnKey")
            node.inputAutocapitalize = string(value, "autocapitalize")
            if let v = subscript_(value, "autocorrect"), v.isBoolean {
                node.inputAutocorrect = v.toBool()
            }
            if let v = subscript_(value, "secure"), v.isBoolean {
                node.inputSecure = v.toBool()
            }
            if let v = subscript_(value, "onChange"), v.isObject {
                node.onInputChange = v
            }
            if let v = subscript_(value, "onSubmit"), v.isObject {
                node.onInputSubmit = v
            }
            if let v = subscript_(value, "onFocus"), v.isObject {
                node.onInputFocus = v
            }
            if let v = subscript_(value, "onBlur"), v.isObject {
                node.onInputBlur = v
            }
        }

        if let childrenVal = subscript_(value, "children"),
           childrenVal.isArray {
            let length = Int(childrenVal.objectForKeyedSubscript("length")?.toInt32() ?? 0)
            node.children.reserveCapacity(length)
            for i in 0..<length {
                if let childVal = childrenVal.atIndex(i), childVal.isObject {
                    node.children.append(parseValue(childVal))
                }
            }
        }

        return node
    }

    private static func subscript_(_ value: JSValue, _ key: String) -> JSValue? {
        guard let v = value.objectForKeyedSubscript(key),
              !v.isUndefined, !v.isNull else { return nil }
        return v
    }

    private static func string(_ value: JSValue, _ key: String) -> String? {
        guard let v = subscript_(value, key), v.isString else { return nil }
        return v.toString()
    }

    static func parseStyle(_ dict: [String: Any]) -> ViewStyle {
        var style = ViewStyle()

        if let s = dict["flexDirection"] as? String {
            style.flex.direction = (s == "row") ? .row : .column
        }
        if let v = dict["width"] { style.flex.width = parseDimension(v) }
        if let v = dict["height"] { style.flex.height = parseDimension(v) }
        if let v = doubleValue(dict["flex"]) { style.flex.flex = v }
        if let v = doubleValue(dict["padding"]) { style.flex.padding = FlexInsets(uniform: v) }
        if let v = doubleValue(dict["paddingTop"]) { style.flex.padding.top = v }
        if let v = doubleValue(dict["paddingRight"]) { style.flex.padding.right = v }
        if let v = doubleValue(dict["paddingBottom"]) { style.flex.padding.bottom = v }
        if let v = doubleValue(dict["paddingLeft"]) { style.flex.padding.left = v }
        if let v = doubleValue(dict["gap"]) { style.flex.gap = v }
        if let v = doubleValue(dict["minWidth"]) { style.flex.minWidth = v }
        if let v = doubleValue(dict["minHeight"]) { style.flex.minHeight = v }
        if let v = doubleValue(dict["maxWidth"]) { style.flex.maxWidth = v }
        if let v = doubleValue(dict["maxHeight"]) { style.flex.maxHeight = v }
        if let v = dict["justifyContent"] as? String { style.flex.justify = parseJustify(v) }
        if let v = dict["alignItems"] as? String { style.flex.alignItems = parseAlign(v) }

        if let v = dict["position"] as? String {
            style.flex.position = (v == "absolute") ? .absolute : .relative
        }
        if let v = doubleValue(dict["top"]) { style.flex.top = v }
        if let v = doubleValue(dict["right"]) { style.flex.right = v }
        if let v = doubleValue(dict["bottom"]) { style.flex.bottom = v }
        if let v = doubleValue(dict["left"]) { style.flex.left = v }

        if let v = dict["backgroundColor"] as? String { style.backgroundColor = parseColor(v) }
        if let v = dict["borderColor"] as? String { style.borderColor = parseColor(v) }
        if let v = doubleValue(dict["borderRadius"]) { style.borderRadius = v }
        if let v = doubleValue(dict["borderWidth"]) { style.borderWidth = v }
        if let any = dict["opacity"] {
            let parsed = parseAnimOrDouble(any)
            style.opacity = parsed.value ?? style.opacity
            style.opacityAnimId = parsed.animId
        }

        if let v = doubleValue(dict["fontSize"]) { style.fontSize = v }
        if let v = dict["fontWeight"] { style.fontWeight = String(describing: v) }
        if let v = dict["fontFamily"] as? String { style.fontFamily = v }
        if let v = dict["color"] as? String { style.color = parseColor(v) }
        if let v = dict["textAlign"] as? String { style.textAlign = v }
        if let v = doubleValue(dict["numberOfLines"]) { style.numberOfLines = Int(v) }
        if let v = doubleValue(dict["lineHeight"]) { style.lineHeight = v }

        if let v = dict["contentMode"] as? String { style.contentMode = v }

        if let t = dict["transform"] as? [String: Any] {
            let tx = parseAnimOrDouble(t["translateX"])
            style.transform.translateX = tx.value ?? style.transform.translateX
            style.transform.translateXAnimId = tx.animId
            let ty = parseAnimOrDouble(t["translateY"])
            style.transform.translateY = ty.value ?? style.transform.translateY
            style.transform.translateYAnimId = ty.animId
            let s = parseAnimOrDouble(t["scale"])
            style.transform.scale = s.value ?? style.transform.scale
            style.transform.scaleAnimId = s.animId
            let sx = parseAnimOrDouble(t["scaleX"])
            style.transform.scaleX = sx.value ?? style.transform.scaleX
            style.transform.scaleXAnimId = sx.animId
            let sy = parseAnimOrDouble(t["scaleY"])
            style.transform.scaleY = sy.value ?? style.transform.scaleY
            style.transform.scaleYAnimId = sy.animId
            let r = parseAnimOrDouble(t["rotate"])
            style.transform.rotate = r.value ?? style.transform.rotate
            style.transform.rotateAnimId = r.animId
        }

        return style
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    /// JS-side AnimatedValue сериализуется как `{__anim: id, ...}`.
    /// Этот хелпер унифицирует: число → (value, nil); animated → (nil, animId).
    private static func parseAnimOrDouble(_ any: Any?) -> (value: Double?, animId: Int?) {
        if let d = doubleValue(any) { return (d, nil) }
        if let dict = any as? [String: Any] {
            if let aid = dict["__anim"] as? Int { return (nil, aid) }
            if let n = dict["__anim"] as? NSNumber { return (nil, n.intValue) }
        }
        return (nil, nil)
    }

    private static func parseDimension(_ v: Any) -> FlexDimension {
        if let s = v as? String {
            if s.hasSuffix("%"), let p = Double(s.dropLast()) {
                return .percent(p)
            }
            if s == "auto" { return .auto }
        }
        if let d = doubleValue(v) { return .points(d) }
        return .auto
    }

    private static func parseJustify(_ s: String) -> FlexJustify {
        switch s {
        case "flex-start", "start": return .start
        case "flex-end", "end": return .end
        case "center": return .center
        case "space-between": return .spaceBetween
        case "space-around": return .spaceAround
        case "space-evenly": return .spaceEvenly
        default: return .start
        }
    }

    private static func parseAlign(_ s: String) -> FlexAlign {
        switch s {
        case "flex-start", "start": return .start
        case "flex-end", "end": return .end
        case "center": return .center
        case "stretch": return .stretch
        default: return .stretch
        }
    }

    static func parseColor(_ raw: String) -> CGColor? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()

        if s.hasPrefix("#") {
            let hex = String(s.dropFirst())
            return colorFromHex(hex)
        }

        switch s {
        case "transparent": return CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
        case "red":         return CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        case "green":       return CGColor(srgbRed: 0, green: 0.7, blue: 0, alpha: 1)
        case "blue":        return CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        case "white":       return CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        case "black":       return CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        case "gray", "grey":return CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        default: return nil
        }
    }

    private static func colorFromHex(_ hex: String) -> CGColor? {
        let normalized: String
        switch hex.count {
        case 3:
            normalized = hex.map { "\($0)\($0)" }.joined()
        case 4:
            normalized = hex.map { "\($0)\($0)" }.joined()
        case 6, 8:
            normalized = hex
        default:
            return nil
        }

        guard let value = UInt32(normalized, radix: 16) else { return nil }

        if normalized.count == 6 {
            return CGColor(srgbRed: Double((value >> 16) & 0xFF) / 255,
                           green: Double((value >> 8) & 0xFF) / 255,
                           blue: Double(value & 0xFF) / 255,
                           alpha: 1)
        } else {
            return CGColor(srgbRed: Double((value >> 24) & 0xFF) / 255,
                           green: Double((value >> 16) & 0xFF) / 255,
                           blue: Double((value >> 8) & 0xFF) / 255,
                           alpha: Double(value & 0xFF) / 255)
        }
    }
}
