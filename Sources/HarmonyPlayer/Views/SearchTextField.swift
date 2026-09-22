import SwiftUI
import AppKit

/// 原生 NSTextField 包装器：解决 SwiftUI TextField 在本应用（NSApp.appearance
/// 被强制 darkAqua、界面实际外观由 preferredColorScheme 控制）下，输入文字颜色
/// 不受控的历史问题。字段编辑器继承控件的 textColor，编辑中文字颜色 100% 生效。
struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var textColor: NSColor
    var placeholderColor: NSColor

    private static let placeholder = "搜索歌曲、艺人和专辑"

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.delegate = context.coordinator
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.font = .systemFont(ofSize: 12)
        tf.lineBreakMode = .byTruncatingTail
        tf.textColor = textColor
        applyPlaceholderColor(to: tf)
        tf.stringValue = text
        return tf
    }

    func updateNSView(_ tf: NSTextField, context: Context) {
        if tf.stringValue != text {
            tf.stringValue = text
        }
        tf.textColor = textColor
        applyPlaceholderColor(to: tf)
        // @FocusState 变化时同步原生焦点。
        if isFocused.wrappedValue && tf.window?.firstResponder !== tf {
            tf.window?.makeFirstResponder(tf)
        }
        context.coordinator.bindings = (text: $text, isFocused: isFocused)
    }

    private func applyPlaceholderColor(to tf: NSTextField) {
        (tf.cell as? NSTextFieldCell)?.placeholderAttributedString = NSAttributedString(
            string: Self.placeholder,
            attributes: [
                .foregroundColor: placeholderColor,
                .font: NSFont.systemFont(ofSize: 12)
            ]
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: isFocused)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var bindings: (text: Binding<String>, isFocused: FocusState<Bool>.Binding)

        init(text: Binding<String>, isFocused: FocusState<Bool>.Binding) {
            bindings = (text: text, isFocused: isFocused)
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            bindings.text.wrappedValue = tf.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            bindings.isFocused.wrappedValue = true
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            bindings.isFocused.wrappedValue = false
        }
    }
}
