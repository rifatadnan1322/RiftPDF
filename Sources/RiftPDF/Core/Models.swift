import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - Tools

enum Tool: String, CaseIterable, Identifiable, Sendable {
    case select, editText, addText, highlight, underline, strikeout
    case ink, eraser, rectangle, ellipse, line, arrow, note, image, signature, redact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "Select"
        case .editText: "Edit Text"
        case .addText: "Add Text"
        case .highlight: "Highlight"
        case .underline: "Underline"
        case .strikeout: "Strikethrough"
        case .ink: "Draw"
        case .eraser: "Eraser"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .line: "Line"
        case .arrow: "Arrow"
        case .note: "Sticky Note"
        case .image: "Place Image"
        case .signature: "Signature"
        case .redact: "Redact"
        }
    }

    var icon: String {
        switch self {
        case .select: "cursorarrow"
        case .editText: "character.cursor.ibeam"
        case .addText: "textbox"
        case .highlight: "highlighter"
        case .underline: "underline"
        case .strikeout: "strikethrough"
        case .ink: "pencil.tip"
        case .eraser: "eraser"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .note: "note.text"
        case .image: "photo"
        case .signature: "signature"
        case .redact: "rectangle.fill.badge.xmark"
        }
    }

    var shortcut: KeyEquivalent? {
        switch self {
        case .select: "v"
        case .editText: "e"
        case .addText: "t"
        case .highlight: "h"
        case .ink: "d"
        case .rectangle: "r"
        case .ellipse: "o"
        case .line: "l"
        case .note: "n"
        case .redact: "x"
        default: nil
        }
    }

    /// Tools that work off a text selection rather than a dragged rectangle.
    var isTextMarkup: Bool { self == .highlight || self == .underline || self == .strikeout }

    var group: String {
        switch self {
        case .select, .editText, .addText: "Content"
        case .highlight, .underline, .strikeout, .note: "Markup"
        case .ink, .eraser, .rectangle, .ellipse, .line, .arrow: "Draw"
        case .image, .signature, .redact: "Insert"
        }
    }
}

// MARK: - Drawing style

struct MarkupStyle: Equatable {
    var color: Color = .init(red: 0.98, green: 0.78, blue: 0.20)
    var strokeColor: Color = .init(red: 0.90, green: 0.24, blue: 0.24)
    var textColor: Color = .black
    var lineWidth: CGFloat = 2
    var opacity: CGFloat = 1
    var fontSize: CGFloat = 13
    var fontName: String = "Helvetica"
    var filled: Bool = false

    static let highlightPalette: [Color] = [
        Color(red: 0.99, green: 0.85, blue: 0.30), Color(red: 0.56, green: 0.93, blue: 0.60),
        Color(red: 0.55, green: 0.80, blue: 0.99), Color(red: 0.99, green: 0.62, blue: 0.75),
        Color(red: 0.79, green: 0.68, blue: 0.99), Color(red: 0.99, green: 0.68, blue: 0.42),
    ]
    static let inkPalette: [Color] = [
        .black, Color(red: 0.90, green: 0.24, blue: 0.24), Color(red: 0.16, green: 0.47, blue: 0.93),
        Color(red: 0.13, green: 0.66, blue: 0.38), Color(red: 0.95, green: 0.60, blue: 0.10),
        Color(red: 0.52, green: 0.29, blue: 0.87), .white,
    ]
}

// MARK: - Background work

@MainActor
final class TaskProgress: ObservableObject, Identifiable {
    let id = UUID()
    let title: String
    @Published var fraction: Double = 0
    @Published var message: String = "Starting…"
    @Published var isIndeterminate = true
    @Published var finished = false
    @Published var failure: String?

    init(title: String) { self.title = title }

    func update(_ value: Double, _ text: String) {
        isIndeterminate = false
        fraction = value
        if !text.isEmpty { message = text }
    }
}

// MARK: - Toast

struct Toast: Identifiable, Equatable {
    enum Kind { case success, warning, failure, info }
    let id = UUID()
    var kind: Kind = .success
    var title: String
    var detail: String?
    var actionTitle: String?
    var revealURL: URL?

    var icon: String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        }
    }
    var tint: Color {
        switch kind {
        case .success: .green
        case .warning: .orange
        case .failure: .red
        case .info: .accentColor
        }
    }
    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

// MARK: - Sheets

enum SheetRoute: Identifiable, Equatable {
    case compress, metadata, watermark, pageNumbers, security, exportImages
    case merge, imagesToPDF, ocr, formFill, attachments
    case documentInfo, bookmarks, compare, preferences, split
    case accessibility, headerFooter, auditSpace, batch

    var id: String { String(describing: self) }
}

// MARK: - Utilities

extension Color {
    var nsColor: NSColor { NSColor(self) }

    /// PDF colour space wants plain 0…1 components.
    var pdfComponents: [Double] {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)]
    }
}

extension URL {
    var displayName: String { deletingPathExtension().lastPathComponent }

    func uniqueSibling(suffix: String, ext: String? = nil) -> URL {
        let dir = deletingLastPathComponent()
        let base = deletingPathExtension().lastPathComponent + suffix
        let fileExt = ext ?? pathExtension
        var candidate = dir.appendingPathComponent(base).appendingPathExtension(fileExt)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(fileExt)
            n += 1
        }
        return candidate
    }
}

func formatBytes(_ bytes: Int) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f.string(fromByteCount: Int64(bytes))
}

extension UTType {
    static let riftpdfWord = UTType(filenameExtension: "docx") ?? .data
}
