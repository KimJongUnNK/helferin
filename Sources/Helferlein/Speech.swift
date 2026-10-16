import AudioToolbox
import AVFoundation
import Speech

/// Sprechen (AVSpeechSynthesizer) und Zuhören (SFSpeechRecognizer, wenn möglich auf dem Gerät).
/// Läuft komplett auf dem Main-Actor; nur der Audio-Tap und die Erkennung melden sich von anderen Threads.
@MainActor
final class SpeechIO: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var onSpoken: (@MainActor () -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "de-DE"))
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Task<Void, Never>?
    private var finished = true
    private var lastText = ""
    private var finalHandler: (@MainActor (String) -> Void)?

    var rate: Float = 0.48
    var pitch: Float = 1.05
    var volume: Float = 1.0
    var silenceSeconds: Double = 1.6
    var noSpeechSeconds: Double = 7
    /// Mikrofon-Pegel 0…1, für die Animation.
    var onLevel: (@MainActor (Float) -> Void)?
    private(set) var voice: AVSpeechSynthesisVoice?

    func setVoice(named name: String) {
        voice = Self.pickVoice(named: name)
    }

    /// Alle deutschen Stimmen, beste zuerst (für die Auswahl in den Einstellungen).
    static var germanVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("de") }
            .sorted { ($0.quality.rawValue, $0.gender == .female ? 1 : 0, $0.name) > ($1.quality.rawValue, $1.gender == .female ? 1 : 0, $1.name) }
    }

    static func qualityLabel(_ v: AVSpeechSynthesisVoice) -> String {
        switch v.quality {
        case .premium: return "Premium"
        case .enhanced: return "Erweitert"
        default: return "Standard"
        }
    }

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
            return [v.quality.rawValue, v.gender == .female ? 1 : 0, favorite, v.language == "de-DE" ? 1 : 0]
        }
        return german.max { score($0).lexicographicallyPrecedes(score($1)) }
            ?? AVSpeechSynthesisVoice(language: "de-DE")
    }

    /// Gibt es eine schöne (Premium/Erweitert) deutsche Stimme?
    static var hasHighQualityVoice: Bool {
        AVSpeechSynthesisVoice.speechVoices().contains { $0.language.hasPrefix("de") && $0.quality != .default }
    }

    // MARK: Sprechen

    func speak(_ text: String, completion: @escaping @MainActor () -> Void) {
        stopListening()
        onSpoken = nil
        synth.stopSpeaking(at: .immediate)
        onSpoken = completion
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = rate
        u.pitchMultiplier = pitch
        u.volume = volume
        u.postUtteranceDelay = 0.15
        synth.speak(u)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            let done = self.onSpoken
            self.onSpoken = nil
            done?()
        }
    }

    // MARK: Zuhören

    /// `final` bekommt den erkannten Text – oder "" wenn `noSpeechSeconds` lang nichts gesagt wurde.
    func listen(partial: @escaping @MainActor (String) -> Void,
                final: @escaping @MainActor (String) -> Void,
                failure: @escaping @MainActor (String) -> Void) {
        Task { @MainActor in
            guard await Self.authorize() else {
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
                failure("Das Mikrofon konnte nicht starten (\(error.localizedDescription)). Wähl in den Einstellungen ein anderes Mikrofon oder schreib mir.")
            }
        }
    }

    private func start(_ recognizer: SFSpeechRecognizer,
                       partial: @escaping @MainActor (String) -> Void,
                       final: @escaping @MainActor (String) -> Void) throws {
        stopListening()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true } // bleibt lokal
        request = req
        lastText = ""
        finalHandler = final
        finished = false

        // Jedes Mal eine frische Audio-Engine: gewähltes Mikrofon, kein hängender Zustand nach dem Umschalten
        let engine = try Self.makeEngine()
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0),
                         block: Self.tap(req, level: Self.levelForwarder(self)))
        self.engine = engine
        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: req, resultHandler: Self.resultHandler(self, partial: partial))
        armSilenceTimer(noSpeechSeconds) // so lange gar nichts gesagt → "" zurückgeben
    }

    /// Audio-Engine mit dem in den Einstellungen gewählten Mikrofon.
    static func makeEngine() throws -> AVAudioEngine {
        let engine = AVAudioEngine()
        if var device = AudioDevices.selectedDeviceID, let unit = engine.inputNode.audioUnit {
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                              &device, UInt32(MemoryLayout<AudioDeviceID>.size))
            if status != noErr { NSLog("Helferlein: Mikrofon konnte nicht gesetzt werden (\(status))") }
        }
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "Helferlein", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Kein Mikrofon gefunden"])
        }
        return engine
    }

    // Die folgenden Helfer sind nonisolated, damit ihre Closures auf Audio-/Erkennungs-Threads laufen dürfen.

    nonisolated private static func levelForwarder(_ owner: SpeechIO) -> @Sendable (Float) -> Void {
        { v in Task { @MainActor in owner.onLevel?(v) } }
    }

    nonisolated private static func tap(_ req: SFSpeechAudioBufferRecognitionRequest?,
                                        level: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            req?.append(buffer)
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += samples[i] * samples[i] }
            let db = 20 * log10(max(sqrt(sum / Float(n)), 1e-6))
            level(min(1, max(0, (db + 50) / 40))) // -50 dB … -10 dB → 0 … 1
        }
    }

    nonisolated private static func resultHandler(_ owner: SpeechIO, partial: @escaping @MainActor (String) -> Void)
        -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                guard !owner.finished else { return }
                if let text {
                    owner.lastText = text
                    partial(text)
                    owner.armSilenceTimer(owner.silenceSeconds)
                    if isFinal { owner.finish() }
                } else if failed {
                    owner.finish()
                }
            }
        }
    }

    private func armSilenceTimer(_ seconds: Double) {
        silenceTimer?.cancel()
        silenceTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
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
        silenceTimer?.cancel()
        silenceTimer = nil
        if let engine {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        onLevel?(0)
    }

    func stopAll() {
        stopListening()
        stopMicTest()
        onSpoken = nil
        synth.stopSpeaking(at: .immediate)
    }

    // MARK: Mikrofon-Test (Einstellungen)

    private var testEngine: AVAudioEngine?

    /// Zeigt nur den Pegel des gewählten Mikrofons an, ohne Erkennung.
    func startMicTest(level: @escaping @MainActor (Float) -> Void) -> String? {
        stopMicTest()
        do {
            let engine = try Self.makeEngine()
            let input = engine.inputNode
            let forward: @Sendable (Float) -> Void = { v in Task { @MainActor in level(v) } }
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0),
                             block: Self.tap(nil, level: forward))
            engine.prepare()
            try engine.start()
            testEngine = engine
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func stopMicTest() {
        guard let engine = testEngine else { return }
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        testEngine = nil
    }

    // MARK: Berechtigungen

    nonisolated static func authorize() async -> Bool {
        let speechOK: Bool = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { return false }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { c in
                AVCaptureDevice.requestAccess(for: .audio) { c.resume(returning: $0) }
            }
        default: return false
        }
    }
}
