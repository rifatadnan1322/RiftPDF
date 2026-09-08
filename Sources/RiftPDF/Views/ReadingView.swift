import SwiftUI
import AVFoundation

/// A reflowed, high-contrast view of the document text — for low vision, for
/// reading long documents comfortably, and as the surface Read Out Loud
/// follows along with.
struct ReadingView: View {
    @ObservedObject var doc: PDFDoc
    @EnvironmentObject var app: AppModel
    @ObservedObject private var speech: ReadAloudService
    @Environment(\.dismiss) private var dismiss

    @State private var wholeDocument = true
    @State private var theme: ReadingTheme = .paper
    @State private var lineSpacing: Double = 1.5
    @State private var showVoiceOptions = false

    init(doc: PDFDoc, app: AppModel) {
        self.doc = doc
        self.speech = app.speech
    }

    enum ReadingTheme: String, CaseIterable, Identifiable {
        case paper, sepia, night, contrast
        var id: String { rawValue }
        var title: String {
            switch self {
            case .paper: "Paper"
            case .sepia: "Sepia"
            case .night: "Night"
            case .contrast: "High contrast"
            }
        }
        var background: Color {
            switch self {
            case .paper: Color(white: 0.99)
            case .sepia: Color(red: 0.98, green: 0.94, blue: 0.86)
            case .night: Color(white: 0.09)
            case .contrast: .black
            }
        }
        var foreground: Color {
            switch self {
            case .paper: Color(white: 0.12)
            case .sepia: Color(red: 0.24, green: 0.18, blue: 0.10)
            case .night: Color(white: 0.88)
            case .contrast: .yellow
            }
        }
        var highlight: Color {
            switch self {
            case .night, .contrast: Color.accentColor.opacity(0.35)
            default: Color.accentColor.opacity(0.18)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            content
        }
        .frame(width: 900, height: 700)
        .background(theme.background)
        .onAppear {
            if app.readingBlocks.isEmpty { app.loadReadingText(doc, wholeDocument: wholeDocument) }
        }
        .onDisappear { speech.stop() }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Label("Close", systemImage: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close reading view")

                Divider().frame(height: 18)

                Picker("", selection: $wholeDocument) {
                    Text("Whole document").tag(true)
                    Text("This page").tag(false)
                }
                .labelsHidden()
                .frame(width: 160)
                .onChange(of: wholeDocument) { _, value in
                    speech.stop()
                    app.loadReadingText(doc, wholeDocument: value)
                }
                .accessibilityLabel("How much to read")

                Spacer()

                Button {
                    app.readingFontScale = max(0.7, app.readingFontScale - 0.1)
                } label: { Image(systemName: "textformat.size.smaller") }
                .buttonStyle(.plain)
                .accessibilityLabel("Smaller text")

                Text("\(Int(app.readingFontScale * 100))%")
                    .font(.system(size: 11).monospacedDigit())
                    .frame(width: 40)

                Button {
                    app.readingFontScale = min(3.0, app.readingFontScale + 0.1)
                } label: { Image(systemName: "textformat.size.larger") }
                .buttonStyle(.plain)
                .accessibilityLabel("Larger text")

                Picker("", selection: $theme) {
                    ForEach(ReadingTheme.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 130)
                .accessibilityLabel("Reading theme")
            }

            HStack(spacing: 10) {
                Button { speech.skipBackward() } label: {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(.plain)
                .disabled(!speech.isSpeaking)
                .accessibilityLabel("Previous paragraph")

                Button {
                    if speech.isSpeaking {
                        speech.pauseOrResume()
                    } else {
                        speech.speak(app.readingBlocks.map(\.text))
                    }
                } label: {
                    Label(speech.isSpeaking ? (speech.isPaused ? "Resume" : "Pause") : "Read Out Loud",
                          systemImage: speech.isSpeaking
                            ? (speech.isPaused ? "play.fill" : "pause.fill")
                            : "speaker.wave.2.fill")
                        .frame(width: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(app.readingBlocks.isEmpty)

                Button { speech.skipForward() } label: {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(.plain)
                .disabled(!speech.isSpeaking)
                .accessibilityLabel("Next paragraph")

                Button { speech.stop() } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(.plain)
                    .disabled(!speech.isSpeaking)
                    .accessibilityLabel("Stop reading")

                Divider().frame(height: 16)

                Image(systemName: "tortoise").font(.system(size: 10)).foregroundStyle(.secondary)
                Slider(value: $speech.rate,
                       in: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
                    .frame(width: 110)
                    .accessibilityLabel("Reading speed")
                Image(systemName: "hare").font(.system(size: 10)).foregroundStyle(.secondary)

                Button { showVoiceOptions.toggle() } label: {
                    Label(speech.voiceName, systemImage: "person.wave.2")
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showVoiceOptions) { voicePicker }

                Spacer()

                if app.readingLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("\(app.readingBlocks.count) passages")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var voicePicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(ReadAloudService.voices, id: \.identifier) { voice in
                    Button {
                        speech.voiceIdentifier = voice.identifier
                        showVoiceOptions = false
                    } label: {
                        HStack {
                            Text(voice.name).font(.system(size: 11.5))
                            Text(voice.language).font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            if voice.identifier == speech.voiceIdentifier {
                                Image(systemName: "checkmark").font(.system(size: 9))
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
        }
        .frame(width: 280, height: 320)
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if app.readingLoading {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Preparing the text…").font(.system(size: 13))
                        }
                        .padding(.top, 40)
                    } else if app.readingBlocks.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "text.viewfinder")
                                .font(.system(size: 30, weight: .light))
                            Text("No readable text here")
                                .font(.system(size: 15, weight: .medium))
                            Text("If this document is a scan, run Tools ▸ Recognise Text to add a text layer, then come back.")
                                .font(.system(size: 12))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 380)
                        }
                        .foregroundStyle(theme.foreground.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    } else {
                        ForEach(Array(app.readingBlocks.enumerated()), id: \.element.id) { index, block in
                            Text(block.text)
                                .font(.system(size: (block.heading ? 21 : 15) * app.readingFontScale,
                                              weight: block.heading ? .semibold : .regular))
                                .lineSpacing((block.heading ? 4 : 8) * lineSpacing / 1.5)
                                .foregroundStyle(theme.foreground)
                                .textSelection(.enabled)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(speech.isSpeaking && speech.currentIndex == index
                                              ? theme.highlight : .clear)
                                )
                                .id(index)
                                .onTapGesture(count: 2) {
                                    speech.speak(app.readingBlocks.map(\.text), from: index)
                                }
                                .accessibilityLabel(block.heading ? "Heading: \(block.text)" : block.text)
                        }
                    }
                }
                .frame(maxWidth: 760)
                .padding(.horizontal, 40)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: speech.currentIndex) { _, index in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }
}
