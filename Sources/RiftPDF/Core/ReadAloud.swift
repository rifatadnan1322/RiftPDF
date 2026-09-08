import AVFoundation
import SwiftUI

/// Read Out Loud, using the same on-device voices as the rest of macOS.
@MainActor
final class ReadAloudService: NSObject, ObservableObject {

    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var currentIndex: Int = 0
    @Published var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    @Published var pitch: Float = 1.0
    @Published var volume: Float = 1.0
    @Published var voiceIdentifier: String = ""

    private let synth = AVSpeechSynthesizer()
    private var queue: [String] = []
    private var onAdvance: ((Int) -> Void)?

    override init() {
        super.init()
        synth.delegate = self
        voiceIdentifier = AVSpeechSynthesisVoice(language: Locale.current.identifier)?.identifier
            ?? AVSpeechSynthesisVoice(language: "en-US")?.identifier ?? ""
    }

    static var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .sorted { ($0.language, $0.name) < ($1.language, $1.name) }
    }

    var voiceName: String {
        AVSpeechSynthesisVoice(identifier: voiceIdentifier)?.name ?? "System voice"
    }

    /// Speaks a list of passages, reporting which one is being read so the
    /// reading view can follow along.
    func speak(_ passages: [String], from index: Int = 0,
               onAdvance: ((Int) -> Void)? = nil) {
        stop()
        queue = passages.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !queue.isEmpty else { return }
        self.onAdvance = onAdvance
        currentIndex = min(max(0, index), queue.count - 1)
        isSpeaking = true
        isPaused = false
        enqueueFrom(currentIndex)
    }

    private func enqueueFrom(_ index: Int) {
        for i in index..<queue.count {
            let utterance = AVSpeechUtterance(string: queue[i])
            utterance.rate = rate
            utterance.pitchMultiplier = pitch
            utterance.volume = volume
            utterance.postUtteranceDelay = 0.12
            if let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
                utterance.voice = voice
            }
            synth.speak(utterance)
        }
    }

    func pauseOrResume() {
        guard isSpeaking else { return }
        if isPaused {
            synth.continueSpeaking()
            isPaused = false
        } else {
            synth.pauseSpeaking(at: .word)
            isPaused = true
        }
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        isSpeaking = false
        isPaused = false
    }

    func skipForward() {
        guard isSpeaking, currentIndex + 1 < queue.count else { return }
        let next = currentIndex + 1
        synth.stopSpeaking(at: .immediate)
        currentIndex = next
        isSpeaking = true
        isPaused = false
        enqueueFrom(next)
        onAdvance?(next)
    }

    func skipBackward() {
        guard isSpeaking else { return }
        let previous = max(0, currentIndex - 1)
        synth.stopSpeaking(at: .immediate)
        currentIndex = previous
        isSpeaking = true
        isPaused = false
        enqueueFrom(previous)
        onAdvance?(previous)
    }
}

extension ReadAloudService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if let index = queue.firstIndex(of: utterance.speechString), index != currentIndex {
                currentIndex = index
                onAdvance?(index)
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if utterance.speechString == queue.last {
                isSpeaking = false
                isPaused = false
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {}
}

// MARK: - low-vision display modes

enum DisplayMode: String, CaseIterable, Identifiable {
    case normal, night, sepia, grayscale, highContrast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: "Normal"
        case .night: "Night (inverted)"
        case .sepia: "Sepia"
        case .grayscale: "Greyscale"
        case .highContrast: "High contrast"
        }
    }

    var icon: String {
        switch self {
        case .normal: "sun.max"
        case .night: "moon.fill"
        case .sepia: "book.closed"
        case .grayscale: "circle.lefthalf.filled"
        case .highContrast: "circle.hexagongrid.fill"
        }
    }

    /// Filters applied to the live PDF view — the page is re-rendered, not
    /// covered with an overlay, so text stays crisp.
    var filters: [CIFilter] {
        switch self {
        case .normal:
            return []
        case .night:
            let invert = CIFilter(name: "CIColorInvert")!
            let warm = CIFilter(name: "CIColorControls")!
            warm.setValue(0.92, forKey: kCIInputContrastKey)
            warm.setValue(-0.04, forKey: kCIInputBrightnessKey)
            return [invert, warm]
        case .sepia:
            let sepia = CIFilter(name: "CISepiaTone")!
            sepia.setValue(0.65, forKey: kCIInputIntensityKey)
            return [sepia]
        case .grayscale:
            return [CIFilter(name: "CIPhotoEffectMono")!]
        case .highContrast:
            let controls = CIFilter(name: "CIColorControls")!
            controls.setValue(1.75, forKey: kCIInputContrastKey)
            controls.setValue(-0.06, forKey: kCIInputBrightnessKey)
            controls.setValue(0.0, forKey: kCIInputSaturationKey)
            return [controls]
        }
    }
}
