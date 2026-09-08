import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct SheetHost: View {
    let route: SheetRoute
    @EnvironmentObject var app: AppModel

    var body: some View {
        Group {
            switch route {
            case .compress: guarded { CompressSheet(doc: $0) }
            case .metadata: guarded { MetadataSheet(doc: $0) }
            case .watermark: guarded { WatermarkSheet(doc: $0) }
            case .pageNumbers: guarded { PageNumberSheet(doc: $0) }
            case .security: guarded { SecuritySheet(doc: $0) }
            case .exportImages: guarded { ExportImagesSheet(doc: $0) }
            case .split: guarded { SplitSheet(doc: $0) }
            case .ocr: guarded { OCRSheet(doc: $0) }
            case .documentInfo: guarded { DocumentInfoSheet(doc: $0) }
            case .formFill: guarded { FormSheet(doc: $0) }
            case .attachments: guarded { AttachmentSheet(doc: $0) }
            case .bookmarks: guarded { BookmarkSheet(doc: $0) }
            case .compare: guarded { CompareSheet(doc: $0) }
            case .accessibility: guarded { AccessibilitySheet(doc: $0) }
            case .headerFooter: guarded { HeaderFooterSheet(doc: $0) }
            case .auditSpace: guarded { AuditSpaceSheet(doc: $0) }
            case .batch: BatchSheet()
            case .merge: MergeSheet()
            case .imagesToPDF: ImagesToPDFSheet()
            case .preferences: PreferencesSheet()
            }
        }
    }

    @ViewBuilder
    private func guarded<V: View>(@ViewBuilder _ build: (PDFDoc) -> V) -> some View {
        if let doc = app.current {
            build(doc)
        } else {
            SheetChrome(title: "No document open", confirmTitle: nil) {
                Text("Open a PDF first.").font(.system(size: 12)).foregroundStyle(.secondary)
            } confirm: {}
        }
    }
}

/// Shared sheet frame — title, scrolling body, cancel/confirm footer.
struct SheetChrome<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var confirmTitle: String? = "Apply"
    var confirmDisabled: Bool = false
    var destructive: Bool = false
    var width: CGFloat = 460
    @ViewBuilder var content: Content
    var confirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 460)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if let confirmTitle {
                    Button(confirmTitle) { confirm(); dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .tint(destructive ? .red : .accentColor)
                        .disabled(confirmDisabled)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
        }
        .frame(width: width)
    }
}
