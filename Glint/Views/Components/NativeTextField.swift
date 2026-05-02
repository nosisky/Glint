//
//  NativeTextField.swift
//  Glint
//
//  Created by Nas Abdulrasaq.
//  GitHub: https://github.com/nosisky
//

import SwiftUI
import AppKit

/// A reliable text field for macOS that wraps NSTextField via NSViewRepresentable.
/// Standard SwiftUI TextField in sheets can fail to accept keyboard input due to
/// responder chain issues. This bypasses that entirely.
struct NativeTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var isSecure: Bool = false
    var font: NSFont = .systemFont(ofSize: 13)

    func makeNSView(context: Context) -> NSTextField {
        let textField: NSTextField
        if isSecure {
            let secure = NSSecureTextField()
            textField = secure
        } else {
            textField = NSTextField()
        }

        textField.placeholderString = placeholder
        textField.font = font
        textField.delegate = context.coordinator
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .exterior
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.sendsActionOnEndEditing = true
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Only update if the value actually changed (avoid cursor jump)
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                text = textField.stringValue
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                text = textField.stringValue
            }
        }
    }
}

/// A secure variant convenience.
struct NativeSecureField: View {
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        NativeTextField(text: $text, placeholder: placeholder, isSecure: true)
    }
}
