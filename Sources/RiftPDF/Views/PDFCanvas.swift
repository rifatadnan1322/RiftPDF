import SwiftUI
import PDFKit

// MARK: - image stamp

/// An image placed on the page. Drawn live by PDFKit while the user positions
/// it; burned into the page content on save so other readers see it too.
final class ImageStampAnnotation: PDFAnnotation {

    var image: NSImage?

    init(bounds: CGRect, image: NSImage) {
        self.image = image
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        guard let image, let page else { return }
        let pageBounds = page.bounds(for: box)
        var rect = bounds
        rect.origin.x -= pageBounds.origin.x
        rect.origin.y -= pageBounds.origin.y
        var target = rect
        guard let cg = image.cgImage(forProposedRect: &target, context: nil, hints: nil) else { return }
        context.saveGState()
        context.setAlpha(1.0)
        context.draw(cg, in: rect)
        context.restoreGState()
    }

    func pngData() -> Data? {
        guard let image,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - selection handles

/// The eight scaling grips around a selected object, plus the body for moving.
enum ResizeHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    static let size: CGFloat = 8
    static let hitSlop: CGFloat = 5

    /// Position in a rect expressed in view coordinates (origin bottom-left).
    func point(in rect: NSRect) -> NSPoint {
        switch self {
        case .topLeft:     NSPoint(x: rect.minX, y: rect.maxY)
        case .top:         NSPoint(x: rect.midX, y: rect.maxY)
        case .topRight:    NSPoint(x: rect.maxX, y: rect.maxY)
        case .right:       NSPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: NSPoint(x: rect.maxX, y: rect.minY)
        case .bottom:      NSPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft:  NSPoint(x: rect.minX, y: rect.minY)
        case .left:        NSPoint(x: rect.minX, y: rect.midY)
        }
    }

    func grip(in rect: NSRect) -> NSRect {
        let p = point(in: rect)
        return NSRect(x: p.x - Self.size / 2, y: p.y - Self.size / 2,
                      width: Self.size, height: Self.size)
    }

    var isCorner: Bool {
        self == .topLeft || self == .topRight || self == .bottomLeft || self == .bottomRight
    }

    var cursor: NSCursor {
        switch self {
        case .left, .right: .resizeLeftRight
        case .top, .bottom: .resizeUpDown
        default: .crosshair
        }
    }

    /// Applies the drag to a rect, holding the opposite edge or corner still.
    func resize(_ rect: CGRect, to point: CGPoint, minimum: CGFloat) -> CGRect {
        var r = rect
        switch self {
        case .left:
            let maxX = r.maxX
            r.origin.x = min(point.x, maxX - minimum)
            r.size.width = maxX - r.origin.x
        case .right:
            r.size.width = max(minimum, point.x - r.minX)
        case .bottom:
            let maxY = r.maxY
            r.origin.y = min(point.y, maxY - minimum)
            r.size.height = maxY - r.origin.y
        case .top:
            r.size.height = max(minimum, point.y - r.minY)
        case .bottomLeft:
            r = ResizeHandle.left.resize(r, to: point, minimum: minimum)
            r = ResizeHandle.bottom.resize(r, to: point, minimum: minimum)
        case .bottomRight:
            r = ResizeHandle.right.resize(r, to: point, minimum: minimum)
            r = ResizeHandle.bottom.resize(r, to: point, minimum: minimum)
        case .topLeft:
            r = ResizeHandle.left.resize(r, to: point, minimum: minimum)
            r = ResizeHandle.top.resize(r, to: point, minimum: minimum)
        case .topRight:
            r = ResizeHandle.right.resize(r, to: point, minimum: minimum)
            r = ResizeHandle.top.resize(r, to: point, minimum: minimum)
        }
        return r
    }

    /// Keeps the original proportions, anchored on the fixed corner.
    func constrain(_ rect: CGRect, to original: CGRect, minimum: CGFloat) -> CGRect {
        guard original.width > 0, original.height > 0 else { return rect }
        let ratio = original.height / original.width
        var r = rect
        let width = max(minimum, r.width)
        let height = max(minimum, r.height)
        // grow along whichever axis the user pulled hardest
        if width * ratio >= height {
            r.size.width = width
            r.size.height = width * ratio
        } else {
            r.size.height = height
            r.size.width = height / ratio
        }
        // re-anchor so the opposite corner stays put
        switch self {
        case .topLeft:     r.origin = CGPoint(x: rect.maxX - r.width, y: rect.minY)
        case .top:         r.origin = CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:    r.origin = CGPoint(x: rect.minX, y: rect.minY)
        case .left:        r.origin = CGPoint(x: rect.maxX - r.width, y: rect.maxY - r.height)
        case .right:       r.origin = CGPoint(x: rect.minX, y: rect.maxY - r.height)
        case .bottomLeft:  r.origin = CGPoint(x: rect.maxX - r.width, y: rect.maxY - r.height)
        case .bottom:      r.origin = CGPoint(x: rect.minX, y: rect.maxY - r.height)
        case .bottomRight: r.origin = CGPoint(x: rect.minX, y: rect.maxY - r.height)
        }
        return r
    }
}

// MARK: - live preview overlay

final class MarkupOverlay: NSView {
    var tool: Tool = .select
    var style = MarkupStyle()
    var start: NSPoint?
    var end: NSPoint?
    var inkPoints: [NSPoint] = []

    /// Bounding box of the selected object, in view coordinates.
    var selectionRect: NSRect?
    var selectionResizable = true
    var selectionLabel: String?

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // never steal events

    func reset() {
        start = nil; end = nil; inkPoints = []
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)

        drawSelection()

        if tool == .ink, inkPoints.count > 1 {
            let path = NSBezierPath()
            path.lineWidth = style.lineWidth
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.move(to: inkPoints[0])
            for i in 1..<inkPoints.count {
                let mid = NSPoint(x: (inkPoints[i - 1].x + inkPoints[i].x) / 2,
                                  y: (inkPoints[i - 1].y + inkPoints[i].y) / 2)
                path.curve(to: mid, controlPoint1: inkPoints[i - 1], controlPoint2: inkPoints[i - 1])
            }
            style.strokeColor.nsColor.withAlphaComponent(style.opacity).setStroke()
            path.stroke()
            return
        }

        guard let start, let end else { return }
        let rect = NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))

        switch tool {
        case .rectangle, .addText, .image, .signature:
            let path = NSBezierPath(rect: rect)
            path.lineWidth = style.lineWidth
            if style.filled || tool == .addText {
                style.color.nsColor.withAlphaComponent(tool == .addText ? 0.10 : style.opacity).setFill()
                path.fill()
            }
            style.strokeColor.nsColor.withAlphaComponent(style.opacity).setStroke()
            if tool != .rectangle {
                path.setLineDash([5, 4], count: 2, phase: 0)
            }
            path.stroke()
        case .ellipse:
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = style.lineWidth
            if style.filled {
                style.color.nsColor.withAlphaComponent(style.opacity).setFill()
                path.fill()
            }
            style.strokeColor.nsColor.withAlphaComponent(style.opacity).setStroke()
            path.stroke()
        case .line, .arrow:
            let path = NSBezierPath()
            path.lineWidth = style.lineWidth
            path.lineCapStyle = .round
            path.move(to: start)
            path.line(to: end)
            style.strokeColor.nsColor.withAlphaComponent(style.opacity).setStroke()
            path.stroke()
            if tool == .arrow { drawArrowHead(from: start, to: end, path: path) }
        case .redact:
            NSColor.black.withAlphaComponent(0.82).setFill()
            NSBezierPath(rect: rect).fill()
            NSColor.systemRed.setStroke()
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 1.5
            outline.stroke()
        default:
            break
        }
    }

    private func drawSelection() {
        guard let rect = selectionRect else { return }
        let accent = NSColor.controlAccentColor

        // outline
        let outline = NSBezierPath(rect: rect.insetBy(dx: -1.5, dy: -1.5))
        outline.lineWidth = 1.5
        accent.withAlphaComponent(0.95).setStroke()
        outline.setLineDash([4, 3], count: 2, phase: 0)
        outline.stroke()

        guard selectionResizable else { return }

        // grips
        for handle in ResizeHandle.allCases {
            let grip = handle.grip(in: rect)
            let path = NSBezierPath(roundedRect: grip, xRadius: 1.5, yRadius: 1.5)
            NSColor.white.setFill()
            path.fill()
            accent.setStroke()
            path.lineWidth = 1.5
            path.setLineDash(nil, count: 0, phase: 0)
            path.stroke()
        }

        // live size readout while dragging
        if let label = selectionLabel {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
            let size = label.size(withAttributes: attrs)
            let box = NSRect(x: rect.midX - size.width / 2 - 6,
                             y: rect.minY - size.height - 12,
                             width: size.width + 12, height: size.height + 6)
            let bubble = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
            accent.withAlphaComponent(0.92).setFill()
            bubble.fill()
            label.draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attrs)
        }
    }

    private func drawArrowHead(from: NSPoint, to: NSPoint, path: NSBezierPath) {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let size = max(9, style.lineWidth * 4)
        let head = NSBezierPath()
        head.move(to: to)
        head.line(to: NSPoint(x: to.x - size * cos(angle - .pi / 7),
                              y: to.y - size * sin(angle - .pi / 7)))
        head.line(to: NSPoint(x: to.x - size * cos(angle + .pi / 7),
                              y: to.y - size * sin(angle + .pi / 7)))
        head.close()
        style.strokeColor.nsColor.withAlphaComponent(style.opacity).setFill()
        head.fill()
    }
}

// MARK: - the PDF view

final class MarkupPDFView: PDFView {

    var tool: Tool = .select { didSet { updateCursor() } }
    var style = MarkupStyle()
    weak var doc: PDFDoc?

    var onSelectAnnotation: ((PDFAnnotation?) -> Void)?
    var onEditText: ((PDFAnnotation) -> Void)?
    var onRedaction: ((Int, CGRect) -> Void)?
    var onNeedImage: ((@escaping (NSImage?) -> Void) -> Void)?
    var onPageChange: ((Int) -> Void)?

    let overlay = MarkupOverlay()

    private var dragStartInView: NSPoint?
    private var dragPage: PDFPage?
    private var movingAnnotation: PDFAnnotation?
    private var moveOffset: NSPoint = .zero
    private var activeHandle: ResizeHandle?
    private var boundsBeforeDrag: CGRect = .zero
    private var pathsBeforeDrag: [NSBezierPath] = []
    private var lineEndsBeforeDrag: (CGPoint, CGPoint)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        commonSetup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonSetup()
    }

    private func commonSetup() {
        overlay.autoresizingMask = [.width, .height]
        overlay.frame = bounds
        addSubview(overlay, positioned: .above, relativeTo: nil)
        wantsLayer = true
        DispatchQueue.main.async { [weak self] in self?.observeViewport() }
    }

    override func layout() {
        super.layout()
        overlay.frame = bounds
        refreshSelection()
    }

    /// Objects whose geometry can be scaled meaningfully.
    static func isResizable(_ annotation: PDFAnnotation) -> Bool {
        switch annotation.type ?? "" {
        case "Stamp", "FreeText", "Square", "Circle", "Line", "Ink": true
        default: false
        }
    }

    /// The rectangle a user perceives as the object. Ink annotations carry
    /// page-sized bounds, so their drawn extent has to be measured instead.
    static func visualBounds(_ annotation: PDFAnnotation) -> CGRect {
        if annotation.type == "Ink", let paths = annotation.paths, !paths.isEmpty {
            var box = paths[0].bounds
            for path in paths.dropFirst() { box = box.union(path.bounds) }
            let width = annotation.border?.lineWidth ?? 2
            return box.insetBy(dx: -width, dy: -width)
                .offsetBy(dx: annotation.bounds.minX, dy: annotation.bounds.minY)
        }
        return annotation.bounds
    }

    /// Redraws the selection outline wherever the page currently sits.
    func refreshSelection(label: String? = nil) {
        guard let annotation = selection, let page = annotation.page,
              document?.index(for: page) != NSNotFound else {
            overlay.selectionRect = nil
            overlay.selectionLabel = nil
            overlay.needsDisplay = true
            return
        }
        let pageRect = Self.visualBounds(annotation)
        overlay.selectionRect = convert(pageRect, from: page)
        overlay.selectionResizable = Self.isResizable(annotation)
        overlay.selectionLabel = label
        overlay.needsDisplay = true
    }

    private func observeViewport() {
        NotificationCenter.default.addObserver(
            forName: .PDFViewScaleChanged, object: self, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSelection() }
        }
        if let scroll = subviews.compactMap({ $0 as? NSScrollView }).first {
            scroll.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scroll.contentView, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSelection() }
            }
        }
    }

    private func updateCursor() {
        switch tool {
        case .select: NSCursor.arrow.set()
        case .addText, .editText: NSCursor.iBeam.set()
        case .eraser: NSCursor.disappearingItem.set()
        default: NSCursor.crosshair.set()
        }
    }

    override func resetCursorRects() {
        discardCursorRects()
        if tool == .select, let rect = overlay.selectionRect,
           let current = selection, Self.isResizable(current) {
            for handle in ResizeHandle.allCases {
                addCursorRect(handle.grip(in: rect).insetBy(dx: -ResizeHandle.hitSlop,
                                                            dy: -ResizeHandle.hitSlop),
                              cursor: handle.cursor)
            }
        }
        let cursor: NSCursor
        switch tool {
        case .select: cursor = .arrow
        case .addText: cursor = .crosshair
        case .editText: cursor = .iBeam
        case .eraser: cursor = .disappearingItem
        default: cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: mouse

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: true) else { return }
        let pagePoint = convert(viewPoint, to: page)
        dragPage = page
        dragStartInView = viewPoint

        switch tool {
        case .select:
            // a grip on the current selection wins over anything underneath
            if let current = selection, let rect = overlay.selectionRect,
               Self.isResizable(current),
               let handle = ResizeHandle.allCases.first(where: {
                   $0.grip(in: rect).insetBy(dx: -ResizeHandle.hitSlop,
                                             dy: -ResizeHandle.hitSlop).contains(viewPoint)
               }) {
                activeHandle = handle
                movingAnnotation = current
                beginGeometryDrag(current)
                return
            }

            if let hit = annotation(at: pagePoint, on: page) {
                movingAnnotation = hit
                activeHandle = nil
                let visual = Self.visualBounds(hit)
                moveOffset = NSPoint(x: pagePoint.x - visual.minX, y: pagePoint.y - visual.minY)
                beginGeometryDrag(hit)
                selection = hit
                onSelectAnnotation?(hit)
                refreshSelection()
                if event.clickCount == 2, hit.type == "FreeText" || hit.type == "Text" {
                    onEditText?(hit)
                }
                return
            }
            selection = nil
            refreshSelection()
            onSelectAnnotation?(nil)
            super.mouseDown(with: event)

        case .highlight, .underline, .strikeout:
            super.mouseDown(with: event)

        case .eraser:
            if let hit = annotation(at: pagePoint, on: page) { doc?.removeAnnotation(hit) }

        case .note:
            let size = CGSize(width: 24, height: 24)
            let bounds = CGRect(x: pagePoint.x - size.width / 2, y: pagePoint.y - size.height / 2,
                                width: size.width, height: size.height)
            let note = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
            note.color = style.color.nsColor
            note.contents = ""
            note.iconType = .comment
            doc?.addAnnotation(note, to: page, name: "Add Note")
            onSelectAnnotation?(note)
            onEditText?(note)

        case .image, .signature:
            beginImagePlacement(at: pagePoint, page: page)

        default:
            overlay.tool = tool
            overlay.style = style
            overlay.start = viewPoint
            overlay.end = viewPoint
            overlay.needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)

        if let annotation = movingAnnotation, let page = annotation.page {
            let pagePoint = convert(viewPoint, to: page)

            if let handle = activeHandle {
                var frame = handle.resize(boundsBeforeDrag, to: pagePoint, minimum: 14)
                let wantsAspect = handle.isCorner
                    && (event.modifierFlags.contains(.shift) != (annotation is ImageStampAnnotation))
                if wantsAspect {
                    frame = handle.constrain(frame, to: boundsBeforeDrag, minimum: 14)
                }
                applyGeometry(frame, to: annotation)
                refreshSelection(label: String(format: "%.0f × %.0f pt", frame.width, frame.height))
            } else {
                var frame = boundsBeforeDrag
                frame.origin = CGPoint(x: pagePoint.x - moveOffset.x,
                                       y: pagePoint.y - moveOffset.y)
                applyGeometry(frame, to: annotation)
                refreshSelection()
            }
            setNeedsDisplay(bounds)
            return
        }

        switch tool {
        case .select, .highlight, .underline, .strikeout:
            super.mouseDragged(with: event)
        case .ink:
            overlay.tool = .ink
            overlay.style = style
            overlay.inkPoints.append(viewPoint)
            overlay.needsDisplay = true
        case .eraser, .note, .image, .signature:
            break
        default:
            overlay.end = viewPoint
            overlay.needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            overlay.reset()
            dragStartInView = nil
            dragPage = nil
        }

        if let annotation = movingAnnotation {
            commitGeometryDrag(annotation)
            movingAnnotation = nil
            activeHandle = nil
            refreshSelection()
            return
        }

        let viewPoint = convert(event.locationInWindow, from: nil)

        switch tool {
        case .select:
            super.mouseUp(with: event)

        case .highlight, .underline, .strikeout:
            super.mouseUp(with: event)
            applyTextMarkup()

        case .ink:
            commitInk()

        case .rectangle, .ellipse, .line, .arrow, .addText, .redact:
            guard let start = dragStartInView, let page = dragPage else { return }
            commitShape(from: start, to: viewPoint, page: page)

        default:
            break
        }
    }

    // MARK: committing annotations

    private func applyTextMarkup() {
        guard let selection = currentSelection, let doc else { return }
        let subtype: PDFAnnotationSubtype = switch tool {
        case .underline: .underline
        case .strikeout: .strikeOut
        default: .highlight
        }
        var added = 0
        doc.perform(tool.title) {
            for page in selection.pages {
                for line in selection.selectionsByLine() where line.pages.contains(page) {
                    let rect = line.bounds(for: page)
                    guard rect.width > 1, rect.height > 1 else { continue }
                    let annotation = PDFAnnotation(bounds: rect, forType: subtype, withProperties: nil)
                    annotation.color = style.color.nsColor.withAlphaComponent(
                        subtype == .highlight ? 0.42 : 1.0)
                    page.addAnnotation(annotation)
                    added += 1
                    doc.registerUndo(tool.title) { _ in page.removeAnnotation(annotation) }
                }
            }
        }
        if added > 0 { clearSelection() }
    }

    private func commitInk() {
        guard overlay.inkPoints.count > 1, let doc,
              let page = page(for: overlay.inkPoints[0], nearest: true) else { return }
        let points = overlay.inkPoints.map { convert($0, to: page) }
        let path = NSBezierPath()
        path.lineWidth = style.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: points[0])
        for i in 1..<points.count {
            let mid = NSPoint(x: (points[i - 1].x + points[i].x) / 2,
                              y: (points[i - 1].y + points[i].y) / 2)
            path.curve(to: mid, controlPoint1: points[i - 1], controlPoint2: points[i - 1])
        }
        // Page-sized bounds keep PDFKit's ink geometry honest across readers.
        let annotation = PDFAnnotation(bounds: page.bounds(for: .mediaBox),
                                       forType: .ink, withProperties: nil)
        let border = PDFBorder()
        border.lineWidth = style.lineWidth
        annotation.border = border
        annotation.color = style.strokeColor.nsColor.withAlphaComponent(style.opacity)
        annotation.add(path)
        doc.addAnnotation(annotation, to: page, name: "Draw")
    }

    private func commitShape(from start: NSPoint, to end: NSPoint, page: PDFPage) {
        let a = convert(start, to: page), b = convert(end, to: page)
        var rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                          width: abs(b.x - a.x), height: abs(b.y - a.y))
        guard let doc else { return }

        switch tool {
        case .redact:
            guard rect.width > 3, rect.height > 3 else { return }
            let index = doc.document.index(for: page)
            let pageBounds = page.bounds(for: .mediaBox)
            // hand the engine top-left origin coordinates
            let flipped = CGRect(x: rect.minX, y: pageBounds.height - rect.maxY,
                                 width: rect.width, height: rect.height)
            onRedaction?(index, flipped)
            let marker = PDFAnnotation(bounds: rect, forType: .square, withProperties: nil)
            marker.color = .systemRed
            marker.interiorColor = NSColor.black.withAlphaComponent(0.85)
            let border = PDFBorder(); border.lineWidth = 1.5
            marker.border = border
            marker.userName = "riftpdf.redaction"
            doc.addAnnotation(marker, to: page, name: "Mark for Redaction")

        case .addText:
            if rect.width < 20 { rect.size.width = 240 }
            if rect.height < 18 { rect.size.height = max(24, style.fontSize * 1.8) }
            let annotation = PDFAnnotation(bounds: rect, forType: .freeText, withProperties: nil)
            annotation.font = NSFont(name: style.fontName, size: style.fontSize)
                ?? .systemFont(ofSize: style.fontSize)
            annotation.fontColor = style.textColor.nsColor
            annotation.color = .clear
            annotation.contents = ""
            annotation.alignment = .left
            doc.addAnnotation(annotation, to: page, name: "Add Text")
            onSelectAnnotation?(annotation)
            onEditText?(annotation)

        case .line, .arrow:
            let padded = rect.insetBy(dx: -style.lineWidth * 3, dy: -style.lineWidth * 3)
            let annotation = PDFAnnotation(bounds: padded, forType: .line, withProperties: nil)
            annotation.startPoint = CGPoint(x: a.x - padded.minX, y: a.y - padded.minY)
            annotation.endPoint = CGPoint(x: b.x - padded.minX, y: b.y - padded.minY)
            if tool == .arrow { annotation.endLineStyle = .closedArrow }
            annotation.color = style.strokeColor.nsColor.withAlphaComponent(style.opacity)
            let border = PDFBorder(); border.lineWidth = style.lineWidth
            annotation.border = border
            doc.addAnnotation(annotation, to: page, name: tool.title)

        default:
            guard rect.width > 3, rect.height > 3 else { return }
            let subtype: PDFAnnotationSubtype = tool == .ellipse ? .circle : .square
            let annotation = PDFAnnotation(bounds: rect, forType: subtype, withProperties: nil)
            annotation.color = style.strokeColor.nsColor.withAlphaComponent(style.opacity)
            if style.filled {
                annotation.interiorColor = style.color.nsColor.withAlphaComponent(style.opacity)
            }
            let border = PDFBorder(); border.lineWidth = style.lineWidth
            annotation.border = border
            doc.addAnnotation(annotation, to: page, name: tool.title)
        }
    }

    private func beginImagePlacement(at point: CGPoint, page: PDFPage) {
        onNeedImage? { [weak self] image in
            guard let self, let image, let doc = self.doc else { return }
            let maxWidth: CGFloat = self.tool == .signature ? 200 : 320
            let ratio = image.size.height / max(1, image.size.width)
            let size = CGSize(width: maxWidth, height: maxWidth * ratio)
            let bounds = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                width: size.width, height: size.height)
            let stamp = ImageStampAnnotation(bounds: bounds, image: image)
            doc.addAnnotation(stamp, to: page, name: "Place Image")
            self.onSelectAnnotation?(stamp)
        }
    }

    /// Low-vision display modes re-render the page through Core Image filters
    /// rather than painting an overlay, so text stays sharp.
    func applyDisplayMode(_ mode: DisplayMode) {
        guard appliedDisplayMode != mode else { return }
        appliedDisplayMode = mode
        let filters = mode.filters
        contentFilters = filters
        // the surrounding grey should follow the mode too
        backgroundColor = mode == .night || mode == .highContrast
            ? NSColor(calibratedWhite: 0.10, alpha: 1)
            : NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(calibratedWhite: 0.12, alpha: 1)
                    : NSColor(calibratedWhite: 0.88, alpha: 1)
            }
        needsDisplay = true
    }

    private var appliedDisplayMode: DisplayMode?

    // MARK: geometry

    private func beginGeometryDrag(_ annotation: PDFAnnotation) {
        boundsBeforeDrag = Self.visualBounds(annotation)
        pathsBeforeDrag = (annotation.paths ?? []).compactMap { $0.copy() as? NSBezierPath }
        lineEndsBeforeDrag = annotation.type == "Line"
            ? (annotation.startPoint, annotation.endPoint) : nil
    }

    /// Moves and scales the annotation, including the bits PDFKit does not
    /// carry along with `bounds` — ink strokes and line endpoints.
    private func applyGeometry(_ target: CGRect, to annotation: PDFAnnotation) {
        let source = boundsBeforeDrag
        guard source.width > 0, source.height > 0 else { return }
        let scaleX = target.width / source.width
        let scaleY = target.height / source.height

        if annotation.type == "Ink", !pathsBeforeDrag.isEmpty {
            // Ink keeps page-sized bounds, so the strokes have to be rescaled by
            // hand. Work in stroke space: the visual box is the path box grown
            // by half the stroke width on each side, and that padding must not
            // be scaled along with the drawing.
            let inset = annotation.border?.lineWidth ?? 2
            let origin = annotation.bounds.origin
            let from = source.insetBy(dx: inset, dy: inset)
                .offsetBy(dx: -origin.x, dy: -origin.y)
            let to = target.insetBy(dx: inset, dy: inset)
                .offsetBy(dx: -origin.x, dy: -origin.y)
            guard from.width > 0.5, from.height > 0.5, to.width > 0.5, to.height > 0.5 else { return }

            for path in annotation.paths ?? [] { annotation.remove(path) }
            for original in pathsBeforeDrag {
                guard let copy = original.copy() as? NSBezierPath else { continue }
                var transform = AffineTransform(translationByX: -from.minX, byY: -from.minY)
                transform.append(AffineTransform(scaleByX: to.width / from.width,
                                                 byY: to.height / from.height))
                transform.append(AffineTransform(translationByX: to.minX, byY: to.minY))
                copy.transform(using: transform)
                annotation.add(copy)
            }
            return
        }

        annotation.bounds = target

        if annotation.type == "Line", let (start, end) = lineEndsBeforeDrag {
            annotation.startPoint = CGPoint(x: (start.x) * scaleX, y: (start.y) * scaleY)
            annotation.endPoint = CGPoint(x: (end.x) * scaleX, y: (end.y) * scaleY)
        }
    }

    /// Sets an object's rectangle from outside the drag loop (numeric fields).
    func setGeometry(_ rect: CGRect, of annotation: PDFAnnotation) {
        beginGeometryDrag(annotation)
        applyGeometry(rect, to: annotation)
        commitGeometryDrag(annotation)
        refreshSelection()
        setNeedsDisplay(bounds)
    }

    private func commitGeometryDrag(_ annotation: PDFAnnotation) {
        let before = boundsBeforeDrag
        let beforePaths = pathsBeforeDrag
        let beforeLine = lineEndsBeforeDrag
        let after = Self.visualBounds(annotation)
        guard abs(before.minX - after.minX) > 0.01 || abs(before.minY - after.minY) > 0.01
                || abs(before.width - after.width) > 0.01
                || abs(before.height - after.height) > 0.01 else { return }

        let afterPaths = (annotation.paths ?? []).compactMap { $0.copy() as? NSBezierPath }
        let afterLine = annotation.type == "Line" ? (annotation.startPoint, annotation.endPoint) : nil
        let name = activeHandle == nil ? "Move" : "Resize"

        doc?.perform(name) {
            doc?.registerUndo(name) { [weak self] target in
                Self.restore(annotation, bounds: before, paths: beforePaths, line: beforeLine)
                target.afterExternalMutation()
                self?.refreshSelection()
                target.undoManager.registerUndo(withTarget: target) { redoTarget in
                    MainActor.assumeIsolated {
                        Self.restore(annotation, bounds: after, paths: afterPaths, line: afterLine)
                        redoTarget.afterExternalMutation()
                        self?.refreshSelection()
                    }
                }
            }
        }
    }

    private static func restore(_ annotation: PDFAnnotation, bounds: CGRect,
                                paths: [NSBezierPath], line: (CGPoint, CGPoint)?) {
        if annotation.type == "Ink" {
            for path in annotation.paths ?? [] { annotation.remove(path) }
            for path in paths { annotation.add(path) }
        } else {
            annotation.bounds = bounds
            if let line {
                annotation.startPoint = line.0
                annotation.endPoint = line.1
            }
        }
    }

    // MARK: hit testing

    /// Picks the smallest object under the pointer, so a page-wide ink stroke
    /// cannot swallow every click on the page.
    func annotation(at point: CGPoint, on page: PDFPage) -> PDFAnnotation? {
        page.annotations
            .filter { Self.visualBounds($0).insetBy(dx: -3, dy: -3).contains(point) }
            .min { a, b in
                let ra = Self.visualBounds(a), rb = Self.visualBounds(b)
                return ra.width * ra.height < rb.width * rb.height
            }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {   // delete / forward delete
            if let selected = selection {
                doc?.removeAnnotation(selected)
                selection = nil
                refreshSelection()
                onSelectAnnotation?(nil)
                return
            }
        }

        // arrows nudge the selection; with shift they scale it
        let arrows: [UInt16: CGVector] = [123: CGVector(dx: -1, dy: 0), 124: CGVector(dx: 1, dy: 0),
                                          125: CGVector(dx: 0, dy: -1), 126: CGVector(dx: 0, dy: 1)]
        if let delta = arrows[event.keyCode], let annotation = selection {
            let step: CGFloat = event.modifierFlags.contains(.option) ? 1 : 8
            beginGeometryDrag(annotation)
            var frame = boundsBeforeDrag
            if event.modifierFlags.contains(.shift) {
                frame.size.width = max(14, frame.width + delta.dx * step)
                frame.size.height = max(14, frame.height + delta.dy * step)
            } else {
                frame.origin.x += delta.dx * step
                frame.origin.y += delta.dy * step
            }
            applyGeometry(frame, to: annotation)
            commitGeometryDrag(annotation)
            refreshSelection()
            setNeedsDisplay(bounds)
            return
        }

        super.keyDown(with: event)
    }

    override var acceptsFirstResponder: Bool { true }

    var selection: PDFAnnotation?
}

// MARK: - SwiftUI bridge

struct PDFCanvas: NSViewRepresentable {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel

    func makeNSView(context: Context) -> MarkupPDFView {
        let view = MarkupPDFView()
        view.document = doc.document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.pageShadowsEnabled = true
        view.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.12, alpha: 1)
                : NSColor(calibratedWhite: 0.88, alpha: 1)
        }
        view.interpolationQuality = .high
        view.doc = doc
        context.coordinator.attach(view: view)
        return view
    }

    func updateNSView(_ view: MarkupPDFView, context: Context) {
        if view.document !== doc.document {
            view.document = doc.document
            view.doc = doc
            view.go(to: doc.document.page(at: min(doc.currentPage, doc.pageCount - 1)) ?? view.currentPage!)
        }
        view.tool = app.tool
        view.style = app.style
        view.applyDisplayMode(app.displayMode)
        view.overlay.style = app.style
        if view.selection !== app.selectedAnnotation {
            view.selection = app.selectedAnnotation
        }
        view.refreshSelection()
        context.coordinator.app = app
        context.coordinator.doc = doc
        view.window?.invalidateCursorRects(for: view)

        // keep the visible page in sync with the sidebar
        if let target = doc.document.page(at: doc.currentPage),
           view.currentPage !== target, !context.coordinator.suppressScroll {
            view.go(to: target)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(doc: doc, app: app) }

    @MainActor
    final class Coordinator: NSObject {
        var doc: PDFDoc
        var app: AppModel
        var suppressScroll = false
        weak var view: MarkupPDFView?

        init(doc: PDFDoc, app: AppModel) {
            self.doc = doc
            self.app = app
        }

        func attach(view: MarkupPDFView) {
            self.view = view
            view.onSelectAnnotation = { [weak self] annotation in
                self?.app.selectedAnnotation = annotation
                if annotation != nil { self?.app.showInspector = true }
            }
            view.onRedaction = { [weak self] page, rect in
                self?.app.pendingRedactions[page, default: []].append(rect)
            }
            view.onNeedImage = { [weak self] completion in
                self?.pickImage(completion)
            }
            view.onEditText = { [weak self] annotation in
                self?.editText(annotation)
            }
            NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged, object: view, queue: .main
            ) { [weak self, weak view] _ in
                MainActor.assumeIsolated {
                    guard let self, let view, let page = view.currentPage else { return }
                    let index = self.doc.document.index(for: page)
                    if index != NSNotFound, index != self.doc.currentPage {
                        self.suppressScroll = true
                        self.doc.currentPage = index
                        self.suppressScroll = false
                    }
                }
            }
        }

        func pickImage(_ completion: @escaping (NSImage?) -> Void) {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.message = app.tool == .signature
                ? "Choose a signature image (a PNG with transparency looks best)"
                : "Choose an image to place"
            completion(panel.runModal() == .OK ? panel.url.flatMap(NSImage.init(contentsOf:)) : nil)
        }

        func editText(_ annotation: PDFAnnotation) {
            guard let view, let page = annotation.page else { return }
            let rectInView = view.convert(annotation.bounds, from: page)
            TextEditorPopover.present(over: view, rect: rectInView,
                                      text: annotation.contents ?? "",
                                      font: annotation.font ?? .systemFont(ofSize: 13),
                                      color: annotation.fontColor ?? .black) { [weak self] newValue in
                guard let self else { return }
                let old = annotation.contents
                self.doc.perform("Edit Text") {
                    annotation.contents = newValue
                    self.doc.registerUndo("Edit Text") { _ in annotation.contents = old }
                }
                view.setNeedsDisplay(view.bounds)
            }
        }
    }
}
