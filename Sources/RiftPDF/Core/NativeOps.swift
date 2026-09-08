import SwiftUI
import PDFKit
import Vision
import UniformTypeIdentifiers

// MARK: - Word / RTF / text → PDF, without needing Office installed

enum OfficeConverter {

    struct Layout {
        var pageSize = CGSize(width: 612, height: 792)
        var margin: CGFloat = 56
    }

    static let readableTypes: [UTType] = [
        UTType(filenameExtension: "docx") ?? .data,
        UTType(filenameExtension: "doc") ?? .data,
        .rtf, .plainText, .html,
        UTType(filenameExtension: "rtfd") ?? .data,
        UTType(filenameExtension: "odt") ?? .data,
    ]

    static func documentType(for url: URL) -> NSAttributedString.DocumentType? {
        switch url.pathExtension.lowercased() {
        case "docx": .officeOpenXML
        case "doc": .docFormat
        case "rtf": .rtf
        case "rtfd": .rtfd
        case "html", "htm": .html
        case "txt", "md", "text": .plain
        default: nil
        }
    }

    /// Reads the document with AppKit's own importers, then typesets it into a
    /// real vector PDF — text stays selectable and searchable.
    static func convert(_ url: URL, layout: Layout = Layout()) throws -> URL {
        let attributed = try read(url)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("riftpdf-office-\(UUID().uuidString).pdf")
        try typeset(attributed, to: output, layout: layout)
        return output
    }

    static func read(_ url: URL) throws -> NSAttributedString {
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        if let type = documentType(for: url) { options[.documentType] = type }
        options[.characterEncoding] = String.Encoding.utf8.rawValue

        if let attr = try? NSAttributedString(url: url, options: options,
                                              documentAttributes: nil), attr.length > 0 {
            return attr
        }
        // Second chance: let textutil normalise it to RTF first. It reads a few
        // stubborn Word variants AppKit's direct importer rejects.
        let rtf = FileManager.default.temporaryDirectory
            .appendingPathComponent("riftpdf-\(UUID().uuidString).rtf")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        proc.arguments = ["-convert", "rtf", "-output", rtf.path, url.path]
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        if FileManager.default.fileExists(atPath: rtf.path),
           let attr = try? NSAttributedString(url: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                              documentAttributes: nil), attr.length > 0 {
            try? FileManager.default.removeItem(at: rtf)
            return attr
        }
        throw NSError(domain: "RiftPDF", code: 10, userInfo: [
            NSLocalizedDescriptionKey: "Could not read \(url.lastPathComponent).",
            NSLocalizedRecoverySuggestionErrorKey: "RiftPDF reads .docx, .doc, .rtf, .odt, .html and .txt.",
        ])
    }

    static func typeset(_ text: NSAttributedString, to output: URL, layout: Layout) throws {
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        manager.usesFontLeading = true
        storage.addLayoutManager(manager)

        let textSize = CGSize(width: layout.pageSize.width - layout.margin * 2,
                              height: layout.pageSize.height - layout.margin * 2)

        var mediaBox = CGRect(origin: .zero, size: layout.pageSize)
        guard let consumer = CGDataConsumer(url: output as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "RiftPDF", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create the PDF."])
        }

        var containerIndex = 0
        var consumedGlyphs = 0
        repeat {
            let container = NSTextContainer(size: textSize)
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)

            let glyphRange = manager.glyphRange(for: container)
            if glyphRange.length == 0 && containerIndex > 0 { break }

            context.beginPDFPage(nil)
            let previous = NSGraphicsContext.current
            let gc = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.current = gc

            context.saveGState()
            context.translateBy(x: layout.margin, y: layout.pageSize.height - layout.margin)
            context.scaleBy(x: 1, y: -1)
            manager.drawBackground(forGlyphRange: glyphRange, at: .zero)
            manager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
            context.restoreGState()

            NSGraphicsContext.current = previous
            context.endPDFPage()

            consumedGlyphs = NSMaxRange(glyphRange)
            containerIndex += 1
            if glyphRange.length == 0 { break }
        } while consumedGlyphs < manager.numberOfGlyphs && containerIndex < 4000

        context.closePDF()
    }
}

// MARK: - OCR with Vision

enum OCRService {

    struct Word: Sendable {
        let page: Int
        let text: String
        let rect: [Double]      // x0, top, x1, bottom — PDF points, origin top-left
    }

    static var availableLanguages: [String] {
        (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? ["en-US"]
    }

    static func recognise(document: PDFDocument,
                          pageIndices: [Int],
                          languages: [String],
                          fast: Bool,
                          dpi: CGFloat = 300,
                          progress: @escaping @Sendable @MainActor (Double, String) -> Void) async throws -> [Word] {
        var words: [Word] = []
        for (n, index) in pageIndices.enumerated() {
            guard let page = document.page(at: index) else { continue }
            let fraction = Double(n) / Double(max(1, pageIndices.count))
            await progress(fraction * 0.9, "Reading page \(index + 1) of \(pageIndices.count)")

            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 1, bounds.height > 1 else { continue }
            guard let image = render(page: page, bounds: bounds, dpi: dpi) else { continue }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = fast ? .fast : .accurate
            request.usesLanguageCorrection = true
            let supported = availableLanguages
            let wanted = languages.filter { supported.contains($0) }
            if !wanted.isEmpty { request.recognitionLanguages = wanted }

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])

            let rotation = page.rotation % 360
            let (pw, ph) = (rotation == 90 || rotation == 270)
                ? (bounds.height, bounds.width) : (bounds.width, bounds.height)

            for observation in (request.results ?? []) {
                guard let candidate = observation.topCandidates(1).first,
                      !candidate.string.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                let b = observation.boundingBox        // normalised, origin bottom-left
                words.append(Word(
                    page: index,
                    text: candidate.string,
                    rect: [Double(b.minX * pw), Double((1 - b.maxY) * ph),
                           Double(b.maxX * pw), Double((1 - b.minY) * ph)]))
            }
        }
        await progress(0.92, "Building text layer")
        return words
    }

    private static func render(page: PDFPage, bounds: CGRect, dpi: CGFloat) -> CGImage? {
        let scale = dpi / 72.0
        let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }
}

// MARK: - app-level wiring

extension AppModel {

    /// Word (and friends) → PDF. Uses LibreOffice when it's installed for
    /// pixel-faithful output, otherwise AppKit's own typesetter.
    func convertOfficeToPDF(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        job("Converting \(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) documents")") { task in
            var produced: [URL] = []
            for (i, url) in urls.enumerated() {
                await MainActor.run {
                    task.update(Double(i) / Double(urls.count), "Converting \(url.lastPathComponent)")
                }
                let target = url.uniqueSibling(suffix: "", ext: "pdf")
                var done = false
                if Engine.shared.capabilities.libreOffice {
                    do {
                        _ = try await Engine.shared.run("office_to_pdf",
                                                        ["input": url.path, "output": target.path])
                        done = true
                    } catch { done = false }
                }
                if !done {
                    let temp = try OfficeConverter.convert(url)
                    try? FileManager.default.removeItem(at: target)
                    try FileManager.default.moveItem(at: temp, to: target)
                }
                produced.append(target)
            }
            return produced
        } onSuccess: { [weak self] produced in
            guard let self else { return }
            for url in produced { self.open(url: url) }
            let fidelity = Engine.shared.capabilities.libreOffice
                ? nil
                : "Converted with the built-in typesetter. Install LibreOffice for exact Word layout fidelity."
            self.success("\(produced.count) PDF\(produced.count == 1 ? "" : "s") created",
                         fidelity, reveal: produced.first)
        }
    }

    /// Recognise text on scanned pages and weld it in as an invisible,
    /// searchable layer.
    func runOCR(_ doc: PDFDoc, pages: [Int], languages: [String], fast: Bool) {
        let snapshot = doc.document
        job("Recognising text") { task in
            let words = try await OCRService.recognise(
                document: snapshot, pageIndices: pages, languages: languages, fast: fast
            ) { value, message in task.update(value, message) }

            guard !words.isEmpty else { return (PDFDocument(), 0) }

            let input = try await MainActor.run { try doc.stageToTemporaryFile() }
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("riftpdf-ocr-\(UUID().uuidString).pdf")
            var payload: [String: Any] = [
                "input": input.path, "output": output.path,
                "words": words.map { ["page": $0.page, "text": $0.text, "rect": $0.rect] },
            ]
            if let pw = await doc.password { payload["password"] = pw }
            _ = try await Engine.shared.run("ocr_layer", payload) { v, m in task.update(v, m) }
            guard let produced = PDFDocument(url: output) else {
                throw Engine.Failure(message: "The OCR text layer could not be written.", detail: nil)
            }
            try? FileManager.default.removeItem(at: input)
            return (produced, words.count)
        } onSuccess: { [weak self] (produced: PDFDocument, count: Int) in
            guard let self else { return }
            if count == 0 {
                self.warn("No text recognised", "These pages look like they have no readable text.")
                return
            }
            doc.replaceDocument(with: produced, actionName: "OCR")
            self.success("Text layer added", "\(count) lines recognised — the document is now searchable.")
        }
    }

    /// Burn placed images (signatures, logos, photos) into the page content so
    /// every other PDF reader shows them too.
    func flattenPlacedImages(_ doc: PDFDoc, then completion: (() -> Void)? = nil) {
        var items: [[String: Any]] = []
        for i in 0..<doc.document.pageCount {
            guard let page = doc.document.page(at: i) else { continue }
            for annotation in page.annotations {
                guard let stamp = annotation as? ImageStampAnnotation,
                      let data = stamp.pngData() else { continue }
                let b = stamp.bounds
                let pageBounds = page.bounds(for: .mediaBox)
                items.append([
                    "page": i,
                    // PDFKit is bottom-left, the engine is top-left
                    "rect": [b.minX, pageBounds.height - b.maxY, b.maxX, pageBounds.height - b.minY],
                    "data": data.base64EncodedString(),
                    "keepProportion": true,
                ])
            }
        }
        guard !items.isEmpty else { completion?(); return }

        job("Placing images") { task in
            // drop the live annotations first so they aren't duplicated
            await MainActor.run {
                for i in 0..<doc.document.pageCount {
                    guard let page = doc.document.page(at: i) else { continue }
                    for a in page.annotations where a is ImageStampAnnotation {
                        page.removeAnnotation(a)
                    }
                }
            }
            let input = try await MainActor.run { try doc.stageToTemporaryFile() }
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("riftpdf-img-\(UUID().uuidString).pdf")
            _ = try await Engine.shared.run("place_images", [
                "input": input.path, "output": output.path, "items": items,
            ]) { v, m in task.update(v, m) }
            guard let produced = PDFDocument(url: output) else {
                throw Engine.Failure(message: "Could not place the images.", detail: nil)
            }
            try? FileManager.default.removeItem(at: input)
            return produced
        } onSuccess: { produced in
            doc.replaceDocument(with: produced, actionName: "Place Images")
            completion?()
        }
    }

    var hasPlacedImages: Bool {
        guard let doc = current else { return false }
        for i in 0..<doc.document.pageCount {
            guard let page = doc.document.page(at: i) else { continue }
            if page.annotations.contains(where: { $0 is ImageStampAnnotation }) { return true }
        }
        return false
    }
}
