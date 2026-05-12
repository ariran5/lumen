import CoreGraphics
import CoreText
import Foundation
import UIKit

enum TextMeasure {
    static func font(for style: ViewStyle) -> UIFont {
        let size = CGFloat(style.fontSize)
        let weight = uiFontWeight(style.fontWeight)
        if let family = style.fontFamily,
           let custom = UIFont(name: family, size: size) {
            return UIFont(descriptor: custom.fontDescriptor.addingAttributes([
                .traits: [UIFontDescriptor.TraitKey.weight: weight]
            ]), size: size)
        }
        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    static func attributedString(_ text: String, style: ViewStyle) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = alignment(style.textAlign)
        para.lineBreakMode = .byTruncatingTail

        if style.lineHeight > 0 {
            para.minimumLineHeight = CGFloat(style.lineHeight)
            para.maximumLineHeight = CGFloat(style.lineHeight)
        }

        var attrs: [NSAttributedString.Key: Any] = [
            .font: font(for: style),
            .paragraphStyle: para,
        ]
        if let color = style.color {
            attrs[.foregroundColor] = UIColor(cgColor: color)
        } else {
            attrs[.foregroundColor] = UIColor.label
        }

        return NSAttributedString(string: text, attributes: attrs)
    }

    static func measure(text: String, style: ViewStyle, maxWidth: CGFloat) -> CGSize {
        guard !text.isEmpty else { return .zero }
        let attr = attributedString(text, style: style)
        let constraint = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        let rect = attr.boundingRect(
            with: constraint,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        let unconstrainedHeight = ceil(rect.height)
        let width = min(maxWidth, ceil(rect.width))

        if style.numberOfLines > 0 {
            let lineH = style.lineHeight > 0
                ? CGFloat(style.lineHeight)
                : font(for: style).lineHeight
            let capped = lineH * CGFloat(style.numberOfLines)
            return CGSize(width: width, height: min(unconstrainedHeight, ceil(capped)))
        }

        return CGSize(width: width, height: unconstrainedHeight)
    }

    private static func uiFontWeight(_ s: String) -> UIFont.Weight {
        switch s {
        case "100", "ultralight", "thin":   return .ultraLight
        case "200":                          return .thin
        case "300", "light":                 return .light
        case "400", "regular", "normal":     return .regular
        case "500", "medium":                return .medium
        case "600", "semibold":              return .semibold
        case "700", "bold":                  return .bold
        case "800", "heavy":                 return .heavy
        case "900", "black":                 return .black
        default:                             return .regular
        }
    }

    private static func alignment(_ s: String) -> NSTextAlignment {
        switch s {
        case "center":  return .center
        case "right":   return .right
        case "justify": return .justified
        default:        return .left
        }
    }
}
