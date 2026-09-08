import AppKit

/// A borderless inline editor that sits directly over a text annotation, so
/// typing on the page feels like typing in a text box rather than a dialog.
final class TextEditorPopover: NSView, NSTextViewDelegate {

    private let scroll = NSScrollView()
    private let textView = NSTextView()
    private var onCommit: ((String) -> Void)?

    @discardableResult
    static func present(over host: NSView,
                        rect: NSRect,
                        text: String,
                        font: NSFont,
                        color: NSColor,
                        onCommit: @escaping (String) -> Void) -> TextEditorPopover {
        host.subviews.compactMap { $0 as? TextEditorPopover }.forEach { $0.commit() }

        let frame = NSRect(x: rect.minX - 4, y: rect.minY - 4,
                           width: max(140, rect.width + 8), height: max(28, rect.height + 8))
        let editor = TextEditorPopover(frame: frame)
        editor.configure(text: text, font: font, color: color, onCommit: onCommit)
        host.addSubview(editor, positioned: .above, relativeTo: nil)
        host.window?.makeFirstResponder(editor.textView)
        return editor
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.97).cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.35).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        scroll.frame = bounds.insetBy(dx: 5, dy: 4)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.documentView = textView

        textView.isRichText = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 1, height: 2)
        textView.autoresizingMask = [.width]
        textView.delegate = self
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func configure(text: String, font: NSFont, color: NSColor,
                           onCommit: @escaping (String) -> Void) {
        textView.string = text
        textView.font = font
        textView.textColor = color
        textView.selectAll(nil)
        self.onCommit = onCommit
    }

    func commit() {
        onCommit?(textView.string)
        onCommit = nil
        removeFromSuperview()
    }

    func cancel() {
        onCommit = nil
        removeFromSuperview()
    }

    // ⌘Return or Escape finish editing; plain Return inserts a newline.
    func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { cancel(); return true }
        if selector == #selector(NSResponder.insertNewline(_:)),
           NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            commit(); return true
        }
        return false
    }

    override func resignFirstResponder() -> Bool {
        commit()
        return true
    }

    func textDidEndEditing(_ notification: Notification) { commit() }
}
