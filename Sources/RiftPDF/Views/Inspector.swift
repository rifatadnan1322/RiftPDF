import SwiftUI
import PDFKit

struct InspectorView: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(heading).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { withAnimation { app.showInspector = false } } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if app.tool == .editText {
                        TextEditPanel(doc: doc)
                    } else if let annotation = app.selectedAnnotation {
                        AnnotationInspector(doc: doc, annotation: annotation)
                    } else if app.tool == .redact {
                        RedactionPanel(doc: doc)
                    } else {
                        DocumentSummary(doc: doc)
                    }
                }
                .padding(12)
            }
        }
        .background(.background.opacity(0.4))
    }

    private var heading: String {
        if app.tool == .editText { return "Edit Page Text" }
        if app.selectedAnnotation != nil { return "Markup" }
        if app.tool == .redact { return "Redaction" }
        return "Document"
    }
}

// MARK: - annotation properties

struct AnnotationInspector: View {
    @ObservedObject var doc: PDFDoc
    let annotation: PDFAnnotation
    @EnvironmentObject var app: AppModel
    @State private var contents: String = ""
    @State private var opacity: Double = 1
    @State private var lineWidth: Double = 2
    @State private var lockAspect = true
    @State private var geometryVersion = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(annotation.type ?? "Markup")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if ["FreeText", "Text", "Highlight", "Square", "Circle"].contains(annotation.type ?? "") {
                Field("Note") {
                    TextEditor(text: $contents)
                        .font(.system(size: 12))
                        .frame(height: 74)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                        .onChange(of: contents) { _, new in
                            annotation.contents = new
                            doc.afterExternalMutation()
                        }
                }
            }

            if !(annotation is ImageStampAnnotation) {
                Field("Colour") {
                    ColorPicker("", selection: Binding(
                        get: { Color(annotation.color) },
                        set: { annotation.color = $0.nsColor; doc.afterExternalMutation(); refresh() }
                    ))
                    .labelsHidden()
                }
            }

            if annotation.type == "Square" || annotation.type == "Circle" || annotation.type == "Ink" || annotation.type == "Line" {
                Field("Thickness") {
                    Slider(value: $lineWidth, in: 0.5...16) { _ in
                        let border = PDFBorder()
                        border.lineWidth = lineWidth
                        annotation.border = border
                        doc.afterExternalMutation()
                        refresh()
                    }
                }
            }

            if annotation.type == "FreeText" {
                Field("Text size") {
                    Stepper(value: Binding(
                        get: { Double(annotation.font?.pointSize ?? 13) },
                        set: {
                            annotation.font = NSFont(name: annotation.font?.fontName ?? "Helvetica", size: $0)
                                ?? .systemFont(ofSize: $0)
                            doc.afterExternalMutation(); refresh()
                        }
                    ), in: 6...96, step: 1) {
                        Text("\(Int(annotation.font?.pointSize ?? 13)) pt").font(.system(size: 11))
                    }
                }
                Button("Edit Text…") {
                    if let view = PDFViewLocator.find() {
                        view.onEditText?(annotation)
                    }
                }
                .controlSize(.small)
            }

            if MarkupPDFView.isResizable(annotation) {
                Field("Size and position") {
                    VStack(spacing: 5) {
                        HStack(spacing: 6) {
                            numberBox("W", width) { setSize(width: $0, height: height) }
                            numberBox("H", height) { setSize(width: width, height: $0) }
                            Toggle("", isOn: $lockAspect)
                                .toggleStyle(.button)
                                .help(lockAspect ? "Proportions locked" : "Proportions free")
                                .accessibilityLabel("Lock proportions")
                        }
                        HStack(spacing: 6) {
                            numberBox("X", originX) { setOrigin(x: $0, y: originY) }
                            numberBox("Y", originY) { setOrigin(x: originX, y: $0) }
                            Spacer().frame(width: 30)
                        }
                    }
                }
                Text("Drag the grips on the page, or nudge with the arrow keys (⇧ arrows resize).")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let b = annotation.bounds
                Text(String(format: "%.0f × %.0f pt at (%.0f, %.0f)", b.width, b.height, b.minX, b.minY))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Button(role: .destructive) {
                    doc.removeAnnotation(annotation)
                    app.selectedAnnotation = nil
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .controlSize(.small)
                Spacer()
            }
        }
        .onAppear {
            contents = annotation.contents ?? ""
            lineWidth = Double(annotation.border?.lineWidth ?? 2)
        }
        .id(ObjectIdentifier(annotation))
    }

    private func refresh() {
        guard let view = PDFViewLocator.find() else { return }
        view.setNeedsDisplay(view.bounds)
        view.refreshSelection()
    }

    // MARK: numeric geometry

    private var visual: CGRect { MarkupPDFView.visualBounds(annotation) }
    private var width: Double { Double(visual.width) }
    private var height: Double { Double(visual.height) }
    private var originX: Double { Double(visual.minX) }
    private var originY: Double { Double(visual.minY) }

    private func numberBox(_ label: String, _ value: Double,
                           _ commit: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 11)
            TextField("", value: Binding(get: { (value * 10).rounded() / 10 },
                                         set: { commit($0) }),
                      format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11).monospacedDigit())
                .frame(width: 58)
                .accessibilityLabel("\(label) in points")
        }
        .id(geometryVersion)
    }

    private func setSize(width newWidth: Double, height newHeight: Double) {
        let current = visual
        var w = max(14, newWidth), h = max(14, newHeight)
        if lockAspect, current.width > 0, current.height > 0 {
            let ratio = current.height / current.width
            if abs(newWidth - Double(current.width)) > 0.01 {
                h = w * Double(ratio)
            } else {
                w = h / Double(ratio)
            }
        }
        applyRect(CGRect(x: current.minX, y: current.minY, width: w, height: h))
    }

    private func setOrigin(x: Double, y: Double) {
        let current = visual
        applyRect(CGRect(x: x, y: y, width: current.width, height: current.height))
    }

    private func applyRect(_ rect: CGRect) {
        guard let view = PDFViewLocator.find() else { return }
        view.setGeometry(rect, of: annotation)
        doc.afterExternalMutation()
        geometryVersion &+= 1
        refresh()
    }
}

// MARK: - editing real page text

struct TextEditPanel: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel
    @StateObject private var model = TextEditModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Page \(doc.currentPage + 1)")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button {
                    model.load(doc: doc, page: doc.currentPage, app: app)
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Reload text from this page")
            }

            if model.loading {
                HStack { ProgressView().controlSize(.small); Text("Reading page…").font(.system(size: 11)) }
            } else if model.lines.isEmpty {
                Text("No editable text found on this page. If it's a scan, run Tools ▸ Recognise Text first — that adds a real text layer.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("Edit any line and apply. RiftPDF erases the original glyphs and re-lays the text with matching size and colour.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                ForEach($model.lines) { $line in
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("", text: $line.text, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .padding(6)
                            .background(line.isChanged ? Color.accentColor.opacity(0.12)
                                        : Color.primary.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(line.isChanged ? Color.accentColor.opacity(0.6) : .clear)
                            )
                        Text("\(line.font) · \(String(format: "%.1f", line.size)) pt")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack {
                    Button("Apply \(model.changedCount) change\(model.changedCount == 1 ? "" : "s")") {
                        model.apply(doc: doc, app: app)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.changedCount == 0)

                    Button("Revert") { model.revert() }
                        .controlSize(.small)
                        .disabled(model.changedCount == 0)
                }
            }
        }
        .onAppear { model.load(doc: doc, page: doc.currentPage, app: app) }
        .onChange(of: doc.currentPage) { _, page in model.load(doc: doc, page: page, app: app) }
    }
}

@MainActor
final class TextEditModel: ObservableObject {

    struct Line: Identifiable {
        let id = UUID()
        var text: String
        let original: String
        let bbox: [Double]
        let font: String
        let size: Double
        let color: [Double]
        let bold: Bool
        let italic: Bool
        var isChanged: Bool { text != original }
    }

    @Published var lines: [Line] = []
    @Published var loading = false
    private var loadedPage: Int?

    var changedCount: Int { lines.filter(\.isChanged).count }

    func load(doc: PDFDoc, page: Int, app: AppModel) {
        guard !loading else { return }
        loading = true
        lines = []
        loadedPage = page
        Task {
            defer { loading = false }
            do {
                let input = try doc.stageToTemporaryFile()
                var payload: [String: Any] = ["input": input.path, "page": page]
                if let pw = doc.password { payload["password"] = pw }
                let res = try await Engine.shared.run("text_spans", payload)
                try? FileManager.default.removeItem(at: input)

                var collected: [Line] = []
                for block in (res["blocks"] as? [[String: Any]] ?? []) {
                    for line in (block["lines"] as? [[String: Any]] ?? []) {
                        let spans = line["spans"] as? [[String: Any]] ?? []
                        guard let first = spans.first else { continue }
                        let text = spans.compactMap { $0["text"] as? String }.joined()
                        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                        collected.append(Line(
                            text: text,
                            original: text,
                            bbox: line["bbox"] as? [Double] ?? [],
                            font: (first["font"] as? String ?? "Helvetica"),
                            size: first["size"] as? Double ?? 11,
                            color: first["color"] as? [Double] ?? [0, 0, 0],
                            bold: first["bold"] as? Bool ?? false,
                            italic: first["italic"] as? Bool ?? false))
                    }
                }
                lines = collected
            } catch {
                app.report(error, context: "Could not read the page text")
            }
        }
    }

    func revert() {
        lines = lines.map { line in
            var copy = line
            copy.text = line.original
            return copy
        }
    }

    func apply(doc: PDFDoc, app: AppModel) {
        let page = loadedPage ?? doc.currentPage
        let edits = lines.filter(\.isChanged).map { line -> [String: Any] in
            ["page": page, "bbox": line.bbox, "text": line.text, "font": line.font,
             "size": line.size, "color": line.color, "bold": line.bold,
             "italic": line.italic, "align": "left"]
        }
        guard !edits.isEmpty else { return }
        app.transform(doc, title: "Rewriting text", command: "text_edit",
                      actionName: "Edit Text", extraPayload: ["edits": edits]) { [weak self] res in
            ThumbnailCache.shared.invalidate()
            let n = res["edits"] as? Int ?? 0
            Task { @MainActor in self?.load(doc: doc, page: page, app: app) }
            return ("Text updated", "\(n) line\(n == 1 ? "" : "s") rewritten")
        }
    }
}

// MARK: - redaction panel

struct RedactionPanel: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel
    @State private var terms = ""

    private var count: Int { app.pendingRedactions.values.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Drag over anything that must go. Applying removes the underlying text and image data — not just covers it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack {
                Text("\(count) area\(count == 1 ? "" : "s") marked")
                    .font(.system(size: 11.5, weight: .medium))
                Spacer()
                Button("Clear") {
                    app.pendingRedactions.removeAll()
                    for i in 0..<doc.document.pageCount {
                        guard let page = doc.document.page(at: i) else { continue }
                        for a in page.annotations where a.userName == "riftpdf.redaction" {
                            page.removeAnnotation(a)
                        }
                    }
                    doc.afterExternalMutation()
                }
                .controlSize(.small)
                .disabled(count == 0)
            }

            Button {
                app.applyRedactions(doc)
            } label: {
                Label("Apply Redactions", systemImage: "rectangle.fill.badge.xmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
            .disabled(count == 0)

            Divider()

            Field("Redact every occurrence of") {
                TextField("comma separated terms", text: $terms)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
            }
            Button("Find and Redact") {
                let list = terms.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                guard !list.isEmpty else { return }
                app.redactSearch(doc, terms: list)
            }
            .controlSize(.small)
            .disabled(terms.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

// MARK: - document summary

struct DocumentSummary: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let url = doc.url {
                row("File", url.lastPathComponent)
                row("Where", url.deletingLastPathComponent().path)
            }
            row("Pages", "\(doc.pageCount)")
            if let page = doc.document.page(at: doc.currentPage) {
                let b = page.bounds(for: .mediaBox)
                row("Page size", String(format: "%.0f × %.0f pt (%.1f × %.1f in)",
                                        b.width, b.height, b.width / 72, b.height / 72))
            }
            let attrs = doc.document.documentAttributes ?? [:]
            if let title = attrs[PDFDocumentAttribute.titleAttribute] as? String, !title.isEmpty {
                row("Title", title)
            }
            if let author = attrs[PDFDocumentAttribute.authorAttribute] as? String, !author.isEmpty {
                row("Author", author)
            }
            if let producer = attrs[PDFDocumentAttribute.producerAttribute] as? String, !producer.isEmpty {
                row("Producer", producer)
            }
            row("Locked", doc.document.isEncrypted ? "Yes" : "No")

            Divider()

            Text("Quick actions").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            quick("Shrink file size", "arrow.down.circle") { app.sheet = .compress }
            quick("Remove metadata", "eye.slash") { app.sheet = .metadata }
            quick("Export to Word", "doc.text") { app.exportWord(doc) }
            quick("Recognise text (OCR)", "text.viewfinder") { app.sheet = .ocr }
            quick("Document properties", "info.circle") { app.sheet = .documentInfo }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9.5)).foregroundStyle(.tertiary).textCase(.uppercase)
            Text(value).font(.system(size: 11.5)).textSelection(.enabled).lineLimit(3)
        }
    }

    private func quick(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 11)).frame(width: 15)
                Text(title).font(.system(size: 11.5))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - shared field wrapper

struct Field<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            content
        }
    }
}
