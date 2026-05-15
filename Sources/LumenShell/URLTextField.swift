import SwiftUI
import UIKit

/// UITextField wrapper. Needed for `selectAll(nil)` in `textFieldDidBeginEditing`
/// — SwiftUI TextField can't programmatically select text, so to overwrite
/// a URL you'd need Backspace. With the native field, on focus the whole text
/// is highlighted and any key press overwrites it.
struct URLTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.keyboardType = .URL
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.returnKeyType = .go
        field.clearButtonMode = .never
        field.font = .systemFont(ofSize: 14, weight: .regular)
        field.textColor = UIColor(red: 0.925, green: 0.925, blue: 0.933, alpha: 1)
        field.tintColor = UIColor(red: 0.5, green: 0.72, blue: 1.0, alpha: 1)  // caret/selection
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(red: 0.42, green: 0.42, blue: 0.46, alpha: 1)])
        field.delegate = context.coordinator
        field.addTarget(context.coordinator,
                        action: #selector(Coordinator.textChanged(_:)),
                        for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        // Sync focus state SwiftUI → UIKit.
        if isFocused, !uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        } else if !isFocused, uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.resignFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: URLTextField
        init(_ p: URLTextField) { self.parent = p }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            parent.isFocused = true
            // Pre-select all — typing immediately overwrites the URL.
            DispatchQueue.main.async {
                field.selectAll(nil)
            }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            if parent.isFocused { parent.isFocused = false }
        }
    }
}
