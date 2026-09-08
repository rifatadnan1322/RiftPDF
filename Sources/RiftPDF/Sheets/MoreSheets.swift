import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - document properties

struct DocumentInfoSheet: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel
    @State private var info: [String: Any] = [:]
    @State private var loading = true

    var body: some View {
        SheetChrome(title: "Document Properties", confirmTitle: nil, width: 520) {
            if loading {
                HStack { ProgressView().controlSize(.small); Text("Inspecting…").font(.system(size: 12)) }
            } else {
                grid([
                    ("Pages", "\(info["pageCount"] as? Int ?? doc.pageCount)"),
                    ("File size", info["fileSizeHuman"] as? String ?? "—"),
                    ("Encrypted", (info["encrypted"] as? Bool ?? false) ? "Yes" : "No"),
                    ("Interactive form", (info["hasForm"] as? Bool ?? false) ? "Yes" : "No"),
                    ("Embedded images", "\(info["imageCount"] as? Int ?? 0)"),
                    ("Bookmarks", "\((info["toc"] as? [[String: Any]] ?? []).count)"),
                ])

                if let meta = info["metadata"] as? [String: String] {
                    let rows = meta.filter { !$0.value.isEmpty }.sorted { $0.key < $1.key }
                    if !rows.isEmpty {
                        Divider()
                        Text("Metadata").font(.system(size: 12, weight: .semibold))
                        grid(rows.map { ($0.key.capitalized, $0.value) })
                    }
                }

                if let fonts = info["fonts"] as? [[String: Any]], !fonts.isEmpty {
                    Divider()
                    Text("Fonts (\(fonts.count))").font(.system(size: 12, weight: .semibold))
                    ForEach(Array(fonts.enumerated()), id: \.offset) { _, font in
                        HStack {
                            Text(font["name"] as? String ?? "—").font(.system(size: 11))
                            Spacer()
                            Text(font["type"] as? String ?? "").font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Text((font["embedded"] as? Bool ?? false) ? "embedded" : "not embedded")
                                .font(.system(size: 9.5))
                                .foregroundStyle((font["embedded"] as? Bool ?? false) ? .green : .orange)
                        }
                    }
                }

                if let pages = info["pages"] as? [[String: Any]], let first = pages.first {
                    Divider()
                    Text(String(format: "First page: %.0f × %.0f pt · rotation %d°",
                                first["width"] as? Double ?? 0,
                                first["height"] as? Double ?? 0,
                                first["rotation"] as? Int ?? 0))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        } confirm: {}
        .task {
            do {
                let input = try doc.stageToTemporaryFile()
                var payload: [String: Any] = ["input": input.path]
                if let pw = doc.password { payload["password"] = pw }
                info = try await Engine.shared.run("info", payload)
                try? FileManager.default.removeItem(at: input)
            } catch {
                app.report(error, context: "Could not inspect the document")
            }
            loading = false
        }
    }

    private func grid(_ rows: [(String, String)]) -> some View {
        VStack(spacing: 5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top) {
                    Text(row.0).font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(width: 130, alignment: .leading)
                    Text(row.1).font(.system(size: 11.5)).textSelection(.enabled)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - forms

struct FormSheet: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel
    @State private var fields: [FormField] = []
    @State private var loading = true
    @State private var flatten = false

    struct FormField: Identifiable {
        let id = UUID()
        let name: String
        let type: String
        let page: Int
        var value: String
        let options: [String]
    }

    var body: some View {
        SheetChrome(title: "Form Fields",
                    subtitle: fields.isEmpty && !loading ? "This PDF has no interactive fields." : nil,
                    confirmTitle: fields.isEmpty ? nil : "Fill Fields",
                    width: 520) {
            if loading {
                HStack { ProgressView().controlSize(.small); Text("Scanning…").font(.system(size: 12)) }
            } else if fields.isEmpty {
                Text("You can still add text with the Add Text tool, then flatten it into the page.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            } else {
                ForEach($fields) { $field in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(field.name.isEmpty ? "(unnamed)" : field.name)
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text("\(field.type) · page \(field.page + 1)")
                                .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                        }
                        if field.type.lowercased().contains("checkbox") {
                            Toggle("Checked", isOn: Binding(
                                get: { !["", "Off", "false", "0"].contains(field.value) },
                                set: { field.value = $0 ? "Yes" : "Off" }
                            )).font(.system(size: 11.5))
                        } else if !field.options.isEmpty {
                            Picker("", selection: $field.value) {
                                ForEach(field.options, id: \.self) { Text($0).tag($0) }
                            }.labelsHidden()
                        } else {
                            TextField("", text: $field.value).textFieldStyle(.roundedBorder)
                        }
                    }
                }
                Toggle("Flatten after filling (locks the values in)", isOn: $flatten)
                    .font(.system(size: 12))
            }
        } confirm: {
            let values = fields.map { ["name": $0.name, "value": $0.value] }
            app.transform(doc, title: "Filling form", command: "form_fill",
                          actionName: "Fill Form",
                          extraPayload: ["values": values, "flatten": flatten]) { res in
                ("Form filled", "\(res["filled"] as? Int ?? 0) fields")
            }
        }
        .task {
            do {
                let input = try doc.stageToTemporaryFile()
                var payload: [String: Any] = ["input": input.path]
                if let pw = doc.password { payload["password"] = pw }
                let res = try await Engine.shared.run("form_fields", payload)
                try? FileManager.default.removeItem(at: input)
                fields = (res["fields"] as? [[String: Any]] ?? []).map {
                    FormField(name: $0["name"] as? String ?? "",
                              type: $0["type"] as? String ?? "text",
                              page: $0["page"] as? Int ?? 0,
                              value: $0["value"] as? String ?? "",
                              options: $0["options"] as? [String] ?? [])
                }
            } catch {
                app.report(error, context: "Could not read the form")
            }
            loading = false
        }
    }
}

// MARK: - attachments

struct AttachmentSheet: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel
    @State private var items: [(index: Int, name: String, size: Int)] = []
    @State private var loading = true

    var body: some View {
        SheetChrome(title: "Attachments", confirmTitle: nil, width: 480) {
            if loading {
                HStack { ProgressView().controlSize(.small); Text("Reading…").font(.system(size: 12)) }
            } else if items.isEmpty {
                Text("No files are embedded in this PDF.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.index) { item in
                    HStack {
                        Image(systemName: "paperclip").foregroundStyle(.secondary)
                        Text(item.name).font(.system(size: 12))
                        Spacer()
                        Text(formatBytes(item.size)).font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                }
                Button("Extract All…") {
                    app.chooseFolder(title: "Where should the attachments go?") { folder in
                        run(["action": "extract", "outputDir": folder.path], reveal: folder)
                    }
                }
                .controlSize(.small)
            }

            Divider()
            Button("Attach Files…") {
                app.chooseFiles(types: [.item], message: "Choose files to embed") { urls in
                    guard !urls.isEmpty else { return }
                    app.transform(doc, title: "Attaching files", command: "attachments",
                                  actionName: "Attach Files",
                                  extraPayload: ["action": "add", "files": urls.map(\.path)]) { _ in
                        ("\(urls.count) file\(urls.count == 1 ? "" : "s") attached", nil)
                    }
                    app.sheet = nil
                }
            }
            .controlSize(.small)
        } confirm: {}
        .task { await load() }
    }

    private func load() async {
        do {
            let input = try doc.stageToTemporaryFile()
            var payload: [String: Any] = ["input": input.path, "action": "list"]
            if let pw = doc.password { payload["password"] = pw }
            let res = try await Engine.shared.run("attachments", payload)
            try? FileManager.default.removeItem(at: input)
            items = (res["attachments"] as? [[String: Any]] ?? []).map {
                ($0["index"] as? Int ?? 0, $0["name"] as? String ?? "?", $0["size"] as? Int ?? 0)
            }
        } catch {
            app.report(error, context: "Could not read attachments")
        }
        loading = false
    }

    private func run(_ extra: [String: Any], reveal: URL?) {
        app.job("Extracting attachments") { task in
            let input = try doc.stageToTemporaryFile()
            var payload: [String: Any] = ["input": input.path]
            payload.merge(extra) { _, new in new }
            if let pw = doc.password { payload["password"] = pw }
            let res = try await Engine.shared.run("attachments", payload) { v, m in task.update(v, m) }
            try? FileManager.default.removeItem(at: input)
            return res
        } onSuccess: { res in
            let n = (res["files"] as? [String] ?? []).count
            app.success("\(n) file\(n == 1 ? "" : "s") extracted", reveal: reveal)
        }
    }
}

// MARK: - bookmarks

struct BookmarkSheet: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel

    struct Entry: Identifiable {
        let id = UUID()
        var level: Int
        var title: String
        var page: Int
    }

    @State private var entries: [Entry] = []

    var body: some View {
        SheetChrome(title: "Bookmarks",
                    subtitle: "Build the table of contents readers see in the sidebar.",
                    confirmTitle: "Save Bookmarks", width: 520) {
            ForEach($entries) { $entry in
                HStack(spacing: 6) {
                    Stepper(value: $entry.level, in: 1...5) {
                        Text("L\(entry.level)").font(.system(size: 10).monospacedDigit())
                            .frame(width: 22)
                    }
                    TextField("Title", text: $entry.title).textFieldStyle(.roundedBorder)
                    Stepper(value: $entry.page, in: 1...max(1, doc.pageCount)) {
                        Text("p\(entry.page)").font(.system(size: 10).monospacedDigit())
                            .frame(width: 32)
                    }
                    Button { entries.removeAll { $0.id == entry.id } } label: {
                        Image(systemName: "minus.circle").font(.system(size: 11))
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.leading, CGFloat(entry.level - 1) * 14)
            }
            Button("Add Bookmark") {
                entries.append(Entry(level: 1, title: "Section \(entries.count + 1)",
                                     page: doc.currentPage + 1))
            }
            .controlSize(.small)
        } confirm: {
            let payload = entries.map { ["level": $0.level, "title": $0.title, "page": $0.page] }
            app.transform(doc, title: "Saving bookmarks", command: "bookmarks_set",
                          actionName: "Set Bookmarks", extraPayload: ["bookmarks": payload]) { res in
                ("Bookmarks saved", "\(res["count"] as? Int ?? 0) entries")
            }
        }
        .onAppear {
            guard entries.isEmpty, let root = doc.document.outlineRoot else { return }
            var stack: [(PDFOutline, Int)] = [(root, 0)]
            var collected: [Entry] = []
            while let (node, depth) = stack.popLast() {
                for i in stride(from: node.numberOfChildren - 1, through: 0, by: -1) {
                    guard let child = node.child(at: i) else { continue }
                    stack.append((child, depth + 1))
                }
                if depth > 0 {
                    let page = node.destination?.page.flatMap { doc.document.index(for: $0) } ?? 0
                    collected.append(Entry(level: depth, title: node.label ?? "", page: page + 1))
                }
            }
            entries = collected.sorted { $0.page < $1.page }
        }
    }
}

// MARK: - compare

struct CompareSheet: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel
    @State private var other: URL?
    @State private var pages: [[String: Any]] = []
    @State private var running = false
    @State private var identical: Bool?

    var body: some View {
        SheetChrome(title: "Compare Documents",
                    subtitle: "Word-level differences against another PDF.",
                    confirmTitle: nil, width: 560) {
            HStack {
                Text(other?.lastPathComponent ?? "No file chosen")
                    .font(.system(size: 12))
                    .foregroundStyle(other == nil ? .secondary : .primary)
                Spacer()
                Button("Choose PDF…") {
                    app.chooseFiles(types: [.pdf], multiple: false,
                                    message: "Compare against which PDF?") { other = $0.first }
                }
                .controlSize(.small)
                Button("Compare") { compare() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(other == nil || running)
            }

            if running {
                HStack { ProgressView().controlSize(.small); Text("Comparing…").font(.system(size: 12)) }
            }

            if identical == true {
                Label("The text of both documents is identical.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(.green)
            }

            ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                let changes = page["changes"] as? [[String: Any]] ?? []
                if !changes.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Page \((page["page"] as? Int ?? 0) + 1) · \(Int((page["similarity"] as? Double ?? 0) * 100))% similar")
                            .font(.system(size: 11, weight: .semibold))
                        ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                            VStack(alignment: .leading, spacing: 2) {
                                if let before = change["before"] as? String, !before.isEmpty {
                                    Text(before).font(.system(size: 11))
                                        .foregroundStyle(.red)
                                        .strikethrough()
                                }
                                if let after = change["after"] as? String, !after.isEmpty {
                                    Text(after).font(.system(size: 11)).foregroundStyle(.green)
                                }
                            }
                            .padding(6)
                            .background(Color.primary.opacity(0.04),
                                        in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
            }
        } confirm: {}
    }

    private func compare() {
        guard let other else { return }
        running = true
        Task {
            defer { running = false }
            do {
                let input = try doc.stageToTemporaryFile()
                let res = try await Engine.shared.run("compare", [
                    "inputA": input.path, "inputB": other.path,
                ])
                try? FileManager.default.removeItem(at: input)
                pages = res["pages"] as? [[String: Any]] ?? []
                identical = res["identical"] as? Bool
            } catch {
                app.report(error, context: "Comparison failed")
            }
        }
    }
}

// MARK: - preferences

struct PreferencesSheet: View {
    @EnvironmentObject var app: AppModel
    @State private var caps = Engine.shared.capabilities

    var body: some View {
        SheetChrome(title: "RiftPDF", subtitle: "Local PDF editing. Nothing is uploaded anywhere.",
                    confirmTitle: nil, width: 500) {
            Text("Default PDF reader").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 10) {
                Image(systemName: app.isDefaultPDFReader ? "checkmark.seal.fill" : "doc.badge.gearshape")
                    .foregroundStyle(app.isDefaultPDFReader ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.isDefaultPDFReader
                         ? "RiftPDF opens PDFs from Finder"
                         : "PDFs currently open in \(app.currentPDFReaderName)")
                        .font(.system(size: 11.5))
                    if !app.isDefaultPDFReader {
                        Text("macOS will ask you to confirm the change.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if !app.isDefaultPDFReader {
                    Button("Make Default") { app.requestDefaultPDFReader() }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                }
            }

            Divider()

            Text("Engine").font(.system(size: 12, weight: .semibold))
            row("Status", caps.ready ? "Ready" : "Not responding", ok: caps.ready)
            row("MuPDF", caps.pymupdf.isEmpty ? "—" : caps.pymupdf, ok: !caps.pymupdf.isEmpty)
            row("pikepdf", caps.pikepdf.isEmpty ? "—" : caps.pikepdf, ok: !caps.pikepdf.isEmpty)
            row("Ghostscript", caps.ghostscript ? "Installed" : "Not installed", ok: caps.ghostscript)
            row("qpdf", caps.qpdf ? "Installed" : "Not installed", ok: caps.qpdf)
            row("LibreOffice", caps.libreOffice ? "Installed" : "Not installed", ok: caps.libreOffice)

            if !caps.libreOffice {
                Text("Word documents convert through macOS's own typesetter, which handles text, styles and images well but won't reproduce complex Word layouts exactly. Installing LibreOffice adds pixel-faithful conversion:")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                HStack {
                    Text("brew install --cask libreoffice")
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 5))
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install --cask libreoffice", forType: .string)
                        app.success("Copied", "Paste it into Terminal.")
                    } label: { Image(systemName: "doc.on.doc").font(.system(size: 11)) }
                    .buttonStyle(.plain)
                }
            }

            Divider()
            Text("Engine location").font(.system(size: 12, weight: .semibold))
            Text(Engine.shared.engineRootDescription)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary).textSelection(.enabled)
        } confirm: {}
        .task { await Engine.shared.probe(); caps = Engine.shared.capabilities }
    }

    private func row(_ label: String, _ value: String, ok: Bool) -> some View {
        HStack {
            Circle().fill(ok ? Color.green : Color.orange).frame(width: 6, height: 6)
            Text(label).font(.system(size: 11.5)).frame(width: 110, alignment: .leading)
            Text(value).font(.system(size: 11.5)).foregroundStyle(.secondary)
            Spacer()
        }
    }
}
