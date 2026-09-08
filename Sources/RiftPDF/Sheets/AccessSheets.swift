import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - accessibility checker

struct AccessibilitySheet: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel

    @State private var loading = true
    @State private var issues: [Issue] = []
    @State private var score = 0
    @State private var tagged = false
    @State private var fixable: [String] = []
    @State private var title = ""
    @State private var language = "en-US"
    @State private var selected: Set<String> = []

    struct Issue: Identifiable {
        let id = UUID()
        let severity: String
        let title: String
        let detail: String
        let fixable: Bool
        let rule: String
    }

    private let languages = ["en-US", "en-GB", "fr-FR", "de-DE", "es-ES", "it-IT",
                             "pt-BR", "nl-NL", "sv-SE", "bn-BD", "hi-IN", "ar-SA",
                             "zh-Hans", "ja-JP", "ko-KR"]

    var body: some View {
        SheetChrome(title: "Accessibility Check",
                    subtitle: loading ? "Auditing the document…"
                                      : "Score \(score) of 100 · \(issues.filter { $0.severity == "error" }.count) errors, \(issues.filter { $0.severity == "warning" }.count) warnings",
                    confirmTitle: selected.isEmpty ? nil : "Fix \(selected.count) Selected",
                    width: 560) {
            if loading {
                HStack { ProgressView().controlSize(.small); Text("Checking…").font(.system(size: 12)) }
            } else if issues.isEmpty {
                Label("No accessibility problems found.", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
            } else {
                scoreBar

                ForEach(issues) { issue in
                    HStack(alignment: .top, spacing: 10) {
                        if issue.fixable {
                            Toggle("", isOn: Binding(
                                get: { selected.contains(issue.rule) },
                                set: { on in
                                    if on { selected.insert(issue.rule) }
                                    else { selected.remove(issue.rule) }
                                }
                            ))
                            .labelsHidden()
                            .accessibilityLabel("Fix: \(issue.title)")
                        } else {
                            Image(systemName: "minus")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .frame(width: 16)
                        }

                        Image(systemName: issue.severity == "error"
                              ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(issue.severity == "error" ? .red : .orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title).font(.system(size: 12.5, weight: .medium))
                            Text(issue.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !issue.fixable {
                                Text(issue.rule == "ocr" ? "" : "Cannot be fixed automatically")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 3)
                }

                if selected.contains("title") {
                    Field("Document title") {
                        TextField("A short, descriptive title", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                if selected.contains("lang") {
                    Field("Document language") {
                        Picker("", selection: $language) {
                            ForEach(languages, id: \.self) { code in
                                Text(Locale.current.localizedString(forIdentifier: code) ?? code)
                                    .tag(code)
                            }
                        }
                        .labelsHidden()
                    }
                }

                if issues.contains(where: { $0.rule == "ocr" }) {
                    Button {
                        app.sheet = .ocr
                    } label: {
                        Label("Recognise text on the scanned pages…", systemImage: "text.viewfinder")
                    }
                    .controlSize(.small)
                }

                if !tagged {
                    Divider()
                    Text("About tagging")
                        .font(.system(size: 12, weight: .semibold))
                    Text("A fully accessible PDF needs a structure tree — headings, lists, table headers and reading order marked up in the file. RiftPDF can set the title, language and viewer hints, but it will not fabricate a structure tree, because guessed structure is worse than none: it makes a document *claim* to be accessible when it isn't. Authoring the document accessibly in Word or InDesign and exporting with tags is the reliable path.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } confirm: {
            app.fixAccessibility(doc, rules: Array(selected), title: title, language: language)
        }
        .task { await load() }
    }

    private var scoreBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(score >= 80 ? Color.green : score >= 50 ? Color.orange : Color.red)
                        .frame(width: geo.size.width * CGFloat(score) / 100)
                }
            }
            .frame(height: 7)
            Text("Higher is better. Acrobat scores the same checks; a perfect score still needs a human to confirm reading order makes sense.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .accessibilityLabel("Accessibility score \(score) out of 100")
    }

    private func load() async {
        do {
            let res = try await app.checkAccessibility(doc)
            score = res["score"] as? Int ?? 0
            tagged = res["tagged"] as? Bool ?? false
            fixable = res["fixable"] as? [String] ?? []
            issues = (res["issues"] as? [[String: Any]] ?? []).map {
                Issue(severity: $0["severity"] as? String ?? "warning",
                      title: $0["title"] as? String ?? "",
                      detail: $0["detail"] as? String ?? "",
                      fixable: $0["fixable"] as? Bool ?? false,
                      rule: $0["rule"] as? String ?? "")
            }
            selected = Set(fixable.filter { $0 != "ocr" && $0 != "permissions" })
            title = (doc.document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)
                ?? doc.displayName
        } catch {
            app.report(error, context: "Accessibility check failed")
        }
        loading = false
    }
}

// MARK: - headers, footers and Bates numbering

struct HeaderFooterSheet: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel

    @State private var headerLeft = ""
    @State private var headerCenter = ""
    @State private var headerRight = ""
    @State private var footerLeft = ""
    @State private var footerCenter = "Page {n} of {total}"
    @State private var footerRight = ""
    @State private var fontSize: Double = 9
    @State private var margin: Double = 28
    @State private var color = Color(white: 0.25)
    @State private var pages = "all"
    @State private var startAt = 1
    @State private var useBates = false
    @State private var batesPrefix = ""
    @State private var batesStart = 1
    @State private var batesDigits = 6

    var body: some View {
        SheetChrome(title: "Headers and Footers",
                    subtitle: "Tokens: {n} {total} {page} {date} {time} {filename} {bates}",
                    confirmTitle: "Apply", width: 560) {
            band("Header", $headerLeft, $headerCenter, $headerRight)
            band("Footer", $footerLeft, $footerCenter, $footerRight)

            Divider()

            Toggle("Bates numbering (for legal filings)", isOn: $useBates)
                .font(.system(size: 12))
            if useBates {
                HStack(spacing: 12) {
                    Field("Prefix") {
                        TextField("SMITH-", text: $batesPrefix)
                            .textFieldStyle(.roundedBorder).frame(width: 100)
                    }
                    Field("Start at") {
                        TextField("", value: $batesStart, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 70)
                    }
                    Field("Digits") {
                        Stepper(value: $batesDigits, in: 3...10) {
                            Text("\(batesDigits)").font(.system(size: 11).monospacedDigit())
                        }
                    }
                }
                Text("Insert {bates} into any field above. Preview: \(batesPreview)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Button("Put {bates} in the bottom right") { footerRight = "{bates}" }
                    .controlSize(.mini)
            }

            Divider()

            HStack(spacing: 14) {
                Field("Size") {
                    Stepper(value: $fontSize, in: 6...24) {
                        Text("\(Int(fontSize)) pt").font(.system(size: 11).monospacedDigit())
                    }
                }
                Field("Margin") {
                    Stepper(value: $margin, in: 10...90, step: 2) {
                        Text("\(Int(margin)) pt").font(.system(size: 11).monospacedDigit())
                    }
                }
                Field("Colour") { ColorPicker("", selection: $color).labelsHidden() }
                Field("First number") {
                    TextField("", value: $startAt, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 60)
                }
            }
            Field("Pages") { TextField("all, or 2-", text: $pages).textFieldStyle(.roundedBorder) }
        } confirm: {
            app.applyHeaderFooter(
                doc,
                header: ["left": headerLeft, "center": headerCenter, "right": headerRight],
                footer: ["left": footerLeft, "center": footerCenter, "right": footerRight],
                fontSize: fontSize, margin: margin, color: color, pages: pages,
                startAt: startAt,
                batesPrefix: useBates ? batesPrefix : "",
                batesStart: batesStart, batesDigits: batesDigits)
        }
    }

    private var batesPreview: String {
        batesPrefix + String(batesStart).padding(toLength: max(String(batesStart).count, 0),
                                                 withPad: "0", startingAt: 0)
            .leftPadded(to: batesDigits)
    }

    private func band(_ label: String, _ left: Binding<String>,
                      _ center: Binding<String>, _ right: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12, weight: .semibold))
            HStack(spacing: 6) {
                TextField("Left", text: left).textFieldStyle(.roundedBorder)
                TextField("Centre", text: center).textFieldStyle(.roundedBorder)
                TextField("Right", text: right).textFieldStyle(.roundedBorder)
            }
            .font(.system(size: 11.5))
        }
    }
}

extension String {
    func leftPadded(to width: Int, with pad: Character = "0") -> String {
        count >= width ? self : String(repeating: pad, count: width - count) + self
    }
}

// MARK: - audit space usage

struct AuditSpaceSheet: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel
    @State private var rows: [(String, String, Double, Int)] = []
    @State private var total = ""
    @State private var loading = true

    var body: some View {
        SheetChrome(title: "Where the Space Goes",
                    subtitle: loading ? nil : "Total \(total)",
                    confirmTitle: nil, width: 520) {
            if loading {
                HStack { ProgressView().controlSize(.small); Text("Measuring…").font(.system(size: 12)) }
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(row.0).font(.system(size: 12))
                            Spacer()
                            Text(row.1).font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text("\(row.2, specifier: "%.1f")%")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 46, alignment: .trailing)
                        }
                        GeometryReader { geo in
                            Capsule()
                                .fill(Color.accentColor.opacity(0.75))
                                .frame(width: max(2, geo.size.width * row.2 / 100))
                        }
                        .frame(height: 5)
                    }
                    .accessibilityElement(children: .combine)
                }

                if let biggest = rows.first, biggest.0 == "Images", biggest.2 > 60 {
                    Divider()
                    Label("Images are \(Int(biggest.2))% of this file — compressing will help a lot.",
                          systemImage: "lightbulb")
                        .font(.system(size: 11.5))
                    Button("Shrink File Size…") { app.sheet = .compress }
                        .controlSize(.small)
                }
            }
        } confirm: {}
        .task {
            do {
                let res = try await app.auditSpace(doc)
                total = res["totalHuman"] as? String ?? ""
                rows = (res["categories"] as? [[String: Any]] ?? []).map {
                    ($0["category"] as? String ?? "",
                     $0["human"] as? String ?? "",
                     $0["percent"] as? Double ?? 0,
                     $0["bytes"] as? Int ?? 0)
                }
            } catch {
                app.report(error, context: "Could not audit the file")
            }
            loading = false
        }
    }
}

// MARK: - batch processing

struct BatchSheet: View {
    @EnvironmentObject var app: AppModel
    @State private var files: [URL] = []
    @State private var action: AppModel.BatchAction = .compress
    @State private var preset = "balanced"
    @State private var folder: URL?

    var body: some View {
        SheetChrome(title: "Batch Processing",
                    subtitle: "Run one operation across many files at once.",
                    confirmTitle: "Run on \(files.count) File\(files.count == 1 ? "" : "s")",
                    confirmDisabled: files.isEmpty || folder == nil,
                    width: 540) {
            Field("Do this") {
                Picker("", selection: $action) {
                    ForEach(AppModel.BatchAction.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
            }

            if action == .compress {
                Field("Compression") {
                    Picker("", selection: $preset) {
                        Text("Light").tag("light"); Text("Balanced").tag("balanced")
                        Text("Aggressive").tag("aggressive"); Text("Maximum").tag("extreme")
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
            }

            Divider()

            HStack {
                Text(files.isEmpty ? "No files chosen"
                                   : "\(files.count) file\(files.count == 1 ? "" : "s") selected")
                    .font(.system(size: 12))
                    .foregroundStyle(files.isEmpty ? .secondary : .primary)
                Spacer()
                Button("Choose PDFs…") {
                    app.chooseFiles(types: [.pdf], message: "Choose PDFs to process") { files = $0 }
                }
                .controlSize(.small)
                if !files.isEmpty {
                    Button("Clear") { files = [] }.controlSize(.small)
                }
            }

            if !files.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(files, id: \.self) { url in
                            Text(url.lastPathComponent)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxHeight: 90)
            }

            HStack {
                Text(folder.map { "Save to \($0.lastPathComponent)" } ?? "No destination chosen")
                    .font(.system(size: 12))
                    .foregroundStyle(folder == nil ? .secondary : .primary)
                Spacer()
                Button("Choose Folder…") {
                    app.chooseFolder(title: "Where should the results go?") { folder = $0 }
                }
                .controlSize(.small)
            }

            Text("Originals are never modified — every result is written into the destination folder.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        } confirm: {
            guard let folder else { return }
            app.runBatch(files: files, action: action, outputFolder: folder, preset: preset)
        }
    }
}
