import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - compress

struct CompressSheet: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel
    @AppStorage("compressMode") private var mode = "preset"
    @State private var targetValue: Double = 500
    @State private var targetUnit = "KB"
    @State private var allowGrayscale = true
    @State private var preset = "balanced"
    @State private var dpi: Double = 150
    @State private var quality: Double = 72
    @State private var grayscale = false
    @State private var stripMetadata = false
    @State private var flatten = false
    @State private var inPlace = true

    private let presets: [(String, String, String)] = [
        ("light", "Light", "Barely any visible change — good for print"),
        ("balanced", "Balanced", "The usual choice: small file, still crisp on screen"),
        ("aggressive", "Aggressive", "Noticeably smaller, fine for email and web"),
        ("extreme", "Maximum", "Smallest possible; images will soften"),
    ]

    var body: some View {
        SheetChrome(title: "Shrink File Size",
                    subtitle: currentSize,
                    confirmTitle: mode == "target" ? "Compress to \(targetLabel)" : "Compress",
                    confirmDisabled: mode == "target" && targetBytes <= 0) {
            Picker("", selection: $mode) {
                Text("Pick a quality").tag("preset")
                Text("Pick a size").tag("target")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if mode == "target" {
                VStack(alignment: .leading, spacing: 10) {
                    Text("RiftPDF tries progressively harder settings and keeps the best quality that still fits.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text("Get it under")
                            .font(.system(size: 12))
                        TextField("", value: $targetValue, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 78)
                            .multilineTextAlignment(.trailing)
                        Picker("", selection: $targetUnit) {
                            Text("KB").tag("KB")
                            Text("MB").tag("MB")
                        }
                        .labelsHidden()
                        .frame(width: 72)
                        Spacer()
                    }

                    HStack(spacing: 5) {
                        ForEach(quickTargets, id: \.0) { label, value, unit in
                            Button(label) { targetValue = value; targetUnit = unit }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                        }
                    }

                    if let source = sourceBytes, targetBytes > 0 {
                        if targetBytes >= source {
                            Label("That's already bigger than this file — nothing will be resampled.",
                                  systemImage: "info.circle")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("A \(Int(100 - Double(targetBytes) / Double(source) * 100))% reduction from \(formatBytes(source)).")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Toggle("Allow greyscale if colour won't fit", isOn: $allowGrayscale)
                        .font(.system(size: 12))
                    Toggle("Remove metadata while compressing", isOn: $stripMetadata)
                        .font(.system(size: 12))
                }
            } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(presets, id: \.0) { key, name, blurb in
                    Button {
                        preset = key
                        applyPresetDefaults(key)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: preset == key ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(preset == key ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).font(.system(size: 12.5, weight: .medium))
                                Text(blurb).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            DisclosureGroup("Fine tuning") {
                VStack(alignment: .leading, spacing: 12) {
                    labelled("Image resolution", "\(Int(dpi)) dpi") {
                        Slider(value: $dpi, in: 50...300, step: 10)
                    }
                    labelled("JPEG quality", "\(Int(quality))") {
                        Slider(value: $quality, in: 25...95, step: 1)
                    }
                    Toggle("Convert images to greyscale", isOn: $grayscale)
                    Toggle("Remove metadata while compressing", isOn: $stripMetadata)
                    Toggle("Flatten markup into the page", isOn: $flatten)
                }
                .padding(.top, 8)
                .font(.system(size: 12))
            }
            .font(.system(size: 12, weight: .medium))
            }

            Picker("", selection: $inPlace) {
                Text("Replace the open document").tag(true)
                Text("Save a compressed copy…").tag(false)
            }
            .pickerStyle(.radioGroup)
            .font(.system(size: 12))
        } confirm: {
            if mode == "target" {
                app.compressToTarget(doc, targetBytes: targetBytes,
                                     allowGrayscale: allowGrayscale,
                                     stripMetadata: stripMetadata, inPlace: inPlace)
            } else {
                app.compress(doc, preset: preset, dpi: Int(dpi), quality: Int(quality),
                             grayscale: grayscale, stripMetadata: stripMetadata,
                             flatten: flatten, inPlace: inPlace)
            }
        }
    }

    private let quickTargets: [(String, Double, String)] = [
        ("100 KB", 100, "KB"), ("250 KB", 250, "KB"), ("500 KB", 500, "KB"),
        ("1 MB", 1, "MB"), ("2 MB", 2, "MB"), ("5 MB", 5, "MB"),
    ]

    private var targetBytes: Int {
        Int(targetValue * (targetUnit == "MB" ? 1_048_576 : 1024))
    }

    private var targetLabel: String {
        targetValue == targetValue.rounded()
            ? "\(Int(targetValue)) \(targetUnit)"
            : String(format: "%.1f %@", targetValue, targetUnit)
    }

    private var sourceBytes: Int? {
        guard let url = doc.url else { return nil }
        return try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
    }

    private var currentSize: String {
        guard let url = doc.url,
              let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        else { return "\(doc.pageCount) pages" }
        return "Currently \(formatBytes(size)) · \(doc.pageCount) pages"
    }

    private func applyPresetDefaults(_ key: String) {
        switch key {
        case "light": dpi = 200; quality = 85
        case "balanced": dpi = 150; quality = 72
        case "aggressive": dpi = 110; quality = 58
        default: dpi = 72; quality = 42
        }
    }

    private func labelled<V: View>(_ title: String, _ value: String,
                                   @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 11.5))
                Spacer()
                Text(value).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
            content()
        }
    }
}

// MARK: - metadata

struct MetadataSheet: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel
    @State private var title = ""
    @State private var author = ""
    @State private var subject = ""
    @State private var keywords = ""
    @State private var creator = ""
    @State private var producer = ""
    @State private var removeAttachments = false
    @State private var resetID = true

    var body: some View {
        SheetChrome(title: "Metadata", subtitle: "Edit what the file says about itself — or erase it entirely.",
                    confirmTitle: "Save Metadata") {
            Field("Title") { TextField("", text: $title).textFieldStyle(.roundedBorder) }
            Field("Author") { TextField("", text: $author).textFieldStyle(.roundedBorder) }
            Field("Subject") { TextField("", text: $subject).textFieldStyle(.roundedBorder) }
            Field("Keywords") { TextField("", text: $keywords).textFieldStyle(.roundedBorder) }
            Field("Creator") { TextField("", text: $creator).textFieldStyle(.roundedBorder) }
            Field("Producer") { TextField("", text: $producer).textFieldStyle(.roundedBorder) }

            Divider()

            Text("Erase everything")
                .font(.system(size: 12, weight: .semibold))
            Text("Removes the document info dictionary, the XMP stream, annotation author names and the trailer ID — the traces that survive a normal \u{201C}save as\u{201D}.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Toggle("Also remove embedded attachments", isOn: $removeAttachments)
                .font(.system(size: 12))
            Toggle("Reset the document ID", isOn: $resetID)
                .font(.system(size: 12))
            Button(role: .destructive) {
                app.stripMetadata(doc, removeAttachments: removeAttachments, resetID: resetID)
                app.sheet = nil
            } label: {
                Label("Remove All Metadata", systemImage: "eye.slash")
            }
            .controlSize(.small)
        } confirm: {
            app.applyMetadata(doc, values: [
                "title": title, "author": author, "subject": subject,
                "keywords": keywords, "creator": creator, "producer": producer,
            ])
        }
        .onAppear(perform: load)
    }

    private func load() {
        let attrs = doc.document.documentAttributes ?? [:]
        title = attrs[PDFDocumentAttribute.titleAttribute] as? String ?? ""
        author = attrs[PDFDocumentAttribute.authorAttribute] as? String ?? ""
        subject = attrs[PDFDocumentAttribute.subjectAttribute] as? String ?? ""
        if let words = attrs[PDFDocumentAttribute.keywordsAttribute] as? [String] {
            keywords = words.joined(separator: ", ")
        } else {
            keywords = attrs[PDFDocumentAttribute.keywordsAttribute] as? String ?? ""
        }
        creator = attrs[PDFDocumentAttribute.creatorAttribute] as? String ?? ""
        producer = attrs[PDFDocumentAttribute.producerAttribute] as? String ?? ""
    }
}

// MARK: - watermark

struct WatermarkSheet: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel
    @State private var text = "DRAFT"
    @State private var fontSize: Double = 0
    @State private var opacity: Double = 0.18
    @State private var rotation: Double = 45
    @State private var color = Color(red: 0.55, green: 0.55, blue: 0.62)
    @State private var pages = "all"
    @State private var onTop = true
    @State private var useImage = false
    @State private var imagePath: String?
    @State private var scale: Double = 0.5

    var body: some View {
        SheetChrome(title: "Watermark",
                    confirmTitle: "Add Watermark",
                    confirmDisabled: useImage ? imagePath == nil : text.isEmpty) {
            Picker("", selection: $useImage) {
                Text("Text").tag(false)
                Text("Image").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if useImage {
                HStack {
                    Text(imagePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No image chosen")
                        .font(.system(size: 11.5))
                        .foregroundStyle(imagePath == nil ? .secondary : .primary)
                    Spacer()
                    Button("Choose…") {
                        app.chooseFiles(types: [.image], multiple: false,
                                        message: "Choose a watermark image") { urls in
                            imagePath = urls.first?.path
                        }
                    }
                    .controlSize(.small)
                }
                slider("Size", $scale, 0.1...1.0, format: { "\(Int($0 * 100))% of page width" })
            } else {
                Field("Text") { TextField("", text: $text).textFieldStyle(.roundedBorder) }
                HStack {
                    Field("Colour") { ColorPicker("", selection: $color).labelsHidden() }
                    Spacer()
                    Field("Rotation") {
                        Picker("", selection: $rotation) {
                            Text("0°").tag(0.0); Text("45°").tag(45.0)
                            Text("90°").tag(90.0); Text("270°").tag(270.0)
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                }
                slider("Text size", $fontSize, 0...160,
                       format: { $0 == 0 ? "Fit to page" : "\(Int($0)) pt" })
            }

            slider("Opacity", $opacity, 0.03...1.0, format: { "\(Int($0 * 100))%" })
            Field("Pages") {
                TextField("all, or 1-3,7", text: $pages).textFieldStyle(.roundedBorder)
            }
            Toggle("Draw on top of the content", isOn: $onTop).font(.system(size: 12))
        } confirm: {
            if useImage, let path = imagePath {
                app.imageWatermark(doc, imagePath: path, scale: scale,
                                   opacity: opacity, pages: pages, onTop: onTop)
            } else {
                app.watermark(doc, text: text, fontSize: fontSize, opacity: opacity,
                              rotation: rotation, color: color, pages: pages, onTop: onTop)
            }
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>,
                        _ range: ClosedRange<Double>,
                        format: @escaping (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 11.5))
                Spacer()
                Text(format(value.wrappedValue))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}

// MARK: - page numbers

struct PageNumberSheet: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel
    @State private var format = "{n}"
    @State private var position = "bottom-center"
    @State private var startAt = 1
    @State private var fontSize: Double = 10
    @State private var margin: Double = 32
    @State private var color = Color(white: 0.25)
    @State private var pages = "all"

    private let positions = [
        ("top-left", "Top left"), ("top-center", "Top centre"), ("top-right", "Top right"),
        ("bottom-left", "Bottom left"), ("bottom-center", "Bottom centre"), ("bottom-right", "Bottom right"),
    ]

    var body: some View {
        SheetChrome(title: "Page Numbers", confirmTitle: "Add Numbers") {
            Field("Format") {
                VStack(alignment: .leading, spacing: 5) {
                    TextField("", text: $format).textFieldStyle(.roundedBorder)
                    Text("{n} number · {total} total · {page} physical page · {filename} file name")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 5) {
                        ForEach(["{n}", "Page {n}", "{n} of {total}", "— {n} —"], id: \.self) { preset in
                            Button(preset) { format = preset }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                        }
                    }
                }
            }
            Field("Position") {
                Picker("", selection: $position) {
                    ForEach(positions, id: \.0) { Text($0.1).tag($0.0) }
                }
                .labelsHidden()
            }
            HStack(spacing: 16) {
                Field("Start at") {
                    Stepper(value: $startAt, in: 0...9999) {
                        Text("\(startAt)").font(.system(size: 12).monospacedDigit())
                    }
                }
                Field("Size") {
                    Stepper(value: $fontSize, in: 6...36) {
                        Text("\(Int(fontSize)) pt").font(.system(size: 12).monospacedDigit())
                    }
                }
                Field("Colour") { ColorPicker("", selection: $color).labelsHidden() }
            }
            Field("Margin") {
                HStack {
                    Slider(value: $margin, in: 12...96)
                    Text("\(Int(margin)) pt").font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary).frame(width: 44)
                }
            }
            Field("Pages") { TextField("all, or 2-", text: $pages).textFieldStyle(.roundedBorder) }
        } confirm: {
            app.addPageNumbers(doc, format: format, position: position, startAt: startAt,
                               fontSize: fontSize, margin: margin, color: color, pages: pages)
        }
    }
}

// MARK: - security

struct SecuritySheet: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel
    @State private var userPassword = ""
    @State private var ownerPassword = ""
    @State private var permissions: [String: Bool] = [
        "print": true, "printHighRes": true, "copy": true, "modify": false,
        "annotate": true, "fillForms": true, "assemble": false, "accessibility": true,
    ]

    private let labels: [(String, String)] = [
        ("print", "Printing"), ("printHighRes", "High-resolution printing"),
        ("copy", "Copying text and images"), ("modify", "Changing the document"),
        ("annotate", "Adding comments and markup"), ("fillForms", "Filling in form fields"),
        ("assemble", "Inserting, deleting and rotating pages"),
        ("accessibility", "Screen reader access"),
    ]

    var body: some View {
        SheetChrome(title: "Password and Permissions",
                    subtitle: "AES-256 encryption.",
                    confirmTitle: "Protect",
                    confirmDisabled: userPassword.isEmpty && ownerPassword.isEmpty) {
            Field("Password to open the document") {
                SecureField("leave blank to let anyone open it", text: $userPassword)
                    .textFieldStyle(.roundedBorder)
            }
            Field("Owner password (to change permissions)") {
                SecureField("recommended", text: $ownerPassword).textFieldStyle(.roundedBorder)
            }

            Divider()
            Text("Allow").font(.system(size: 12, weight: .semibold))
            ForEach(labels, id: \.0) { key, label in
                Toggle(label, isOn: Binding(
                    get: { permissions[key] ?? true },
                    set: { permissions[key] = $0 }
                ))
                .font(.system(size: 12))
            }

            if doc.document.isEncrypted {
                Divider()
                Button(role: .destructive) {
                    app.decrypt(doc)
                    app.sheet = nil
                } label: {
                    Label("Remove Existing Protection", systemImage: "lock.open")
                }
                .controlSize(.small)
            }
        } confirm: {
            app.encrypt(doc, userPassword: userPassword,
                        ownerPassword: ownerPassword.isEmpty ? userPassword : ownerPassword,
                        permissions: permissions)
        }
    }
}

// MARK: - export images

struct ExportImagesSheet: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel
    @State private var dpi: Double = 200
    @State private var format = "png"
    @State private var pages = "all"

    var body: some View {
        SheetChrome(title: "Export Pages as Images", confirmTitle: "Choose Folder…") {
            Field("Format") {
                Picker("", selection: $format) {
                    Text("PNG").tag("png"); Text("JPEG").tag("jpg"); Text("TIFF").tag("tiff")
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            Field("Resolution") {
                HStack {
                    Slider(value: $dpi, in: 72...600, step: 6)
                    Text("\(Int(dpi)) dpi").font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary).frame(width: 60)
                }
            }
            Field("Pages") { TextField("all, or 1-5", text: $pages).textFieldStyle(.roundedBorder) }
        } confirm: {
            app.exportImages(doc, dpi: Int(dpi), format: format, pages: pages)
        }
    }
}

// MARK: - split

struct SplitSheet: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel
    @State private var mode = "every"
    @State private var every = 1
    @State private var ranges = "1-3, 4-6"

    var body: some View {
        SheetChrome(title: "Split Document",
                    subtitle: "\(doc.pageCount) pages",
                    confirmTitle: "Choose Folder…") {
            Picker("", selection: $mode) {
                Text("Every N pages").tag("every")
                Text("Custom ranges").tag("ranges")
                Text("One file per page").tag("each")
            }
            .pickerStyle(.radioGroup).labelsHidden().font(.system(size: 12))

            if mode == "every" {
                Field("Pages per file") {
                    Stepper(value: $every, in: 1...500) {
                        Text("\(every)").font(.system(size: 12).monospacedDigit())
                    }
                }
            } else if mode == "ranges" {
                Field("Ranges") {
                    TextField("1-3, 4-6, 7-", text: $ranges).textFieldStyle(.roundedBorder)
                }
            }
        } confirm: {
            let list = ranges.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            app.splitDocument(doc, mode: mode, every: every, ranges: list)
        }
    }
}

// MARK: - OCR

struct OCRSheet: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel
    @State private var scope = "all"
    @State private var language = "en-US"
    @State private var fast = false

    var body: some View {
        SheetChrome(title: "Recognise Text",
                    subtitle: "Adds an invisible, searchable text layer using Apple's on-device recognition. Nothing leaves your Mac.",
                    confirmTitle: "Recognise") {
            Field("Pages") {
                Picker("", selection: $scope) {
                    Text("Every page").tag("all")
                    Text("This page only").tag("current")
                }
                .pickerStyle(.radioGroup).labelsHidden().font(.system(size: 12))
            }
            Field("Language") {
                Picker("", selection: $language) {
                    ForEach(OCRService.availableLanguages, id: \.self) { code in
                        Text(Locale.current.localizedString(forIdentifier: code) ?? code).tag(code)
                    }
                }
                .labelsHidden()
            }
            Toggle("Fast mode (less accurate)", isOn: $fast).font(.system(size: 12))
            Text("Accurate mode takes roughly a second per page.")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        } confirm: {
            let pages = scope == "all" ? Array(0..<doc.pageCount) : [doc.currentPage]
            app.runOCR(doc, pages: pages, languages: [language], fast: fast)
        }
    }
}

// MARK: - merge

struct MergeSheet: View {
    @EnvironmentObject var app: AppModel
    @State private var files: [URL] = []
    @State private var bookmarks = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetChrome(title: "Combine PDFs",
                    subtitle: "Drag to reorder. The result opens in a new tab.",
                    confirmTitle: "Combine \(files.count) Files",
                    confirmDisabled: files.count < 2,
                    width: 520) {
            if files.isEmpty {
                Button {
                    app.chooseFiles(types: [.pdf], message: "Choose PDFs to combine") { files += $0 }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.down.right")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("Add PDFs…").font(.system(size: 12))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundStyle(.tertiary))
                }
                .buttonStyle(.plain)
            } else {
                List {
                    ForEach(Array(files.enumerated()), id: \.element) { index, url in
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 18)
                            Image(systemName: "doc.richtext").foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(url.lastPathComponent).font(.system(size: 12))
                                Text("\(PDFDocument(url: url)?.pageCount ?? 0) pages")
                                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button { files.removeAll { $0 == url } } label: {
                                Image(systemName: "minus.circle").font(.system(size: 11))
                            }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                    }
                    .onMove { files.move(fromOffsets: $0, toOffset: $1) }
                }
                .frame(height: 220)
                HStack {
                    Button("Add More…") {
                        app.chooseFiles(types: [.pdf], message: "Choose PDFs to combine") { files += $0 }
                    }
                    .controlSize(.small)
                    Spacer()
                    Text("\(files.reduce(0) { $0 + (PDFDocument(url: $1)?.pageCount ?? 0) }) pages total")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Toggle("Add a bookmark for each file", isOn: $bookmarks).font(.system(size: 12))
            }
        } confirm: {
            app.mergeFiles(files, bookmarkPerFile: bookmarks)
        }
    }
}

// MARK: - images to PDF

struct ImagesToPDFSheet: View {
    @EnvironmentObject var app: AppModel
    @State private var files: [URL] = []
    @State private var pageSize = "auto"
    @State private var fit = "fit"
    @State private var margin: Double = 0
    @State private var quality: Double = 88

    var body: some View {
        SheetChrome(title: "Images to PDF",
                    confirmTitle: "Create PDF",
                    confirmDisabled: files.isEmpty,
                    width: 520) {
            if files.isEmpty {
                Button {
                    app.chooseFiles(types: [.image], message: "Choose images") { files += $0 }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 26, weight: .light)).foregroundStyle(.tertiary)
                        Text("Add images…").font(.system(size: 12))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 34)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundStyle(.tertiary))
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(files, id: \.self) { url in
                            VStack(spacing: 3) {
                                if let image = NSImage(contentsOf: url) {
                                    Image(nsImage: image)
                                        .resizable().aspectRatio(contentMode: .fill)
                                        .frame(width: 64, height: 64).clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                }
                                Text(url.lastPathComponent)
                                    .font(.system(size: 8)).lineLimit(1).frame(width: 64)
                            }
                            .overlay(alignment: .topTrailing) {
                                Button { files.removeAll { $0 == url } } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                                }
                                .buttonStyle(.plain).padding(2)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                HStack {
                    Button("Add More…") {
                        app.chooseFiles(types: [.image], message: "Choose images") { files += $0 }
                    }.controlSize(.small)
                    Button("Clear") { files = [] }.controlSize(.small)
                    Spacer()
                    Text("\(files.count) images").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Field("Page size") {
                    Picker("", selection: $pageSize) {
                        Text("Match each image").tag("auto")
                        Text("Letter").tag("letter"); Text("A4").tag("a4")
                        Text("Legal").tag("legal"); Text("Tabloid").tag("tabloid")
                    }.labelsHidden()
                }
                if pageSize != "auto" {
                    Field("Scaling") {
                        Picker("", selection: $fit) {
                            Text("Fit inside").tag("fit")
                            Text("Fill the page").tag("fill-page")
                        }.pickerStyle(.segmented).labelsHidden()
                    }
                    Field("Margin") {
                        HStack {
                            Slider(value: $margin, in: 0...90)
                            Text("\(Int(margin)) pt").font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary).frame(width: 44)
                        }
                    }
                }
                Field("Image quality") {
                    HStack {
                        Slider(value: $quality, in: 40...100)
                        Text("\(Int(quality))").font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary).frame(width: 30)
                    }
                }
            }
        } confirm: {
            app.imagesToPDF(files, pageSize: pageSize, fit: fit, margin: margin, quality: Int(quality))
        }
    }
}
