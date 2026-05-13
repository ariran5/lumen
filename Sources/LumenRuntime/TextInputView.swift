import JavaScriptCore
import UIKit

/// Native UITextField как overlay поверх Lumen-дерева. Используется через
/// `kind: 'textInput'` в RenderNode — renderer монтирует LumenTextField как
/// subview hostView с absolute frame из flex layout (паттерн из VirtualList).
///
/// Стиль (backgroundColor, font, color, borderRadius, padding) пробрасывается
/// напрямую в UITextField и его layer. Padding реализован через override
/// textRect/editingRect/placeholderRect.
@MainActor
final class LumenTextField: UITextField {
    var padding: UIEdgeInsets = .zero

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: padding)
    }
    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: padding)
    }
    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: padding)
    }
}

@MainActor
final class TextInputController: NSObject, UITextFieldDelegate {

    weak var textField: LumenTextField?

    var onChange: JSValue?
    var onSubmit: JSValue?
    var onFocus: JSValue?
    var onBlur: JSValue?

    /// Хранится текущее «модельное» значение из JS, чтобы при reconcile не
    /// записывать textField.text вхолостую и не сбрасывать каретку.
    private var lastValue: String = ""

    func attach(_ field: LumenTextField) {
        self.textField = field
        field.delegate = self
        field.addTarget(self,
                         action: #selector(textFieldDidChange(_:)),
                         for: .editingChanged)
    }

    func apply(value: String,
               placeholder: String?,
               style: ViewStyle,
               keyboardType: String?,
               returnKey: String?,
               autocapitalize: String?,
               autocorrect: Bool?,
               secure: Bool?,
               onChange: JSValue?,
               onSubmit: JSValue?,
               onFocus: JSValue?,
               onBlur: JSValue?) {
        guard let field = textField else { return }

        self.onChange = onChange
        self.onSubmit = onSubmit
        self.onFocus = onFocus
        self.onBlur = onBlur

        // Controlled value: пишем только если отличается от того что в поле,
        // иначе iOS сбросит cursor position на end-of-text.
        if field.text != value {
            field.text = value
        }
        lastValue = value

        field.placeholder = placeholder ?? ""

        field.font = TextMeasure.font(for: style)
        if let color = style.color {
            field.textColor = UIColor(cgColor: color)
        } else {
            field.textColor = .label
        }

        if let bg = style.backgroundColor {
            field.backgroundColor = UIColor(cgColor: bg)
        } else {
            field.backgroundColor = .clear
        }

        field.layer.cornerRadius = CGFloat(style.borderRadius)
        field.layer.masksToBounds = style.borderRadius > 0
        if let borderColor = style.borderColor {
            field.layer.borderColor = borderColor
            field.layer.borderWidth = CGFloat(style.borderWidth)
        } else {
            field.layer.borderWidth = 0
        }
        field.alpha = CGFloat(style.opacity)

        let p = style.flex.padding
        field.padding = UIEdgeInsets(top: p.top,
                                     left: p.left,
                                     bottom: p.bottom,
                                     right: p.right)

        field.keyboardType = parseKeyboardType(keyboardType)
        field.returnKeyType = parseReturnKey(returnKey)
        field.autocapitalizationType = parseAutocapitalize(autocapitalize)
        field.autocorrectionType = (autocorrect == false) ? .no : .default
        field.isSecureTextEntry = (secure == true)

        switch style.textAlign {
        case "center":  field.textAlignment = .center
        case "right":   field.textAlignment = .right
        case "justify": field.textAlignment = .justified
        default:        field.textAlignment = .left
        }
    }

    // MARK: - Events

    @objc private func textFieldDidChange(_ sender: UITextField) {
        let v = sender.text ?? ""
        lastValue = v
        if let onChange {
            _ = onChange.call(withArguments: [["value": v]])
        }
    }

    nonisolated func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        return MainActor.assumeIsolated {
            textField.resignFirstResponder()
            if let onSubmit {
                _ = onSubmit.call(withArguments: [["value": textField.text ?? ""]])
            }
            return true
        }
    }

    nonisolated func textFieldDidBeginEditing(_ textField: UITextField) {
        MainActor.assumeIsolated {
            _ = onFocus?.call(withArguments: [])
        }
    }

    nonisolated func textFieldDidEndEditing(_ textField: UITextField) {
        MainActor.assumeIsolated {
            _ = onBlur?.call(withArguments: [])
        }
    }

    // MARK: - Helpers

    private func parseKeyboardType(_ s: String?) -> UIKeyboardType {
        switch s {
        case "url":     return .URL
        case "email":   return .emailAddress
        case "number":  return .numberPad
        case "decimal": return .decimalPad
        case "phone":   return .phonePad
        case "search":  return .webSearch
        default:        return .default
        }
    }

    private func parseReturnKey(_ s: String?) -> UIReturnKeyType {
        switch s {
        case "go":       return .go
        case "next":     return .next
        case "done":     return .done
        case "search":   return .search
        case "send":     return .send
        case "continue": return .continue
        default:         return .default
        }
    }

    private func parseAutocapitalize(_ s: String?) -> UITextAutocapitalizationType {
        switch s {
        case "none":      return .none
        case "sentences": return .sentences
        case "words":     return .words
        case "characters":return .allCharacters
        default:          return .sentences
        }
    }
}
