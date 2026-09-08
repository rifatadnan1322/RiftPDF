import SwiftUI
import PDFKit
import UniformTypeIdentifiers

@main
struct RiftPDFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .onAppear {
                    app.bootstrap()
                    delegate.model = app
                    delegate.drainQueue()
                    app.offerToBecomeDefaultReader()
                    // scripted launch: RIFTPDF_OPEN=/path/a.pdf:/path/b.pdf
                    if let list = ProcessInfo.processInfo.environment["RIFTPDF_OPEN"] {
                        for path in list.split(separator: ":").map(String.init) {
                            app.open(url: URL(fileURLWithPath: path))
                        }
                    }
                    if let name = ProcessInfo.processInfo.environment["RIFTPDF_SHEET"] {
                        let routes: [String: SheetRoute] = [
                            "compress": .compress, "metadata": .metadata,
                            "watermark": .watermark, "pageNumbers": .pageNumbers,
                            "security": .security, "ocr": .ocr, "split": .split,
                            "merge": .merge, "imagesToPDF": .imagesToPDF,
                            "documentInfo": .documentInfo, "preferences": .preferences,
                            "accessibility": .accessibility, "headerFooter": .headerFooter,
                            "auditSpace": .auditSpace, "batch": .batch,
                        ]
                        if let route = routes[name] { app.sheet = route }
                    }
                    if ProcessInfo.processInfo.environment["RIFTPDF_READING"] == "1",
                       let doc = app.current {
                        app.loadReadingText(doc, wholeDocument: true)
                        app.showReadingView = true
                    }
                }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { RiftPDFCommands(app: app) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    private var queued: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // One window, one set of tabs. Without this macOS restores every window
        // that was open last time and they all share the same document list.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        closeDuplicateWindows()
        scheduleSnapshotIfRequested()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func closeDuplicateWindows() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let documentWindows = NSApp.windows.filter {
                $0.contentView != nil && $0.canBecomeMain && $0.styleMask.contains(.titled)
            }
            for extra in documentWindows.dropFirst() { extra.close() }
            documentWindows.first?.makeKeyAndOrderFront(nil)
        }
    }

    /// Writes a PNG of RiftPDF's own window when RIFTPDF_SNAPSHOT is set.
    /// An app can always capture its own view hierarchy, so this needs no
    /// screen-recording permission — handy for verifying the UI headlessly.
    private func scheduleSnapshotIfRequested() {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["RIFTPDF_SNAPSHOT"] else { return }
        let delay = Double(env["RIFTPDF_SNAPSHOT_DELAY"] ?? "") ?? 2.5
        let quitAfter = env["RIFTPDF_SNAPSHOT_QUIT"] == "1"

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
                Self.capture(window: window, to: URL(fileURLWithPath: path))
            }
            if quitAfter { NSApp.terminate(nil) }
        }
    }

    static func capture(window: NSWindow, to url: URL) {
        guard let view = window.contentView else { return }
        let bounds = view.bounds

        // cacheDisplay misses CoreAnimation-backed content (PDFView tiles),
        // so also render the layer tree and keep both.
        if let rep = view.bitmapImageRepForCachingDisplay(in: bounds) {
            rep.size = bounds.size
            view.cacheDisplay(in: bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
            }
        }

        if let layer = view.layer {
            let scale = window.backingScaleFactor
            let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
            if let ctx = CGContext(data: nil, width: width, height: height,
                                   bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) {
                ctx.scaleBy(x: scale, y: scale)
                layer.render(in: ctx)
                if let image = ctx.makeImage() {
                    let rep = NSBitmapImageRep(cgImage: image)
                    let layerURL = url.deletingPathExtension()
                        .appendingPathExtension("layer.png")
                    if let data = rep.representation(using: .png, properties: [:]) {
                        try? data.write(to: layerURL)
                    }
                }
            }
        }

        Self.diagnose(window: window)
        FileHandle.standardError.write("snapshot written: \(url.path)\n".data(using: .utf8)!)
    }

    /// Reports what the live PDFView actually holds, so a blank capture can be
    /// told apart from a blank view.
    static func diagnose(window: NSWindow) {
        func find(_ view: NSView) -> PDFView? {
            if let match = view as? PDFView { return match }
            for sub in view.subviews { if let m = find(sub) { return m } }
            return nil
        }
        var lines: [String] = []
        lines.append("NSApp.windows count: \(NSApp.windows.count)")
        for w in NSApp.windows {
            lines.append("  win '\(w.title)' visible=\(w.isVisible) titled=\(w.styleMask.contains(.titled)) canMain=\(w.canBecomeMain) sheet=\(w.isSheet) class=\(String(describing: type(of: w))) frame=\(NSStringFromRect(w.frame))")
        }
        if let root = window.contentView, let pdf = find(root) {
            lines.append("PDFView frame: \(NSStringFromRect(pdf.frame))")
            lines.append("PDFView hidden: \(pdf.isHidden) alpha: \(pdf.alphaValue)")
            lines.append("document: \(pdf.document == nil ? "nil" : "loaded")")
            lines.append("pageCount: \(pdf.document?.pageCount ?? -1)")
            lines.append("currentPage: \(pdf.currentPage.map { pdf.document?.index(for: $0) ?? -1 } ?? -1)")
            lines.append("scaleFactor: \(pdf.scaleFactor)")
            lines.append("wantsLayer: \(pdf.wantsLayer) layer: \(pdf.layer != nil)")
            lines.append("subviews: \(pdf.subviews.map { String(describing: type(of: $0)) })")
            if let doc = pdf.document, let page = doc.page(at: 0) {
                lines.append("page0 bounds: \(NSStringFromRect(page.bounds(for: .mediaBox)))")
                lines.append("page0 text chars: \((page.string ?? "").count)")
            }
        } else {
            lines.append("NO PDFView FOUND in hierarchy")
        }
        FileHandle.standardError.write(("DIAG " + lines.joined(separator: "\nDIAG ") + "\n")
            .data(using: .utf8)!)
    }

    @MainActor
    func drainQueue() {
        guard let model, !queued.isEmpty else { return }
        for url in queued { model.open(url: url) }
        queued.removeAll()
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        accept(filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        accept(urls)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        queued.isEmpty
    }

    private func accept(_ urls: [URL]) {
        if let model {
            MainActor.assumeIsolated {
                for url in urls { _ = model.open(url: url) }
            }
        } else {
            queued += urls
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - menu bar

struct RiftPDFCommands: Commands {
    @ObservedObject var app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") { app.openPanel() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(app.recentFiles, id: \.self) { url in
                    Button(url.lastPathComponent) { app.open(url: url) }
                }
                Divider()
                Button("Clear Menu") { app.clearRecents() }
            }
            Divider()
            Button("Combine PDFs…") { app.sheet = .merge }
            Button("Images to PDF…") { app.sheet = .imagesToPDF }
            Button("Word to PDF…") {
                app.chooseFiles(types: OfficeConverter.readableTypes,
                                message: "Choose documents to convert") { app.convertOfficeToPDF($0) }
            }
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save") { if let doc = app.current { app.save(doc) } }
                .keyboardShortcut("s")
                .disabled(app.current == nil)
            Button("Save As…") { if let doc = app.current { app.saveAs(doc) } }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(app.current == nil)
            Divider()
            Menu("Export") {
                Button("To Word (.docx)…") { if let d = app.current { app.exportWord(d) } }
                Button("To Plain Text…") { if let d = app.current { app.exportText(d) } }
                Button("To Images…") { app.sheet = .exportImages }
                Button("Tables to Excel…") { if let d = app.current { app.exportExcel(d, includeUnruled: false) } }
                Divider()
                Button("Extract Embedded Images…") { if let d = app.current { app.extractImages(d) } }
                Button("Split into Several Files…") { app.sheet = .split }
            }
            .disabled(app.current == nil)
            Divider()
            Button("Close Document") { if let doc = app.current { app.close(doc) } }
                .keyboardShortcut("w")
                .disabled(app.current == nil)
            Button("Print…") { PDFViewLocator.find()?.print(with: .shared, autoRotate: true) }
                .keyboardShortcut("p")
                .disabled(app.current == nil)
        }

        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                app.current?.undoManager.undo()
                app.current?.afterExternalMutation()
                ThumbnailCache.shared.invalidate()
            }
            .keyboardShortcut("z")
            .disabled(app.current?.undoManager.canUndo != true)

            Button("Redo") {
                app.current?.undoManager.redo()
                app.current?.afterExternalMutation()
                ThumbnailCache.shared.invalidate()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(app.current?.undoManager.canRedo != true)
        }

        CommandMenu("Tools") {
            Section("Size and quality") {
                Button("Shrink File Size…") { app.sheet = .compress }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Button("Optimise for Web") { if let d = app.current { app.linearize(d) } }
                Button("Repair Damaged File") { if let d = app.current { app.repairDocument(d) } }
            }
            Section("Content") {
                Button("Recognise Text (OCR)…") { app.sheet = .ocr }
                Button("Add Watermark…") { app.sheet = .watermark }
                Button("Add Page Numbers…") { app.sheet = .pageNumbers }
                Button("Headers, Footers and Bates…") { app.sheet = .headerFooter }
                Button("Form Fields…") { app.sheet = .formFill }
                Button("Bookmarks…") { app.sheet = .bookmarks }
                Button("Attachments…") { app.sheet = .attachments }
            }
            Section("Privacy") {
                Button("Metadata…") { app.sheet = .metadata }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                Button("Remove All Metadata") {
                    if let d = app.current { app.stripMetadata(d, removeAttachments: false, resetID: true) }
                }
                Button("Remove Active Content") { if let d = app.current { app.sanitize(d) } }
                Button("Apply Marked Redactions") { if let d = app.current { app.applyRedactions(d) } }
                Button("Password and Permissions…") { app.sheet = .security }
            }
            Section("Document") {
                Button("Flatten Markup into Page") {
                    if let d = app.current { app.flatten(d, annotations: true, widgets: true) }
                }
                Button("Place Images into Page") {
                    if let d = app.current { app.flattenPlacedImages(d) }
                }
                Button("Compare with Another PDF…") { app.sheet = .compare }
                Button("Document Properties…") { app.sheet = .documentInfo }
                    .keyboardShortcut("i")
                Button("Where the Space Goes…") { app.sheet = .auditSpace }
                Button("Batch Processing…") { app.sheet = .batch }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
            }
            Section("Accessibility") {
                Button("Accessibility Check…") { app.sheet = .accessibility }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }

        CommandMenu("Pages") {
            Button("Insert Blank Page") {
                if let d = app.current { d.insertBlankPage(at: d.currentPage + 1) }
                ThumbnailCache.shared.invalidate()
            }
            Button("Insert Pages from PDF…") {
                guard let d = app.current else { return }
                app.chooseFiles(types: [.pdf], multiple: false, message: "Choose a PDF to insert") { urls in
                    guard let url = urls.first, let src = PDFDocument(url: url) else { return }
                    d.insertPages(from: src, at: d.currentPage + 1)
                    ThumbnailCache.shared.invalidate()
                }
            }
            Divider()
            Button("Rotate Right") { rotate(90) }
                .keyboardShortcut("]", modifiers: [.command])
            Button("Rotate Left") { rotate(-90) }
                .keyboardShortcut("[", modifiers: [.command])
            Button("Duplicate Page") {
                if let d = app.current { d.duplicatePages(targets(d)) }
                ThumbnailCache.shared.invalidate()
            }
            Button("Delete Page") {
                if let d = app.current { d.deletePages(targets(d)); app.selectedPages.removeAll() }
                ThumbnailCache.shared.invalidate()
            }
            Divider()
            Menu("Resize Pages To") {
                ForEach(["letter", "a4", "legal", "tabloid"], id: \.self) { size in
                    Button(size.capitalized) { if let d = app.current { app.resizePages(d, pageSize: size) } }
                }
            }
        }

        CommandMenu("Markup") {
            ForEach(Tool.allCases) { tool in
                ToolMenuItem(tool: tool, app: app)
            }
        }

        CommandGroup(after: .sidebar) {
            Button(app.showSidebar ? "Hide Sidebar" : "Show Sidebar") {
                withAnimation { app.showSidebar.toggle() }
            }
            .keyboardShortcut("\\", modifiers: [.command])
            Button(app.showInspector ? "Hide Inspector" : "Show Inspector") {
                withAnimation { app.showInspector.toggle() }
            }
            .keyboardShortcut("\\", modifiers: [.command, .option])
            Divider()
            Menu("Display Mode") {
                ForEach(DisplayMode.allCases) { mode in
                    Button(mode.title) { app.displayMode = mode }
                }
            }
            Button("Reading View") {
                guard let doc = app.current else { return }
                app.loadReadingText(doc, wholeDocument: true)
                app.showReadingView = true
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(app.current == nil)
            Button(app.speech.isSpeaking ? "Stop Reading" : "Read Out Loud") {
                guard let doc = app.current else { return }
                app.readAloud(doc, wholeDocument: true)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(app.current == nil)
            Divider()
            Button("Zoom In") { scale(1.2) }.keyboardShortcut("+", modifiers: [.command])
            Button("Zoom Out") { scale(1 / 1.2) }.keyboardShortcut("-", modifiers: [.command])
            Button("Fit to Window") {
                PDFViewLocator.find()?.autoScales = true
                app.zoomLabel = "Fit"
            }
            .keyboardShortcut("0", modifiers: [.command])
            Divider()
            Button("Next Page") { PDFViewLocator.find()?.goToNextPage(nil) }
                .keyboardShortcut(.downArrow, modifiers: [.command])
            Button("Previous Page") { PDFViewLocator.find()?.goToPreviousPage(nil) }
                .keyboardShortcut(.upArrow, modifiers: [.command])
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings and Engine Status…") { app.sheet = .preferences }
                .keyboardShortcut(",")
            Button("Save Window Snapshot…") {
                guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.png]
                panel.nameFieldStringValue = "RiftPDF snapshot.png"
                if panel.runModal() == .OK, let url = panel.url {
                    AppDelegate.capture(window: window, to: url)
                    app.success("Snapshot saved", url.lastPathComponent, reveal: url)
                }
            }
        }
    }

    private func targets(_ doc: PDFDoc) -> [Int] {
        app.selectedPages.isEmpty ? [doc.currentPage] : Array(app.selectedPages)
    }

    private func rotate(_ degrees: Int) {
        guard let doc = app.current else { return }
        doc.rotatePages(targets(doc), by: degrees)
        ThumbnailCache.shared.invalidate()
    }

    private func scale(_ factor: CGFloat) {
        guard let view = PDFViewLocator.find() else { return }
        view.autoScales = false
        view.scaleFactor = min(max(view.scaleFactor * factor, 0.1), 12)
        app.zoomLabel = "\(Int(view.scaleFactor * 100))%"
    }
}


/// Tools get ⌃-prefixed shortcuts so a bare keypress still types into fields.
struct ToolMenuItem: View {
    let tool: Tool
    @ObservedObject var app: AppModel

    var body: some View {
        if let key = tool.shortcut {
            Button(tool.title) { app.tool = tool }
                .keyboardShortcut(KeyboardShortcut(key, modifiers: [.control]))
        } else {
            Button(tool.title) { app.tool = tool }
        }
    }
}
