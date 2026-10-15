import AVFoundation
import Speech

/// Sprechen (AVSpeechSynthesizer) und Zuhören (SFSpeechRecognizer, wenn möglich auf dem Gerät).
/// Alle Callbacks kommen auf dem Main-Thread an.
final class SpeechIO: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var onSpoken: (() -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var silenceWork: DispatchWorkItem?
    private var finished = true
    private var lastText = ""
    private var finalHandler: ((String) -> Void)?

    var rate: Float = 0.48
    var silenceSeconds: Double = 1.6
    var noSpeechSeconds: Double = 7
    /// Mikrofon-Pegel 0…1, für die Animation.
    var onLevel: ((Float) -> Void)?
    private(set) var voice: AVSpeechSynthesisVoice?

    init(voiceName: String = "") {
        super.init()
        synth.delegate = self
        voice = Self.pickVoice(named: voiceName)
    }

    // MARK: Stimme

    static let preferredFemale = ["anna", "petra", "helena", "marlene", "sandy", "shelley", "flo"]

    /// Wunschname aus der Config, sonst: beste Qualität → weiblich → Lieblingsnamen → de-DE.
    static func pickVoice(named wanted: String) -> AVSpeechSynthesisVoice? {
        let german = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("de") }
        let w = wanted.trimmingCharacters(in: .whitespaces).lowercased()
        if !w.isEmpty, let exact = german.first(where: { $0.name.lowercased() == w || $0.identifier.lowercased() == w })
            ?? german.first(where: { $0.name.lowercased().hasPrefix(w) }) {
            return exact
        }
        func score(_ v: AVSpeechSynthesisVoice) -> [Int] {
            let name = v.name.lowercased()
            let favorite = preferredFemale.firstIndex { name.hasPrefix($0) }.map { preferredFemale.count - $0 } ?? 0
            return [v.quality.rawValue,
                    v.gender == .female ? 1 : 0,
                    favorite,
                    v.language == "de-DE" ? 1 : 0]
        }
        return german.max { score($0).lexicographicallyPrecedes(score($1)) }
            ?? AVSpeechSynthesisVoice(language: "de-DE")
    }

    // MARK: Sprechen

    func speak(_ text: String, completion: @escaping () -> Void) {
        stopListening()
        onSpoken = nil
        synth.stopSpeaking(at: .immediate)
        onSpoken = completion
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = rate
        u.pitchMultiplier = 1.05
        u.postUtteranceDelay = 0.15
        synth.speak(u)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            let done = self.onSpoken
            self.onSpoken = nil
            done?()
        }
    }

    // MARK: Zuhören

    /// `final` bekommt den erkannten Text – oder "" wenn `noSpeechSeconds` lang nichts gesagt wurde.
    func listen(partial: @escaping (String) -> Void,
                final: @escaping (String) -> Void,
                failure: @escaping (String) -> Void) {
        Self.authorize { [weak self] ok in
            guard let self else { return }
            guard ok else {
                failure("Ich darf das Mikrofon nicht benutzen. Erlauben kannst du es in den Systemeinstellungen unter „Datenschutz & Sicherheit“ → Mikrofon und Spracherkennung.")
                return
            }
            guard let recognizer = self.recognizer, recognizer.isAvailable else {
                failure("Die Spracherkennung ist gerade nicht verfügbar. Du kannst mir aber schreiben.")
                return
            }
            do {
                try self.start(recognizer, partial: partial, final: final)
            } catch {
                self.stopListening()
                failure("Das Mikrofon konnte nicht starten (\(error.localizedDescription)). Du kannst mir aber schreiben.")
            }
        }
    }

    private func start(_ recognizer: SFSpeechRecognizer,
                       partial: @escaping (String) -> Void,
                       final: @escaping (String) -> Void) throws {
        stopListening()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true } // bleibt lokal
        request = req
        lastText = ""
        finalHandler = final
        finished = false

        let level: (Float) -> Void = { [weak self] v in
            DispatchQueue.main.async { self?.onLevel?(v) }
        }
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0),
                         block: Self.tap(req, level: level))
        tapInstalled = true
        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            DispatchQueue.main.async {
                guard let self, !self.finished else { return }
                if let text {
                    self.lastText = text
                    partial(text)
                    self.armSilenceTimer(self.silenceSeconds)
                    if isFinal { self.finish() }
                } else if error != nil {
                    self.finish()
                }
            }
        }
        armSilenceTimer(noSpeechSeconds) // so lange gar nichts gesagt → "" zurückgeben
    }

    /// Eigene Funktion, damit der Audio-Thread-Block keinen Actor-Kontext erbt.
    private static func tap(_ req: SFSpeechAudioBufferRecognitionRequest,
                            level: @escaping (Float) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            req.append(buffer)
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += samples[i] * samples[i] }
            let db = 20 * log10(max(sqrt(sum / Float(n)), 1e-6))
            level(min(1, max(0, (db + 50) / 40))) // -50 dB … -10 dB → 0 … 1
        }
    }

    private func armSilenceTimer(_ seconds: Double) {
        silenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.finish() }
        silenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func finish() {
        guard !finished else { return }
        let text = lastText.trimmingCharacters(in: .whitespacesAndNewlines)
        let handler = finalHandler
        stopListening()
        handler?(text)
    }

    func stopListening() {
        finished = true
        finalHandler = nil
        silenceWork?.cancel()
        silenceWork = nil
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        onLevel?(0)
    }

    func stopAll() {
        stopListening()
        onSpoken = nil
        synth.stopSpeaking(at: .immediate)
    }

    // MARK: Berechtigungen

    private static func authorize(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { return DispatchQueue.main.async { done(false) } }
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                DispatchQueue.main.async { done(true) }
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { done(ok) } }
            default:
                DispatchQueue.main.async { done(false) }
            }
        }
    }
}
