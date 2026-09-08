import SwiftUI
import PDFKit

// MARK: - thumbnail rendering

@MainActor
final class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()
    private var store: [String: NSImage] = [:]
    private let queue = DispatchQueue(label: "riftpdf.thumbnails", qos: .userInitiated)

    func key(_ page: PDFPage, _ width: CGFloat) -> String {
        "\(ObjectIdentifier(page).hashValue)-\(page.rotation)-\(Int(width))"
    }

    func cached(_ page: PDFPage, width: CGFloat) -> NSImage? { store[key(page, width)] }

    func render(_ page: PDFPage, width: CGFloat) async -> NSImage {
        let cacheKey = key(page, width)
        if let hit = store[cacheKey] { return hit }
        let image: NSImage = await withCheckedContinuation { continuation in
            queue.async {
                let bounds = page.bounds(for: .mediaBox)
                let ratio = bounds.height / max(1, bounds.width)
                let size = CGSize(width: width, height: width * ratio)
                let thumb = page.thumbnail(of: size, for: .mediaBox)
                continuation.resume(returning: thumb)
            }
        }
        store[cacheKey] = image
        if store.count > 600 { store.removeAll() }
        return image
    }

    func invalidate() { store.removeAll() }
}

struct PageThumbnail: View {
    let page: PDFPage
    var width: CGFloat = 150
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.06))
                    .aspectRatio(0.77, contentMode: .fit)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .task(id: "\(ObjectIdentifier(page).hashValue)-\(page.rotation)") {
            image = await ThumbnailCache.shared.render(page, width: width)
        }
    }
}

// MARK: - sidebar

struct SidebarView: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $app.sidebarMode) {
                ForEach(AppModel.SidebarMode.allCases, id: \.self) { mode in
                    Image(systemName: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            Divider()

            switch app.sidebarMode {
            case .thumbnails: PageList(doc: doc)
            case .outline: OutlineList(doc: doc)
            case .annotations: AnnotationList(doc: doc)
            case .search: SearchPanel(doc: doc)
            }
        }
        .background(.background.opacity(0.4))
    }
}

// MARK: - pages

struct PageList: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $app.selectedPages) {
                ForEach(0..<doc.pageCount, id: \.self) { index in
                    if let page = doc.document.page(at: index) {
                        HStack(spacing: 9) {
                            PageThumbnail(page: page, width: 110)
                                .frame(width: 62)
                                .background(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .strokeBorder(index == doc.currentPage
                                                      ? Color.accentColor : Color.primary.opacity(0.15),
                                                      lineWidth: index == doc.currentPage ? 2 : 0.5)
                                )
                                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(index + 1)")
                                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                                if page.annotations.count > 0 {
                                    Label("\(page.annotations.count)", systemImage: "bubble.left")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 3)
                        .tag(index)
                        .contentShape(Rectangle())
                        .onTapGesture { doc.currentPage = index }
                    }
                }
                .onMove { source, destination in
                    doc.movePages(Array(source), to: destination)
                    ThumbnailCache.shared.invalidate()
                }
            }
            .listStyle(.sidebar)
            .contextMenu(forSelectionType: Int.self) { selection in
                pageMenu(for: selection.isEmpty ? [doc.currentPage] : Array(selection))
            }
            .id(doc.structureVersion)

            Divider()
            HStack(spacing: 3) {
                sidebarButton("plus", "Insert blank page after current") {
                    doc.insertBlankPage(at: doc.currentPage + 1)
                    ThumbnailCache.shared.invalidate()
                }
                sidebarButton("doc.badge.plus", "Insert pages from another PDF") { insertFromFile() }
                sidebarButton("rotate.left", "Rotate left") { rotate(-90) }
                sidebarButton("rotate.right", "Rotate right") { rotate(90) }
                sidebarButton("square.on.square", "Duplicate") {
                    doc.duplicatePages(targets)
                    ThumbnailCache.shared.invalidate()
                }
                sidebarButton("trash", "Delete", destructive: true) {
                    doc.deletePages(targets)
                    app.selectedPages.removeAll()
                    ThumbnailCache.shared.invalidate()
                }
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
    }

    private var targets: [Int] {
        app.selectedPages.isEmpty ? [doc.currentPage] : Array(app.selectedPages)
    }

    @ViewBuilder
    private func pageMenu(for pages: [Int]) -> some View {
        Button("Rotate Right") { doc.rotatePages(pages, by: 90); ThumbnailCache.shared.invalidate() }
        Button("Rotate Left") { doc.rotatePages(pages, by: -90); ThumbnailCache.shared.invalidate() }
        Divider()
        Button("Duplicate") { doc.duplicatePages(pages); ThumbnailCache.shared.invalidate() }
        Button("Extract to New Document…") { extract(pages) }
        Button("Insert Blank Page After") {
            doc.insertBlankPage(at: (pages.max() ?? 0) + 1); ThumbnailCache.shared.invalidate()
        }
        Divider()
        Button("Delete", role: .destructive) {
            doc.deletePages(pages); app.selectedPages.removeAll(); ThumbnailCache.shared.invalidate()
        }
    }

    private func rotate(_ degrees: Int) {
        doc.rotatePages(targets, by: degrees)
        ThumbnailCache.shared.invalidate()
    }

    private func extract(_ pages: [Int]) {
        let extracted = doc.extract(pages)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(doc.displayName) extract.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if extracted.write(to: url) {
            app.success("Extracted \(pages.count) page\(pages.count == 1 ? "" : "s")", reveal: url)
            app.open(url: url)
        } else {
            app.fail("Could not write the extracted pages")
        }
    }

    private func insertFromFile() {
        app.chooseFiles(types: [.pdf], multiple: false, message: "Choose a PDF to insert") { urls in
            guard let url = urls.first, let source = PDFDocument(url: url) else { return }
            doc.insertPages(from: source, at: doc.currentPage + 1)
            ThumbnailCache.shared.invalidate()
            app.success("Inserted \(source.pageCount) page\(source.pageCount == 1 ? "" : "s")")
        }
    }

    private func sidebarButton(_ symbol: String, _ help: String, destructive: Bool = false,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .frame(width: 26, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(destructive ? Color.red.opacity(0.85) : Color.primary.opacity(0.75))
        .help(help)
    }
}

// MARK: - outline

struct OutlineList: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel

    private struct Entry: Identifiable {
        let id = UUID()
        let label: String
        let depth: Int
        let destination: Int
    }

    private var entries: [Entry] {
        guard let root = doc.document.outlineRoot else { return [] }
        var out: [Entry] = []
        var stack: [(PDFOutline, Int)] = []
        for i in stride(from: root.numberOfChildren - 1, through: 0, by: -1) {
            if let child = root.child(at: i) { stack.append((child, 0)) }
        }
        while let (node, depth) = stack.popLast() {
            let page = node.destination?.page.flatMap { doc.document.index(for: $0) } ?? 0
            out.append(Entry(label: node.label ?? "Untitled", depth: depth, destination: page))
            for i in stride(from: node.numberOfChildren - 1, through: 0, by: -1) {
                if let child = node.child(at: i) { stack.append((child, depth + 1)) }
            }
        }
        return out
    }

    var body: some View {
        if entries.isEmpty {
            EmptyPane(icon: "list.bullet.indent", title: "No table of contents",
                      message: "This PDF has no bookmarks. You can add them from Tools ▸ Bookmarks.")
        } else {
            List {
                ForEach(entries) { entry in
                    HStack {
                        Text(entry.label)
                            .font(.system(size: 11.5))
                            .lineLimit(2)
                        Spacer()
                        Text("\(entry.destination + 1)")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.leading, CGFloat(entry.depth) * 12)
                    .contentShape(Rectangle())
                    .onTapGesture { doc.currentPage = entry.destination }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

// MARK: - annotations

struct AnnotationList: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel

    private struct Item: Identifiable {
        let id = UUID()
        let page: Int
        let annotation: PDFAnnotation
    }

    private var items: [Item] {
        (0..<doc.document.pageCount).flatMap { index -> [Item] in
            guard let page = doc.document.page(at: index) else { return [] }
            return page.annotations.map { Item(page: index, annotation: $0) }
        }
    }

    var body: some View {
        let all = items
        if all.isEmpty {
            EmptyPane(icon: "bubble.left.and.text.bubble.right", title: "No markup yet",
                      message: "Highlights, notes, drawings and shapes you add will be listed here.")
        } else {
            List {
                ForEach(all) { item in
                    HStack(spacing: 8) {
                        Image(systemName: symbol(for: item.annotation))
                            .font(.system(size: 11))
                            .foregroundStyle(Color(item.annotation.color))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(label(for: item.annotation))
                                .font(.system(size: 11.5))
                                .lineLimit(2)
                            Text("Page \(item.page + 1)")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        doc.currentPage = item.page
                        app.selectedAnnotation = item.annotation
                        app.showInspector = true
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            doc.removeAnnotation(item.annotation)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .id(doc.structureVersion)
        }
    }

    private func symbol(for a: PDFAnnotation) -> String {
        switch a.type ?? "" {
        case "Highlight": "highlighter"
        case "Underline": "underline"
        case "StrikeOut": "strikethrough"
        case "Ink": "pencil.tip"
        case "Square": a.userName == "riftpdf.redaction" ? "rectangle.fill.badge.xmark" : "rectangle"
        case "Circle": "circle"
        case "Line": "line.diagonal"
        case "FreeText": "textbox"
        case "Text": "note.text"
        case "Stamp": "photo"
        default: "scribble"
        }
    }

    private func label(for a: PDFAnnotation) -> String {
        if let contents = a.contents, !contents.isEmpty { return contents }
        if a.userName == "riftpdf.redaction" { return "Marked for redaction" }
        return a.type ?? "Markup"
    }
}

// MARK: - search

struct SearchPanel: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Find in document", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { doc.runSearch(query) }
                if !query.isEmpty {
                    Button { query = ""; doc.searchMatches = [] } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(8)
            .onChange(of: query) { _, new in doc.runSearch(new) }

            Divider()

            if doc.searchMatches.isEmpty {
                EmptyPane(icon: "magnifyingglass",
                          title: query.count > 1 ? "No matches" : "Search this document",
                          message: query.count > 1
                            ? "Nothing matched “\(query)”. If this is a scan, run Tools ▸ Recognise Text first."
                            : "Type to find text across every page.")
            } else {
                List {
                    Section("\(doc.searchMatches.count) matches") {
                        ForEach(Array(doc.searchMatches.enumerated()), id: \.offset) { index, match in
                            let pageIndex = match.pages.first.map { doc.document.index(for: $0) } ?? 0
                            VStack(alignment: .leading, spacing: 2) {
                                Text(context(for: match))
                                    .font(.system(size: 11))
                                    .lineLimit(3)
                                Text("Page \(pageIndex + 1)")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                doc.currentPage = pageIndex
                                if let view = PDFViewLocator.find() {
                                    view.setCurrentSelection(match, animate: true)
                                    view.scrollSelectionToVisible(nil)
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private func context(for match: PDFSelection) -> String {
        guard let page = match.pages.first else { return match.string ?? "" }
        let extended = match.copy() as? PDFSelection ?? match
        extended.extend(atStart: 28)
        extended.extend(atEnd: 42)
        _ = page
        return (extended.string ?? match.string ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - shared empty state

struct EmptyPane: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
