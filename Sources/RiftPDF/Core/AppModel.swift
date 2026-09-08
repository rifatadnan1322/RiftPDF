import SwiftUI
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {

    // MARK: - open documents

    @Published var docs: [PDFDoc] = []
    @Published var selectedDocID: UUID?

    var current: PDFDoc? {
        docs.first { $0.id == selectedDocID } ?? docs.first
    }

    // MARK: - editing state

    @Published var tool: Tool = .select
    @Published var style = MarkupStyle()
    @Published var selectedAnnotation: PDFAnnotation?
    @Published var selectedPages: Set<Int> = []
    @Published var pendingRedactions: [Int: [CGRect]] = [:]

    // MARK: - chrome

    @Published var showSidebar = true
    @Published var showInspector = false
    @Published var sidebarMode: SidebarMode = .thumbnails
    @Published var searchText = ""
    @Published var sheet: SheetRoute?
    @Published var tasks: [TaskProgress] = []
    @Published var toast: Toast?
    @Published var zoomLabel = "Fit"
    @Published var recentFiles: [URL] = []

    // accessibility
    @Published var displayMode: DisplayMode = .normal
    @Published var showReadingView = false
    @Published var readingBlocks: [ReadingBlock] = []
    @Published var readingLoading = false
    @Published var readingFontScale: Double = 1.0
    let speech = ReadAloudService()

    struct ReadingBlock: Identifiable, Hashable {
        let id = UUID()
        let page: Int
        let text: String
        let heading: Bool
    }

    enum SidebarMode: String, CaseIterable {
        case thumbnails = "Pages", outline = "Contents", annotations = "Markup", search = "Search"
        var icon: String {
            switch self {
            case .thumbnails: "sidebar.squares.left"
            case .outline: "list.bullet.indent"
            case .annotations: "bubble.left.and.text.bubble.right"
            case .search: "magnifyingglass"
            }
        }
    }

    // MARK: - lifecycle

    init() { loadRecents() }

    func bootstrap() {
        Task { await Engine.shared.probe() }
    }

    // MARK: - toasts & tasks

    func notify(_ toast: Toast) {
        self.toast = toast
        let id = toast.id
        Task {
            try? await Task.sleep(for: .seconds(toast.revealURL == nil ? 3.4 : 6.0))
            if self.toast?.id == id { withAnimation(.easeOut(duration: 0.25)) { self.toast = nil } }
        }
    }

    func success(_ title: String, _ detail: String? = nil, reveal: URL? = nil) {
        notify(Toast(kind: .success, title: title, detail: detail,
                     actionTitle: reveal != nil ? "Show in Finder" : nil, revealURL: reveal))
    }

    func warn(_ title: String, _ detail: String? = nil) {
        notify(Toast(kind: .warning, title: title, detail: detail))
    }

    func fail(_ title: String, _ detail: String? = nil) {
        notify(Toast(kind: .failure, title: title, detail: detail))
    }

    func report(_ error: Error, context: String) {
        if let f = error as? Engine.Failure {
            fail(context, [f.message, f.detail].compactMap { $0 }.joined(separator: "\n"))
        } else {
            fail(context, error.localizedDescription)
        }
    }

    /// Runs an async job with a progress row in the toolbar.
    func job<T>(_ title: String,
                _ body: @escaping (TaskProgress) async throws -> T,
                onSuccess: @escaping (T) -> Void) {
        let task = TaskProgress(title: title)
        tasks.append(task)
        Task {
            do {
                let value = try await body(task)
                task.finished = true
                tasks.removeAll { $0.id == task.id }
                onSuccess(value)
            } catch {
                task.finished = true
                tasks.removeAll { $0.id == task.id }
                report(error, context: "\(title) failed")
            }
        }
    }

    // MARK: - documents

    @discardableResult
    func open(url: URL) -> PDFDoc? {
        if let existing = docs.first(where: { $0.url == url }) {
            selectedDocID = existing.id
            return existing
        }
        guard let raw = PDFDocument(url: url) else {
            fail("Could not open \(url.lastPathComponent)",
                 "The file may be damaged. Try Tools ▸ Repair Document.")
            return nil
        }
        if raw.isLocked {
            promptForPassword(url: url, document: raw)
            return nil
        }
        let doc = PDFDoc(document: raw, url: url)
        docs.append(doc)
        selectedDocID = doc.id
        noteRecent(url)
        sheet = nil
        return doc
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.message = "Choose one or more PDFs"
        if panel.runModal() == .OK {
            for url in panel.urls { open(url: url) }
        }
    }

    private func promptForPassword(url: URL, document: PDFDocument) {
        let alert = NSAlert()
        alert.messageText = "\(url.lastPathComponent) is password protected"
        alert.informativeText = "Enter the password to open this document."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if document.unlock(withPassword: field.stringValue) {
            let doc = PDFDoc(document: document, url: url)
            doc.password = field.stringValue
            docs.append(doc)
            selectedDocID = doc.id
            noteRecent(url)
            sheet = nil
        } else {
            fail("Wrong password", "RiftPDF could not unlock \(url.lastPathComponent).")
        }
    }

    func close(_ doc: PDFDoc) {
        if doc.isDirty {
            let alert = NSAlert()
            alert.messageText = "Save changes to \(doc.displayName)?"
            alert.informativeText = "Your edits will be lost if you don't save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn: save(doc)
            case .alertThirdButtonReturn: return
            default: break
            }
        }
        docs.removeAll { $0.id == doc.id }
        if selectedDocID == doc.id { selectedDocID = docs.first?.id }
    }

    func save(_ doc: PDFDoc) {
        guard doc.url != nil else { return saveAs(doc) }
        withPlacedImagesBurnedIn(doc) {
            do {
                let out = try doc.save()
                self.success("Saved", out.lastPathComponent)
            } catch { self.report(error, context: "Save failed") }
        }
    }

    /// Image stamps live as annotations while you position them; they have to
    /// become page content before the file goes to disk.
    private func withPlacedImagesBurnedIn(_ doc: PDFDoc, _ then: @escaping () -> Void) {
        let hasStamps = (0..<doc.document.pageCount).contains { index in
            doc.document.page(at: index)?.annotations.contains { $0 is ImageStampAnnotation } ?? false
        }
        if hasStamps {
            flattenPlacedImages(doc, then: then)
        } else {
            then()
        }
    }

    func saveAs(_ doc: PDFDoc) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (doc.url?.displayName ?? "Untitled") + ".pdf"
        panel.directoryURL = doc.url?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let target = panel.url else { return }
        withPlacedImagesBurnedIn(doc) {
            do {
                let out = try doc.save(to: target)
                self.noteRecent(out)
                self.success("Saved", out.lastPathComponent, reveal: out)
            } catch { self.report(error, context: "Save failed") }
        }
    }

    // MARK: - recents

    private func loadRecents() {
        let saved = UserDefaults.standard.stringArray(forKey: "recentFiles") ?? []
        recentFiles = saved.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func noteRecent(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        recentFiles = Array(recentFiles.prefix(12))
        UserDefaults.standard.set(recentFiles.map(\.path), forKey: "recentFiles")
    }

    func clearRecents() {
        recentFiles = []
        UserDefaults.standard.removeObject(forKey: "recentFiles")
    }
}
