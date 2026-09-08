import SwiftUI
import PDFKit

struct ToolStrip: View {
    @EnvironmentObject var app: AppModel

    private let groups: [(String, [Tool])] = [
        ("Content", [.select, .editText, .addText]),
        ("Markup", [.highlight, .underline, .strikeout, .note]),
        ("Draw", [.ink, .rectangle, .ellipse, .line, .arrow, .eraser]),
        ("Insert", [.image, .signature, .redact]),
    ]

    var body: some View {
        HStack(spacing: 10) {
            fileCluster
            divider
            ForEach(groups, id: \.0) { group in
                HStack(spacing: 2) {
                    ForEach(group.1) { tool in ToolButton(tool: tool) }
                }
                if group.0 != groups.last?.0 { divider }
            }
            Spacer(minLength: 8)
            StylePicker()
            divider
            accessibilityCluster
            divider
            zoomCluster
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.10)).frame(width: 1, height: 22)
    }

    private var fileCluster: some View {
        HStack(spacing: 2) {
            iconButton("folder", "Open… (⌘O)") { app.openPanel() }
                .accessibilityLabel("Open a PDF")
            iconButton("square.and.arrow.down", "Save (⌘S)") {
                if let doc = app.current { app.save(doc) }
            }
            .disabled(app.current == nil)
            .accessibilityLabel("Save document")
            iconButton("arrow.uturn.backward", "Undo (⌘Z)") {
                app.current?.undoManager.undo()
                app.current?.afterExternalMutation()
            }
            .disabled(app.current?.undoManager.canUndo != true)
            iconButton("arrow.uturn.forward", "Redo (⇧⌘Z)") {
                app.current?.undoManager.redo()
                app.current?.afterExternalMutation()
            }
            .disabled(app.current?.undoManager.canRedo != true)
        }
    }

    private var accessibilityCluster: some View {
        HStack(spacing: 2) {
            Menu {
                Picker("Display", selection: $app.displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Image(systemName: app.displayMode.icon).font(.system(size: 13))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 30)
            .help("Display mode — night, sepia, greyscale, high contrast")
            .accessibilityLabel("Display mode, currently \(app.displayMode.title)")

            iconButton("speaker.wave.2", app.speech.isSpeaking ? "Stop reading" : "Read out loud") {
                guard let doc = app.current else { return }
                app.readAloud(doc, wholeDocument: true)
            }
            .disabled(app.current == nil)
            .accessibilityLabel(app.speech.isSpeaking ? "Stop reading out loud" : "Read out loud")

            iconButton("text.alignleft", "Reading view — reflowed text (⌥⌘R)") {
                guard let doc = app.current else { return }
                app.loadReadingText(doc, wholeDocument: true)
                app.showReadingView = true
            }
            .disabled(app.current == nil)
            .accessibilityLabel("Open reading view")
        }
    }

    private var zoomCluster: some View {
        HStack(spacing: 2) {
            iconButton("minus.magnifyingglass", "Zoom out (⌘−)") { zoom(by: 1 / 1.2) }
            Text(app.zoomLabel)
                .font(.system(size: 11).monospacedDigit())
                .frame(width: 46)
                .foregroundStyle(.secondary)
            iconButton("plus.magnifyingglass", "Zoom in (⌘+)") { zoom(by: 1.2) }
            iconButton("arrow.up.left.and.down.right.magnifyingglass", "Fit to window (⌘0)") { fit() }
        }
    }

    private func iconButton(_ symbol: String, _ help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func zoom(by factor: CGFloat) {
        guard let view = PDFViewLocator.find() else { return }
        view.autoScales = false
        view.scaleFactor = min(max(view.scaleFactor * factor, 0.1), 12)
        app.zoomLabel = "\(Int(view.scaleFactor * 100))%"
    }

    private func fit() {
        guard let view = PDFViewLocator.find() else { return }
        view.autoScales = true
        app.zoomLabel = "Fit"
    }
}

/// Reaches the live PDFView for zoom and navigation commands issued from
/// SwiftUI chrome and the menu bar.
enum PDFViewLocator {
    static func find() -> MarkupPDFView? {
        func search(_ view: NSView) -> MarkupPDFView? {
            if let match = view as? MarkupPDFView { return match }
            for sub in view.subviews { if let match = search(sub) { return match } }
            return nil
        }
        for window in NSApp.windows {
            if let root = window.contentView, let match = search(root) { return match }
        }
        return nil
    }
}

struct ToolButton: View {
    let tool: Tool
    @EnvironmentObject var app: AppModel
    @State private var hovering = false

    var body: some View {
        let active = app.tool == tool
        Button {
            app.tool = tool
            if tool == .redact || tool == .editText { app.showInspector = true }
        } label: {
            Image(systemName: tool.icon)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .frame(width: 30, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(active ? Color.accentColor.opacity(0.9)
                              : hovering ? Color.primary.opacity(0.08) : .clear)
                )
                .foregroundStyle(active ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tool.shortcut.map { "\(tool.title)  ⌃\(String($0.character).uppercased())" } ?? tool.title)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - colour / size controls

struct StylePicker: View {
    @EnvironmentObject var app: AppModel

    private var usesFill: Bool {
        [.highlight, .rectangle, .ellipse, .note].contains(app.tool)
    }

    var body: some View {
        HStack(spacing: 8) {
            switch app.tool {
            case .highlight, .underline, .strikeout, .note:
                palette(MarkupStyle.highlightPalette, binding: $app.style.color)
            case .ink, .rectangle, .ellipse, .line, .arrow:
                palette(MarkupStyle.inkPalette, binding: $app.style.strokeColor)
                widthSlider
                Toggle("Fill", isOn: $app.style.filled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .disabled(app.tool == .line || app.tool == .arrow)
            case .addText:
                palette(MarkupStyle.inkPalette, binding: $app.style.textColor)
                fontSizeStepper
            default:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.15), value: app.tool)
    }

    private func palette(_ colors: [Color], binding: Binding<Color>) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color)
                    .frame(width: 15, height: 15)
                    .overlay(Circle().strokeBorder(.primary.opacity(0.22), lineWidth: 0.5))
                    .overlay(
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                            .opacity(binding.wrappedValue == color ? 1 : 0)
                            .padding(-2.5)
                    )
                    .onTapGesture { binding.wrappedValue = color }
            }
            ColorPicker("", selection: binding)
                .labelsHidden()
                .frame(width: 26)
        }
    }

    private var widthSlider: some View {
        HStack(spacing: 4) {
            Image(systemName: "lineweight").font(.system(size: 10)).foregroundStyle(.secondary)
            Slider(value: $app.style.lineWidth, in: 0.5...16).frame(width: 66)
            Text(String(format: "%.0f", app.style.lineWidth))
                .font(.system(size: 10).monospacedDigit())
                .frame(width: 14)
                .foregroundStyle(.secondary)
        }
    }

    private var fontSizeStepper: some View {
        HStack(spacing: 4) {
            Image(systemName: "textformat.size").font(.system(size: 10)).foregroundStyle(.secondary)
            Stepper(value: $app.style.fontSize, in: 6...96, step: 1) {
                Text("\(Int(app.style.fontSize))")
                    .font(.system(size: 11).monospacedDigit())
                    .frame(width: 20)
            }
        }
    }
}
