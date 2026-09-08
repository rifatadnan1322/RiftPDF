import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var app: AppModel
    @State private var dropTargeted = false

    var body: some View {
        ZStack(alignment: .top) {
            if let doc = app.current {
                editor(doc)
            } else {
                WelcomeView()
            }

            VStack(spacing: 8) {
                if !app.tasks.isEmpty { TaskBar() }
                if let toast = app.toast { ToastView(toast: toast) }
            }
            .padding(.top, 10)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: app.toast)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: app.tasks.count)
        }
        .frame(minWidth: 1080, minHeight: 700)
        .background(WindowBackground())
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(10)
                    .background(Color.accentColor.opacity(0.06).padding(10))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .sheet(item: $app.sheet) { route in SheetHost(route: route) }
        .sheet(isPresented: $app.showReadingView) {
            if let doc = app.current { ReadingView(doc: doc, app: app).environmentObject(app) }
        }
    }

    @ViewBuilder
    private func editor(_ doc: PDFDoc) -> some View {
        VStack(spacing: 0) {
            if app.docs.count > 1 { DocumentTabBar(); Divider() }
            ToolStrip()
            Divider()
            HStack(spacing: 0) {
                if app.showSidebar {
                    SidebarView(doc: doc)
                        .frame(width: 236)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider()
                }
                PDFCanvas(doc: doc)
                    .id(doc.id)
                if app.showInspector {
                    Divider()
                    InspectorView(doc: doc)
                        .frame(width: 268)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            Divider()
            StatusBar(doc: doc)
        }
        .animation(.easeInOut(duration: 0.18), value: app.showSidebar)
        .animation(.easeInOut(duration: 0.18), value: app.showInspector)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        var pdfs: [URL] = [], images: [URL] = [], office: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                defer { group.leave() }
                guard let url else { return }
                let ext = url.pathExtension.lowercased()
                if ext == "pdf" { pdfs.append(url) }
                else if ["png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "bmp", "webp"].contains(ext) { images.append(url) }
                else if ["docx", "doc", "rtf", "odt", "txt", "html", "htm", "md"].contains(ext) { office.append(url) }
            }
        }
        group.notify(queue: .main) {
            for url in pdfs { app.open(url: url) }
            if !office.isEmpty { app.convertOfficeToPDF(office) }
            if !images.isEmpty {
                if let doc = app.current, pdfs.isEmpty, office.isEmpty, images.count == 1 {
                    app.imagesToPDF(images, pageSize: "auto", fit: "fit", margin: 0, quality: 88)
                    _ = doc
                } else {
                    app.imagesToPDF(images, pageSize: "auto", fit: "fit", margin: 0, quality: 88)
                }
            }
        }
    }
}

// MARK: - window chrome

struct WindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - tabs

struct DocumentTabBar: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(app.docs) { doc in
                    tab(doc)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .background(.ultraThinMaterial)
    }

    private func tab(_ doc: PDFDoc) -> some View {
        let selected = doc.id == app.current?.id
        return HStack(spacing: 6) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 10))
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            Text(doc.displayName)
                .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                .lineLimit(1)
            if doc.isDirty {
                Circle().fill(Color.orange).frame(width: 5, height: 5)
            }
            Button { app.close(doc) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(selected ? 1 : 0.45)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
        )
        .contentShape(Rectangle())
        .onTapGesture { app.selectedDocID = doc.id }
        .help(doc.url?.path ?? doc.displayName)
    }
}

// MARK: - status bar

struct StatusBar: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel

    var body: some View {
        HStack(spacing: 14) {
            Button {
                withAnimation { app.showSidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.plain)
            .help("Toggle sidebar")

            Text("Page \(doc.currentPage + 1) of \(max(1, doc.pageCount))")
                .font(.system(size: 11.5).monospacedDigit())

            if !app.pendingRedactions.isEmpty {
                let count = app.pendingRedactions.values.reduce(0) { $0 + $1.count }
                Button {
                    app.applyRedactions(doc)
                } label: {
                    Label("Apply \(count) redaction\(count == 1 ? "" : "s")", systemImage: "rectangle.fill.badge.xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
            }

            Spacer()

            if doc.isDirty {
                Label("Unsaved changes", systemImage: "circle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .labelStyle(CompactLabel())
            }

            if let url = doc.url,
               let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int {
                Text(formatBytes(size))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                withAnimation { app.showInspector.toggle() }
            } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.plain)
            .help("Toggle inspector")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .foregroundStyle(.secondary)
        .background(.ultraThinMaterial)
    }
}

struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 6))
            configuration.title
        }
    }
}

// MARK: - progress + toast

struct TaskBar: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        VStack(spacing: 6) {
            ForEach(app.tasks) { task in
                TaskRow(task: task)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
    }
}

struct TaskRow: View {
    @ObservedObject var task: TaskProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(task.title).font(.system(size: 12, weight: .semibold))
                Spacer()
                if !task.isIndeterminate {
                    Text("\(Int(task.fraction * 100))%")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: task.isIndeterminate ? nil : task.fraction)
                .progressViewStyle(.linear)
            Text(task.message)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct ToastView: View {
    let toast: Toast
    @EnvironmentObject var app: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: toast.icon)
                .font(.system(size: 15))
                .foregroundStyle(toast.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(toast.title).font(.system(size: 12.5, weight: .semibold))
                if let detail = toast.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let url = toast.revealURL {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
            Button {
                withAnimation { app.toast = nil }
            } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: 460, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(toast.tint.opacity(0.28)))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
