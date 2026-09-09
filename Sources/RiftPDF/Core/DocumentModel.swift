import SwiftUI
import PDFKit
import Combine

/// One open PDF. Owns the PDFKit document, undo history and dirty state.
@MainActor
final class PDFDoc: ObservableObject, Identifiable {

    let id = UUID()
    @Published private(set) var document: PDFDocument
    @Published var url: URL?
    @Published var isDirty = false
    @Published var currentPage: Int = 0
    @Published var pageCount: Int
    @Published var searchMatches: [PDFSelection] = []
    @Published var searchIndex: Int = 0
    /// Bumped whenever pages are added, removed or reordered so views refresh.
    @Published var structureVersion: Int = 0

    let undoManager = UndoManager()
    var password: String?

    /// A file on disk whose bytes are exactly this document's current content.
    ///
    /// PDFKit's writer is lossy about file *size*: it duplicates image objects
    /// that were shared between pages and stores streams far less compressed.
    /// On a scanned page that inflates the file by over 150%, which silently
    /// undoes everything the engine just did. So whenever the bytes on disk are
    /// authoritative, we copy them rather than asking PDFKit to write them out.
    /// Any in-memory edit clears this, because then PDFKit holds changes the
    /// file does not.
    private(set) var backingFileURL: URL?

    /// The engine's most recent output for this document. Unlike
    /// `backingFileURL` this survives editing, because after PDFKit rewrites
    /// the file we can still transplant the markup back onto these
    /// well-compressed bytes.
    private(set) var optimisedSourceURL: URL?

    private static let backingDirectory: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("riftpdf-backing", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    var displayName: String { url?.displayName ?? "Untitled" }

    init(document: PDFDocument, url: URL?) {
        self.document = document
        self.url = url
        self.backingFileURL = url          // freshly opened: the file is the truth
        self.pageCount = document.pageCount
        undoManager.levelsOfUndo = 40
        undoManager.groupsByEvent = false
    }

    convenience init?(url: URL, password: String? = nil) {
        guard let doc = PDFDocument(url: url) else { return nil }
        if doc.isLocked, let password { _ = doc.unlock(withPassword: password) }
        self.init(document: doc, url: url)
        self.password = password
    }

    // MARK: - mutation plumbing

    private func touch() {
        isDirty = true
        invalidateBackingFile()
        pageCount = document.pageCount
        structureVersion &+= 1
    }

    /// The file on disk now matches what is in memory (used after the saved
    /// file has been re-optimised behind the scenes).
    func noteSavedBytes(at file: URL) {
        backingFileURL = file
        isDirty = false
    }

    /// Called whenever the in-memory document diverges from any file.
    func invalidateBackingFile() {
        backingFileURL = nil
    }

    /// Takes ownership of a file the engine produced, so its exact bytes are
    /// what gets written on save.
    func adoptBackingFile(_ file: URL) {
        let destination = Self.backingDirectory
            .appendingPathComponent("\(id.uuidString)-\(UUID().uuidString).pdf")
        do {
            try FileManager.default.moveItem(at: file, to: destination)
            backingFileURL = destination
            optimisedSourceURL = destination
        } catch {
            backingFileURL = nil      // fall back to PDFKit rather than lie
        }
    }

    func registerUndo(_ name: String, _ action: @escaping @MainActor (PDFDoc) -> Void) {
        undoManager.setActionName(name)
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { action(target) }
        }
    }

    /// Groups a set of edits so one ⌘Z reverses the whole thing.
    func perform(_ name: String, _ body: () -> Void) {
        undoManager.beginUndoGrouping()
        undoManager.setActionName(name)
        body()
        undoManager.endUndoGrouping()
        touch()
    }

    // MARK: - page operations

    func deletePages(_ indices: [Int]) {
        let sorted = indices.sorted(by: >)
        let saved: [(Int, PDFPage)] = sorted.compactMap { idx in
            document.page(at: idx).map { (idx, $0) }
        }
        guard !saved.isEmpty else { return }
        perform(saved.count == 1 ? "Delete Page" : "Delete \(saved.count) Pages") {
            for (idx, _) in saved { document.removePage(at: idx) }
            registerUndo("Delete Pages") { target in
                for (idx, page) in saved.reversed() {
                    target.document.insert(page, at: min(idx, target.document.pageCount))
                }
                target.afterExternalMutation()
            }
        }
        currentPage = min(currentPage, max(0, document.pageCount - 1))
    }

    func rotatePages(_ indices: [Int], by degrees: Int) {
        guard !indices.isEmpty else { return }
        perform(degrees > 0 ? "Rotate Right" : "Rotate Left") {
            for i in indices { document.page(at: i)?.rotation += degrees }
            registerUndo("Rotate") { target in
                target.rotatePages(indices, by: -degrees)
            }
        }
    }

    func movePages(_ indices: [Int], to destination: Int) {
        let ordered = indices.sorted()
        guard !ordered.isEmpty else { return }
        let pages = ordered.compactMap { document.page(at: $0) }
        let before = (0..<document.pageCount).compactMap { document.page(at: $0) }

        perform("Move Pages") {
            for i in ordered.reversed() { document.removePage(at: i) }
            let shift = ordered.filter { $0 < destination }.count
            var insertAt = min(max(0, destination - shift), document.pageCount)
            for page in pages {
                document.insert(page, at: insertAt)
                insertAt += 1
            }
            registerUndo("Move Pages") { target in
                target.replaceOrder(with: before)
            }
        }
    }

    private func replaceOrder(with pages: [PDFPage]) {
        while document.pageCount > 0 { document.removePage(at: 0) }
        for (i, p) in pages.enumerated() { document.insert(p, at: i) }
        afterExternalMutation()
    }

    func insertBlankPage(at index: Int) {
        let template = document.page(at: max(0, min(index - 1, document.pageCount - 1)))
        let bounds = template?.bounds(for: .mediaBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        let blank = BlankPage(size: bounds.size)
        perform("Insert Blank Page") {
            document.insert(blank, at: min(index, document.pageCount))
            registerUndo("Insert Blank Page") { target in
                if let idx = target.document.index(for: blank) as Int?, idx >= 0 {
                    target.document.removePage(at: idx)
                    target.afterExternalMutation()
                }
            }
        }
    }

    func insertPages(from other: PDFDocument, at index: Int) {
        let inserted = (0..<other.pageCount).compactMap { other.page(at: $0)?.copy() as? PDFPage }
        guard !inserted.isEmpty else { return }
        perform("Insert Pages") {
            for (offset, page) in inserted.enumerated() {
                document.insert(page, at: min(index + offset, document.pageCount))
            }
            registerUndo("Insert Pages") { target in
                for page in inserted.reversed() {
                    let idx = target.document.index(for: page)
                    if idx != NSNotFound && idx >= 0 { target.document.removePage(at: idx) }
                }
                target.afterExternalMutation()
            }
        }
    }

    func duplicatePages(_ indices: [Int]) {
        let copies = indices.sorted().compactMap { document.page(at: $0)?.copy() as? PDFPage }
        guard let last = indices.max() else { return }
        perform("Duplicate Pages") {
            for (offset, page) in copies.enumerated() {
                document.insert(page, at: min(last + 1 + offset, document.pageCount))
            }
            registerUndo("Duplicate Pages") { target in
                for page in copies.reversed() {
                    let idx = target.document.index(for: page)
                    if idx != NSNotFound && idx >= 0 { target.document.removePage(at: idx) }
                }
                target.afterExternalMutation()
            }
        }
    }

    func extract(_ indices: [Int]) -> PDFDocument {
        let out = PDFDocument()
        for (n, i) in indices.sorted().enumerated() {
            if let page = document.page(at: i)?.copy() as? PDFPage { out.insert(page, at: n) }
        }
        return out
    }

    // MARK: - annotations

    func addAnnotation(_ annotation: PDFAnnotation, to page: PDFPage, name: String) {
        perform(name) {
            page.addAnnotation(annotation)
            registerUndo(name) { target in
                page.removeAnnotation(annotation)
                target.isDirty = true
                target.structureVersion &+= 1
            }
        }
    }

    func removeAnnotation(_ annotation: PDFAnnotation) {
        guard let page = annotation.page else { return }
        perform("Delete Markup") {
            page.removeAnnotation(annotation)
            registerUndo("Delete Markup") { target in
                page.addAnnotation(annotation)
                target.isDirty = true
                target.structureVersion &+= 1
            }
        }
    }

    // MARK: - whole document replacement (engine round trips)

    /// Swap in a document the engine produced, keeping undo intact.
    func replaceDocument(with new: PDFDocument, actionName: String,
                         backingFile: URL? = nil) {
        let snapshot = document.dataRepresentation()
        let previousBacking = backingFileURL
        perform(actionName) {
            document = new
            registerUndo(actionName) { target in
                if let snapshot, let restored = PDFDocument(data: snapshot) {
                    target.document = restored
                    target.afterExternalMutation()
                    target.backingFileURL = previousBacking
                }
            }
        }
        // set after the undo registration, which clears it via afterExternalMutation
        if let backingFile {
            adoptBackingFile(backingFile)
        } else {
            invalidateBackingFile()
        }
        isDirty = true
        pageCount = new.pageCount
        structureVersion &+= 1
        currentPage = min(currentPage, max(0, new.pageCount - 1))
    }

    func afterExternalMutation() {
        isDirty = true
        invalidateBackingFile()
        pageCount = document.pageCount
        structureVersion &+= 1
    }

    // MARK: - saving

    /// Writes the live document (annotations included) to disk.
    func save(to target: URL? = nil) throws -> URL {
        guard let destination = target ?? url else {
            throw NSError(domain: "RiftPDF", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No destination for this document."])
        }
        if let backing = backingFileURL,
           FileManager.default.fileExists(atPath: backing.path),
           backing.standardizedFileURL != destination.standardizedFileURL {
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: backing, to: destination)
            } catch {
                throw NSError(domain: "RiftPDF", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Could not write to \(destination.lastPathComponent): \(error.localizedDescription)"])
            }
        } else if backingFileURL?.standardizedFileURL != destination.standardizedFileURL {
            guard document.write(to: destination) else {
                throw NSError(domain: "RiftPDF", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Could not write to \(destination.lastPathComponent). Check folder permissions."])
            }
        }
        url = destination
        backingFileURL = destination
        isDirty = false
        return destination
    }

    /// Snapshot to a temp file so the engine can work on the *current* state,
    /// annotations and all, rather than whatever is on disk.
    func stageToTemporaryFile() throws -> URL {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("riftpdf-stage-\(UUID().uuidString).pdf")
        // Prefer the real file: handing the engine a PDFKit rewrite would make
        // it compress an already-inflated copy.
        if let backing = backingFileURL,
           FileManager.default.fileExists(atPath: backing.path),
           (try? FileManager.default.copyItem(at: backing, to: temp)) != nil {
            return temp
        }
        guard document.write(to: temp) else {
            throw NSError(domain: "RiftPDF", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Could not prepare the document for processing."])
        }
        return temp
    }

    // MARK: - search

    func runSearch(_ text: String) {
        guard text.count > 1 else { searchMatches = []; searchIndex = 0; return }
        searchMatches = document.findString(text, withOptions: [.caseInsensitive, .diacriticInsensitive])
        searchIndex = 0
    }
}

/// A genuinely blank page — PDFKit has no public constructor for one.
final class BlankPage: PDFPage {
    private let pageSize: CGSize
    init(size: CGSize) {
        self.pageSize = size
        super.init()
    }
    override func bounds(for box: PDFDisplayBox) -> CGRect {
        CGRect(origin: .zero, size: pageSize)
    }
    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        context.saveGState()
        context.setFillColor(NSColor.white.cgColor)
        context.fill(bounds(for: box))
        context.restoreGState()
        super.draw(with: box, to: context)
    }
}
