import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// Everything the app can *do* to a document. Each operation stages the live
// document (annotations and all) to a temp file, hands it to the engine, then
// swaps the result back in as a single undoable step.
extension AppModel {

    // MARK: - generic in-place transform

    func transform(_ doc: PDFDoc,
                   title: String,
                   command: String,
                   actionName: String? = nil,
                   extraPayload: [String: Any] = [:],
                   summary: @escaping ([String: Any]) -> (String, String?)) {
        job(title) { task in
            let input = try doc.stageToTemporaryFile()
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("riftpdf-out-\(UUID().uuidString).pdf")
            var payload: [String: Any] = ["input": input.path, "output": output.path]
            if let pw = doc.password { payload["password"] = pw }
            payload.merge(extraPayload) { _, new in new }

            let res = try await Engine.shared.run(command, payload) { value, message in
                task.update(value, message)
            }
            guard let produced = PDFDocument(url: output) else {
                throw Engine.Failure(message: "The engine returned a file RiftPDF could not read.",
                                     detail: output.path)
            }
            try? FileManager.default.removeItem(at: input)
            return (produced, res)
        } onSuccess: { [weak self] (produced: PDFDocument, res: [String: Any]) in
            guard let self else { return }
            doc.replaceDocument(with: produced, actionName: actionName ?? title)
            let (headline, detail) = summary(res)
            self.success(headline, detail)
        }
    }

    /// Same, but writes to a user-chosen destination instead of editing in place.
    func exportTransform(_ doc: PDFDoc,
                         title: String,
                         command: String,
                         suggestedName: String,
                         contentType: UTType,
                         extraPayload: [String: Any] = [:],
                         summary: @escaping ([String: Any], URL) -> (String, String?)) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = suggestedName
        panel.directoryURL = doc.url?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let target = panel.url else { return }

        job(title) { task in
            let input = try doc.stageToTemporaryFile()
            var payload: [String: Any] = ["input": input.path, "output": target.path]
            if let pw = doc.password { payload["password"] = pw }
            payload.merge(extraPayload) { _, new in new }
            let res = try await Engine.shared.run(command, payload) { v, m in task.update(v, m) }
            try? FileManager.default.removeItem(at: input)
            return res
        } onSuccess: { [weak self] res in
            let (headline, detail) = summary(res, target)
            self?.success(headline, detail, reveal: target)
        }
    }

    // MARK: - compression

    func compress(_ doc: PDFDoc, preset: String, dpi: Int, quality: Int,
                  grayscale: Bool, stripMetadata: Bool, flatten: Bool, inPlace: Bool) {
        let payload: [String: Any] = [
            "preset": preset, "dpi": dpi, "quality": quality, "grayscale": grayscale,
            "removeMetadata": stripMetadata, "flattenAnnotations": flatten,
            "recompressImages": true, "subsetFonts": true, "useGhostscript": true,
        ]
        let describe: ([String: Any]) -> (String, String?) = { res in
            let before = res["beforeHuman"] as? String ?? ""
            let after = res["afterHuman"] as? String ?? ""
            let ratio = res["ratio"] as? Double ?? 0
            if ratio <= 0.5 {
                return ("Already about as small as it gets",
                        "\(before) → \(after). Try a stronger preset for more.")
            }
            return ("Shrunk by \(Int(ratio))%", "\(before) → \(after)")
        }
        if inPlace {
            transform(doc, title: "Compressing", command: "compress",
                      actionName: "Compress", extraPayload: payload, summary: describe)
        } else {
            exportTransform(doc, title: "Compressing", command: "compress",
                            suggestedName: (doc.url?.displayName ?? "Document") + " compressed.pdf",
                            contentType: .pdf, extraPayload: payload) { res, url in
                let (h, d) = describe(res)
                return (h, [d, url.lastPathComponent].compactMap { $0 }.joined(separator: " · "))
            }
        }
    }

    /// Compress until the file fits a size the user names, keeping the best
    /// quality that still fits.
    func compressToTarget(_ doc: PDFDoc, targetBytes: Int, allowGrayscale: Bool,
                          stripMetadata: Bool, inPlace: Bool) {
        let payload: [String: Any] = [
            "targetBytes": targetBytes,
            "allowGrayscale": allowGrayscale,
            "removeMetadata": stripMetadata,
        ]

        // Not routed through `transform` because a missed target should read as
        // a warning, not a success.
        let destination: URL?
        if inPlace {
            destination = nil
        } else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = (doc.url?.displayName ?? "Document") + " compressed.pdf"
            panel.directoryURL = doc.url?.deletingLastPathComponent()
            guard panel.runModal() == .OK, let url = panel.url else { return }
            destination = url
        }

        job("Compressing to \(formatBytes(targetBytes))") { task in
            let input = try doc.stageToTemporaryFile()
            let output = destination ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("riftpdf-target-\(UUID().uuidString).pdf")
            var full: [String: Any] = ["input": input.path, "output": output.path]
            if let pw = doc.password { full["password"] = pw }
            full.merge(payload) { _, new in new }

            let res = try await Engine.shared.run("compress_target", full) { v, m in
                task.update(v, m)
            }
            try? FileManager.default.removeItem(at: input)
            let produced = destination == nil ? PDFDocument(url: output) : nil
            return (res, produced, output)
        } onSuccess: { [weak self] (res: [String: Any], produced: PDFDocument?, output: URL) in
            guard let self else { return }
            if let produced { doc.replaceDocument(with: produced, actionName: "Compress") }

            let hit = res["hitTarget"] as? Bool ?? false
            let before = res["beforeHuman"] as? String ?? ""
            let after = res["afterHuman"] as? String ?? ""
            let target = res["targetHuman"] as? String ?? ""
            let settings = res["settings"] as? String ?? ""
            let attempts = res["attempts"] as? Int ?? 0
            let note = res["note"] as? String

            if hit {
                var detail = "\(before) → \(after), under your \(target) target"
                if attempts > 0 { detail += " · \(settings) · \(attempts) passes" }
                if let note { detail = note }
                self.success("Now \(after)", detail,
                             reveal: destination != nil ? output : nil)
            } else {
                self.notify(Toast(kind: .warning,
                                  title: "Got to \(after) — couldn't reach \(target)",
                                  detail: note,
                                  actionTitle: destination != nil ? "Show in Finder" : nil,
                                  revealURL: destination))
            }
        }
    }

    // MARK: - metadata

    func applyMetadata(_ doc: PDFDoc, values: [String: String]) {
        transform(doc, title: "Updating metadata", command: "metadata_set",
                  actionName: "Change Metadata", extraPayload: ["metadata": values]) { _ in
            ("Metadata updated", nil)
        }
    }

    func stripMetadata(_ doc: PDFDoc, removeAttachments: Bool, resetID: Bool) {
        transform(doc, title: "Removing metadata", command: "metadata_strip",
                  actionName: "Remove Metadata",
                  extraPayload: ["removeAttachments": removeAttachments,
                                 "resetDocumentID": resetID,
                                 "removeAnnotationAuthors": true]) { res in
            let removed = res["removed"] as? [String] ?? []
            return ("Metadata removed", removed.joined(separator: " · "))
        }
    }

    func sanitize(_ doc: PDFDoc) {
        transform(doc, title: "Removing active content", command: "sanitize",
                  actionName: "Sanitise") { res in
            let removed = res["removed"] as? [String] ?? []
            return ("Document sanitised", removed.joined(separator: " · "))
        }
    }

    // MARK: - stamping

    func watermark(_ doc: PDFDoc, text: String, fontSize: Double, opacity: Double,
                   rotation: Double, color: Color, pages: String, onTop: Bool) {
        transform(doc, title: "Adding watermark", command: "watermark",
                  actionName: "Add Watermark",
                  extraPayload: ["text": text, "fontSize": fontSize, "opacity": opacity,
                                 "rotate": rotation, "color": color.pdfComponents,
                                 "pages": pages, "onTop": onTop, "kind": "text"]) { res in
            ("Watermark applied", "\(res["pagesStamped"] as? Int ?? 0) pages")
        }
    }

    func imageWatermark(_ doc: PDFDoc, imagePath: String, scale: Double,
                        opacity: Double, pages: String, onTop: Bool) {
        transform(doc, title: "Adding watermark", command: "watermark",
                  actionName: "Add Watermark",
                  extraPayload: ["kind": "image", "imagePath": imagePath, "scale": scale,
                                 "opacity": opacity, "pages": pages, "onTop": onTop,
                                 "rotate": 0]) { res in
            ("Watermark applied", "\(res["pagesStamped"] as? Int ?? 0) pages")
        }
    }

    func addPageNumbers(_ doc: PDFDoc, format: String, position: String, startAt: Int,
                        fontSize: Double, margin: Double, color: Color, pages: String) {
        transform(doc, title: "Numbering pages", command: "page_numbers",
                  actionName: "Add Page Numbers",
                  extraPayload: ["format": format, "position": position, "startAt": startAt,
                                 "fontSize": fontSize, "margin": margin,
                                 "color": color.pdfComponents, "pages": pages]) { res in
            ("Page numbers added", "\(res["pagesNumbered"] as? Int ?? 0) pages")
        }
    }

    // MARK: - redaction

    func applyRedactions(_ doc: PDFDoc) {
        let areas: [[String: Any]] = pendingRedactions.flatMap { page, rects in
            rects.map { r in
                ["page": page, "rect": [r.minX, r.minY, r.maxX, r.maxY]] as [String: Any]
            }
        }
        guard !areas.isEmpty else {
            warn("Nothing marked for redaction", "Use the Redact tool to draw over what should go.")
            return
        }
        transform(doc, title: "Applying redactions", command: "redact",
                  actionName: "Apply Redactions",
                  extraPayload: ["areas": areas, "fill": [0, 0, 0],
                                 "scrubImages": true, "stripMetadata": true]) { [weak self] res in
            self?.pendingRedactions.removeAll()
            return ("Redactions applied", "\(res["areas"] as? Int ?? 0) areas permanently removed")
        }
    }

    func redactSearch(_ doc: PDFDoc, terms: [String]) {
        transform(doc, title: "Redacting matches", command: "redact_search",
                  actionName: "Redact Matches",
                  extraPayload: ["terms": terms, "fill": [0, 0, 0]]) { res in
            let n = res["occurrences"] as? Int ?? 0
            return (n == 0 ? "No matches found" : "Redacted \(n) occurrence\(n == 1 ? "" : "s")", nil)
        }
    }

    // MARK: - security

    func encrypt(_ doc: PDFDoc, userPassword: String, ownerPassword: String,
                 permissions: [String: Bool]) {
        transform(doc, title: "Encrypting", command: "encrypt", actionName: "Encrypt",
                  extraPayload: ["userPassword": userPassword,
                                 "ownerPassword": ownerPassword,
                                 "permissions": permissions]) { res in
            ("Protected with \(res["encryption"] as? String ?? "AES-256")",
             "Save the document to write the encryption to disk.")
        }
    }

    func decrypt(_ doc: PDFDoc) {
        transform(doc, title: "Removing protection", command: "decrypt",
                  actionName: "Remove Protection") { _ in
            ("Password protection removed", nil)
        }
    }

    // MARK: - structure

    func flatten(_ doc: PDFDoc, annotations: Bool, widgets: Bool) {
        transform(doc, title: "Flattening", command: "flatten", actionName: "Flatten",
                  extraPayload: ["annotations": annotations, "widgets": widgets]) { _ in
            ("Flattened", "Markup is now part of the page content.")
        }
    }

    func repairDocument(_ doc: PDFDoc) {
        transform(doc, title: "Repairing", command: "repair", actionName: "Repair") { res in
            ("Document repaired", (res["notes"] as? [String] ?? []).joined(separator: " · "))
        }
    }

    func linearize(_ doc: PDFDoc) {
        transform(doc, title: "Optimising for web", command: "linearize",
                  actionName: "Optimise for Web") { _ in
            ("Optimised for fast web view", nil)
        }
    }

    func resizePages(_ doc: PDFDoc, pageSize: String) {
        transform(doc, title: "Resizing pages", command: "page_ops", actionName: "Resize Pages",
                  extraPayload: ["operations": [["op": "resize", "pageSize": pageSize]]]) { _ in
            ("Pages resized to \(pageSize.uppercased())", nil)
        }
    }

    // MARK: - exports

    func exportWord(_ doc: PDFDoc) {
        exportTransform(doc, title: "Converting to Word", command: "pdf_to_word",
                        suggestedName: (doc.url?.displayName ?? "Document") + ".docx",
                        contentType: UTType.riftpdfWord) { res, url in
            ("Word document created", "\(url.lastPathComponent) · \(formatBytes(res["size"] as? Int ?? 0))")
        }
    }

    func exportText(_ doc: PDFDoc) {
        exportTransform(doc, title: "Extracting text", command: "pdf_to_text",
                        suggestedName: (doc.url?.displayName ?? "Document") + ".txt",
                        contentType: .plainText, extraPayload: ["pageBreaks": true]) { res, url in
            ("Text extracted", "\(res["characters"] as? Int ?? 0) characters")
        }
    }

    func exportImages(_ doc: PDFDoc, dpi: Int, format: String, pages: String) {
        chooseFolder(title: "Choose where to save the images") { [weak self] folder in
            guard let self else { return }
            self.job("Rendering pages") { task in
                let input = try doc.stageToTemporaryFile()
                var payload: [String: Any] = ["input": input.path, "outputDir": folder.path,
                                              "dpi": dpi, "format": format, "pages": pages]
                if let pw = doc.password { payload["password"] = pw }
                let res = try await Engine.shared.run("pdf_to_images", payload) { v, m in task.update(v, m) }
                try? FileManager.default.removeItem(at: input)
                return res
            } onSuccess: { res in
                let files = res["files"] as? [String] ?? []
                self.success("\(files.count) image\(files.count == 1 ? "" : "s") saved",
                             folder.lastPathComponent, reveal: folder)
            }
        }
    }

    func extractImages(_ doc: PDFDoc) {
        chooseFolder(title: "Choose where to save the extracted images") { [weak self] folder in
            guard let self else { return }
            self.job("Extracting images") { task in
                let input = try doc.stageToTemporaryFile()
                var payload: [String: Any] = ["input": input.path, "outputDir": folder.path,
                                              "minPixels": 48]
                if let pw = doc.password { payload["password"] = pw }
                let res = try await Engine.shared.run("extract_images", payload) { v, m in task.update(v, m) }
                try? FileManager.default.removeItem(at: input)
                return res
            } onSuccess: { res in
                let n = res["count"] as? Int ?? 0
                if n == 0 { self.warn("No embedded images found") }
                else { self.success("\(n) image\(n == 1 ? "" : "s") extracted", reveal: folder) }
            }
        }
    }

    func splitDocument(_ doc: PDFDoc, mode: String, every: Int, ranges: [String]) {
        chooseFolder(title: "Choose where to save the split files") { [weak self] folder in
            guard let self else { return }
            self.job("Splitting") { task in
                let input = try doc.stageToTemporaryFile()
                var payload: [String: Any] = ["input": input.path, "outputDir": folder.path,
                                              "mode": mode, "every": every, "ranges": ranges]
                if let pw = doc.password { payload["password"] = pw }
                let res = try await Engine.shared.run("split", payload) { v, m in task.update(v, m) }
                try? FileManager.default.removeItem(at: input)
                return res
            } onSuccess: { res in
                let files = res["files"] as? [String] ?? []
                self.success("Split into \(files.count) file\(files.count == 1 ? "" : "s")",
                             reveal: folder)
            }
        }
    }

    // MARK: - creating new documents

    func mergeFiles(_ urls: [URL], bookmarkPerFile: Bool) {
        guard urls.count >= 1 else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Combined.pdf"
        panel.directoryURL = urls.first?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let target = panel.url else { return }

        job("Combining \(urls.count) files") { task in
            try await Engine.shared.run("merge", [
                "inputs": urls.map(\.path), "output": target.path,
                "bookmarkPerFile": bookmarkPerFile,
            ]) { v, m in task.update(v, m) }
        } onSuccess: { [weak self] res in
            self?.success("Combined into one PDF",
                          "\(res["pageCount"] as? Int ?? 0) pages", reveal: target)
            self?.open(url: target)
        }
    }

    func imagesToPDF(_ urls: [URL], pageSize: String, fit: String, margin: Double, quality: Int) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Images.pdf"
        panel.directoryURL = urls.first?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let target = panel.url else { return }

        job("Building PDF from \(urls.count) images") { task in
            try await Engine.shared.run("images_to_pdf", [
                "inputs": urls.map(\.path), "output": target.path,
                "pageSize": pageSize, "fit": fit, "margin": margin,
                "quality": quality, "autoOrient": true,
            ]) { v, m in task.update(v, m) }
        } onSuccess: { [weak self] res in
            self?.success("PDF created", "\(res["pageCount"] as? Int ?? 0) pages", reveal: target)
            self?.open(url: target)
        }
    }

    // MARK: - helpers

    func chooseFolder(title: String, _ completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = title
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { completion(url) }
    }

    func chooseFiles(types: [UTType], multiple: Bool = true,
                     message: String, _ completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = multiple
        panel.message = message
        if panel.runModal() == .OK { completion(panel.urls) }
    }
}

// MARK: - accessibility

extension AppModel {

    func checkAccessibility(_ doc: PDFDoc) async throws -> [String: Any] {
        let input = try doc.stageToTemporaryFile()
        var payload: [String: Any] = ["input": input.path]
        if let pw = doc.password { payload["password"] = pw }
        defer { try? FileManager.default.removeItem(at: input) }
        return try await Engine.shared.run("accessibility_check", payload)
    }

    func fixAccessibility(_ doc: PDFDoc, rules: [String], title: String, language: String) {
        transform(doc, title: "Repairing accessibility", command: "accessibility_fix",
                  actionName: "Accessibility Fixes",
                  extraPayload: ["rules": rules, "title": title, "language": language]) { res in
            let applied = res["applied"] as? [String] ?? []
            let skipped = res["skipped"] as? [String] ?? []
            var detail = applied.joined(separator: " · ")
            if !skipped.isEmpty {
                detail += (detail.isEmpty ? "" : "\n") + "Not done: " + skipped.joined(separator: " · ")
            }
            return (applied.isEmpty ? "Nothing could be fixed automatically"
                                    : "\(applied.count) fix\(applied.count == 1 ? "" : "es") applied",
                    detail.isEmpty ? nil : detail)
        }
    }

    /// Pulls the document out as reading-ordered text for the reflow view and
    /// read-aloud.
    func loadReadingText(_ doc: PDFDoc, wholeDocument: Bool) {
        readingLoading = true
        readingBlocks = []
        let pages = wholeDocument ? "all" : "\(doc.currentPage + 1)"
        Task {
            defer { readingLoading = false }
            do {
                let input = try doc.stageToTemporaryFile()
                var payload: [String: Any] = ["input": input.path, "pages": pages]
                if let pw = doc.password { payload["password"] = pw }
                let res = try await Engine.shared.run("reading_text", payload)
                try? FileManager.default.removeItem(at: input)

                var blocks: [ReadingBlock] = []
                for page in (res["pages"] as? [[String: Any]] ?? []) {
                    let index = page["page"] as? Int ?? 0
                    for block in (page["blocks"] as? [[String: Any]] ?? []) {
                        guard let text = block["text"] as? String,
                              !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                        blocks.append(ReadingBlock(page: index, text: text,
                                                   heading: block["heading"] as? Bool ?? false))
                    }
                }
                readingBlocks = blocks
                if blocks.isEmpty {
                    warn("Nothing to read on this page",
                         "If it's a scan, run Tools ▸ Recognise Text first.")
                }
            } catch {
                report(error, context: "Could not read the document text")
            }
        }
    }

    func readAloud(_ doc: PDFDoc, wholeDocument: Bool) {
        if speech.isSpeaking { speech.stop(); return }
        if readingBlocks.isEmpty {
            loadReadingText(doc, wholeDocument: wholeDocument)
            Task {
                while readingLoading { try? await Task.sleep(for: .milliseconds(120)) }
                guard !readingBlocks.isEmpty else { return }
                speech.speak(readingBlocks.map(\.text))
            }
        } else {
            speech.speak(readingBlocks.map(\.text))
        }
    }

    // MARK: - Acrobat-style extras

    func applyHeaderFooter(_ doc: PDFDoc, header: [String: String], footer: [String: String],
                           fontSize: Double, margin: Double, color: Color, pages: String,
                           startAt: Int, batesPrefix: String, batesStart: Int, batesDigits: Int) {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let now = Date()

        transform(doc, title: "Adding headers and footers", command: "header_footer",
                  actionName: "Headers and Footers",
                  extraPayload: ["header": header, "footer": footer,
                                 "fontSize": fontSize, "margin": margin,
                                 "color": color.pdfComponents, "pages": pages,
                                 "startAt": startAt, "batesPrefix": batesPrefix,
                                 "batesStart": batesStart, "batesDigits": batesDigits,
                                 "date": formatter.string(from: now),
                                 "time": timeFormatter.string(from: now)]) { res in
            ("Headers and footers added", "\(res["pagesStamped"] as? Int ?? 0) pages")
        }
    }

    func exportExcel(_ doc: PDFDoc, includeUnruled: Bool) {
        exportTransform(doc, title: "Extracting tables", command: "tables_to_excel",
                        suggestedName: (doc.url?.displayName ?? "Tables") + ".xlsx",
                        contentType: UTType(filenameExtension: "xlsx") ?? .data,
                        extraPayload: ["includeUnruled": includeUnruled]) { res, url in
            let tables = res["tables"] as? Int ?? 0
            return ("\(tables) table\(tables == 1 ? "" : "s") exported",
                    "\(res["sheets"] as? Int ?? 0) sheets · \(url.lastPathComponent)")
        }
    }

    func auditSpace(_ doc: PDFDoc) async throws -> [String: Any] {
        let input = try doc.stageToTemporaryFile()
        var payload: [String: Any] = ["input": input.path]
        if let pw = doc.password { payload["password"] = pw }
        defer { try? FileManager.default.removeItem(at: input) }
        return try await Engine.shared.run("audit_space", payload)
    }

    // MARK: - batch processing

    enum BatchAction: String, CaseIterable, Identifiable {
        case compress, removeMetadata, sanitize, toWord, toText, ocr, flatten, linearize
        var id: String { rawValue }
        var title: String {
            switch self {
            case .compress: "Shrink file size"
            case .removeMetadata: "Remove all metadata"
            case .sanitize: "Remove active content"
            case .toWord: "Convert to Word"
            case .toText: "Extract text"
            case .ocr: "Recognise text (OCR)"
            case .flatten: "Flatten markup"
            case .linearize: "Optimise for web"
            }
        }
        var producesPDF: Bool { self != .toWord && self != .toText }
        var fileExtension: String {
            switch self {
            case .toWord: "docx"
            case .toText: "txt"
            default: "pdf"
            }
        }
    }

    func runBatch(files: [URL], action: BatchAction, outputFolder: URL, preset: String) {
        guard !files.isEmpty else { return }
        job("Batch: \(action.title)") { task in
            var done: [URL] = []
            var failures: [String] = []

            for (index, file) in files.enumerated() {
                await MainActor.run {
                    task.update(Double(index) / Double(files.count),
                                "\(file.lastPathComponent) — \(index + 1) of \(files.count)")
                }
                let target = outputFolder
                    .appendingPathComponent(file.deletingPathExtension().lastPathComponent)
                    .appendingPathExtension(action.fileExtension)
                do {
                    switch action {
                    case .ocr:
                        guard let source = PDFDocument(url: file) else {
                            throw Engine.Failure(message: "Could not open \(file.lastPathComponent)", detail: nil)
                        }
                        let words = try await OCRService.recognise(
                            document: source, pageIndices: Array(0..<source.pageCount),
                            languages: ["en-US"], fast: true) { _, _ in }
                        _ = try await Engine.shared.run("ocr_layer", [
                            "input": file.path, "output": target.path,
                            "words": words.map { ["page": $0.page, "text": $0.text, "rect": $0.rect] },
                        ])
                    case .compress:
                        _ = try await Engine.shared.run("compress", [
                            "input": file.path, "output": target.path, "preset": preset,
                        ])
                    case .removeMetadata:
                        _ = try await Engine.shared.run("metadata_strip", [
                            "input": file.path, "output": target.path,
                        ])
                    case .sanitize:
                        _ = try await Engine.shared.run("sanitize", [
                            "input": file.path, "output": target.path,
                        ])
                    case .toWord:
                        _ = try await Engine.shared.run("pdf_to_word", [
                            "input": file.path, "output": target.path,
                        ])
                    case .toText:
                        _ = try await Engine.shared.run("pdf_to_text", [
                            "input": file.path, "output": target.path,
                        ])
                    case .flatten:
                        _ = try await Engine.shared.run("flatten", [
                            "input": file.path, "output": target.path,
                        ])
                    case .linearize:
                        _ = try await Engine.shared.run("linearize", [
                            "input": file.path, "output": target.path,
                        ])
                    }
                    done.append(target)
                } catch {
                    let reason = (error as? Engine.Failure)?.message ?? error.localizedDescription
                    failures.append("\(file.lastPathComponent): \(reason)")
                }
            }
            return (done, failures)
        } onSuccess: { [weak self] (done: [URL], failures: [String]) in
            guard let self else { return }
            if failures.isEmpty {
                self.success("Processed \(done.count) file\(done.count == 1 ? "" : "s")",
                             outputFolder.lastPathComponent, reveal: outputFolder)
            } else {
                self.notify(Toast(kind: failures.count == files.count ? .failure : .warning,
                                  title: "\(done.count) of \(files.count) processed",
                                  detail: failures.prefix(3).joined(separator: "\n"),
                                  actionTitle: "Show in Finder", revealURL: outputFolder))
            }
        }
    }

    // MARK: - default reader

    var isDefaultPDFReader: Bool {
        guard let handler = LSCopyDefaultRoleHandlerForContentType(
            "com.adobe.pdf" as CFString, .all)?.takeRetainedValue() as String? else { return false }
        return handler.caseInsensitiveCompare(Bundle.main.bundleIdentifier ?? "") == .orderedSame
    }

    var currentPDFReaderName: String {
        guard let handler = LSCopyDefaultRoleHandlerForContentType(
                "com.adobe.pdf" as CFString, .all)?.takeRetainedValue() as String?,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: handler)
        else { return "unknown" }
        return url.deletingPathExtension().lastPathComponent
    }

    /// macOS requires the app itself to ask, and shows its own confirmation.
    /// Offers once, on first launch, to take over PDFs. macOS shows its own
    /// confirmation; we never change the setting behind the user's back.
    func offerToBecomeDefaultReader() {
        let key = "askedToBeDefaultPDFReader"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        guard !isDefaultPDFReader else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, let window = NSApp.windows.first(where: { $0.isVisible })
            else { return }
            let reader = self.currentPDFReaderName
            let alert = NSAlert()
            alert.messageText = "Open PDFs with RiftPDF?"
            alert.informativeText = "PDFs currently open in \(reader). Making RiftPDF "
                + "the default means double-clicking any PDF in Finder opens it here."
                + "\n\nmacOS will ask you to confirm."
            alert.addButton(withTitle: "Use RiftPDF")
            alert.addButton(withTitle: "Not Now")
            alert.alertStyle = .informational
            // A sheet, not runModal: a modal alert here blocks the main thread,
            // leaving the whole app frozen until someone answers it.
            alert.beginSheetModal(for: window) { response in
                UserDefaults.standard.set(true, forKey: key)
                if response == .alertFirstButtonReturn {
                    self.requestDefaultPDFReader()
                }
            }
        }
    }

    func requestDefaultPDFReader() {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL,
                                                 toOpen: .pdf) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.fail("Could not become the default reader", error.localizedDescription)
                } else {
                    self.success("RiftPDF is now your default PDF reader",
                                 "Double-clicking a PDF in Finder will open it here.")
                }
            }
        }
    }
}
