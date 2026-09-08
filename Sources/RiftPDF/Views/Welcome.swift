import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        AppMark(size: 42)
                        Text("RiftPDF")
                            .font(.system(size: 34, weight: .light, design: .rounded))
                    }
                    Text("Everything you need to do to a PDF, on your own machine.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    bigButton("Open a PDF", "folder", primary: true) { app.openPanel() }
                    bigButton("Combine PDFs", "square.stack.3d.down.right") { app.sheet = .merge }
                    bigButton("Images to PDF", "photo.on.rectangle.angled") { app.sheet = .imagesToPDF }
                    bigButton("Word to PDF", "doc.text") {
                        app.chooseFiles(types: OfficeConverter.readableTypes,
                                        message: "Choose Word or text documents to convert") { urls in
                            app.convertOfficeToPDF(urls)
                        }
                    }
                }

                Spacer()

                if !app.isDefaultPDFReader {
                    HStack(spacing: 9) {
                        Image(systemName: "doc.badge.gearshape")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("PDFs still open in \(app.currentPDFReaderName)")
                                .font(.system(size: 11.5, weight: .medium))
                            Text("macOS will ask you to confirm.")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("Use RiftPDF") { app.requestDefaultPDFReader() }
                            .controlSize(.small)
                    }
                    .padding(10)
                    .frame(width: 330)
                    .background(Color.primary.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 8))
                }

                EngineStatus()
            }
            .padding(34)
            .frame(width: 400, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Recent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                if app.recentFiles.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("Nothing here yet")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("Drop a PDF, image or Word file anywhere in this window to get started.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 240)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(app.recentFiles, id: \.self) { url in
                                Button { app.open(url: url) } label: {
                                    HStack(spacing: 9) {
                                        Image(systemName: "doc.richtext")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color.accentColor)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(url.displayName)
                                                .font(.system(size: 12, weight: .medium))
                                                .lineLimit(1)
                                            Text(url.deletingLastPathComponent().path)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                                .truncationMode(.head)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(HoverRowStyle())
                            }
                        }
                    }
                    Button("Clear recent files") { app.clearRecents() }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bigButton(_ title: String, _ icon: String, primary: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14)).frame(width: 20)
                Text(title).font(.system(size: 13, weight: primary ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 300)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(primary ? Color.accentColor.opacity(0.92) : Color.primary.opacity(0.06))
            )
            .foregroundStyle(primary ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

struct HoverRowStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(hovering ? Color.primary.opacity(0.07) : .clear))
            .onHover { hovering = $0 }
    }
}

struct EngineStatus: View {
    @State private var caps = Engine.shared.capabilities

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(caps.ready ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(caps.ready ? "Engine ready" : "Engine starting…")
                    .font(.system(size: 10.5, weight: .medium))
            }
            if caps.ready {
                Text("MuPDF \(caps.pymupdf) · pikepdf \(caps.pikepdf)"
                     + (caps.ghostscript ? " · Ghostscript" : "")
                     + (caps.qpdf ? " · qpdf" : "")
                     + (caps.libreOffice ? " · LibreOffice" : ""))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            if caps.ready && !caps.libreOffice {
                Text("Word conversion uses the built-in typesetter. Install LibreOffice for exact layout fidelity.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: 300, alignment: .leading)
            }
        }
        .task {
            await Engine.shared.probe()
            caps = Engine.shared.capabilities
        }
    }
}


/// The app mark, loaded from the bundle so the window and the icon always agree.
struct AppMark: View {
    var size: CGFloat = 42

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "AppMark", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "book.pages.fill")
                    .resizable()
                    .foregroundStyle(Color.accentColor)
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
