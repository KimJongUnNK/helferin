import AppKit
import Foundation

struct ChatMessage: Identifiable {
    enum Role { case user, assistant, info }
    let id = UUID()
    let date = Date()
    let role: Role
    let text: String
    var symbol: String? = nil   // SF Symbol für Info-Karten
    var fileURL: URL? = nil     // erstellte/geöffnete Datei → „Öffnen“ / „Im Finder zeigen“
}

@MainActor
final class Assistant: ObservableObject {
    enum Mode { case voice, text }
    enum Phase { case idle, speaking, listening, thinking }

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var mode: Mode = .voice
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var liveTranscript = ""
    @Published private(set) var level: Float = 0
    @Published var input = ""
    @Published private(set) var focusRequest = 0
    @Published private(set) var profile: Profile?
    @Published private(set) var editingProfile = false
    @Published var showingSettings = false

    var onClose: (() -> Void)?
    /// Einrichtung zeigen: beim allerersten Start oder über „Profil & Programme“.
    var needsOnboarding: Bool { profile == nil || editingProfile }
    /// Noch nichts gesagt oder getippt → Startkarten zeigen.
    var showsQuickStart: Bool { !messages.contains { $0.role == .user } }

    let settings: Settings
    private let speech: SpeechIO
    private var history: [OllamaClient.Message] = []
    private var reprompts = 0
    private var llm: OllamaClient { OllamaClient(settings: settings) }
    var actions: Actions { Actions(settings: settings) }

    init() {
        let settings = Settings.load()
        self.settings = settings
        speech = SpeechIO(voiceName: settings.voiceName)
        speech.silenceSeconds = settings.silenceSeconds
        speech.noSpeechSeconds = settings.noSpeechSeconds
        profile = Profile.load()
        applyStyle()
        speech.onLevel = { [weak self] v in self?.level = v }
    }

    // MARK: Start & Einrichtung

    /// Beim Login (nachdem die Vorbereitung fertig ist): begrüßen – oder beim ersten Mal die Einrichtung starten.
    func start() {
        Task { await llm.warmUp() }
        if profile == nil {
            mode = .text
            speech.speak("Hallo! Ich bin Helferlein. Lass uns kurz einrichten, das dauert nur eine Minute.") {}
        } else {
            greet()
        }
    }

    func completeOnboarding(_ p: Profile) {
        do { try p.save() } catch {
            add(.info, "Profil konnte nicht gespeichert werden: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
        let firstTime = profile == nil
        profile = p
        editingProfile = false
        showingSettings = false
        applyStyle()
        if firstTime {
            LoginItem.setEnabled(true)
            messages = []
            history = []
        }
        greet()
    }

    func editProfile() {
        speech.stopAll()
        mode = .text
        if phase != .thinking { phase = .idle }
        showingSettings = false
        editingProfile = true
    }

    func cancelEditProfile() {
        guard profile != nil else { return }
        editingProfile = false
    }

    func openSettings() {
        speech.stopAll()
        mode = .text
        if phase != .thinking { phase = .idle }
        showingSettings = true
    }

    func closeSettings() {
        speech.stopMicTest()
        showingSettings = false
    }

    /// „Probehören“ in der Einrichtung.
    func preview(_ style: Style, name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        speech.rate = settings.speechRate > 0 ? settings.speechRate : style.rate
        speech.speak(style.sample(name: n.isEmpty ? "du" : n)) {}
    }

    func stopPreview() {
        speech.stopAll()
        applyStyle()
    }

    private func applyStyle() {
        speech.rate = settings.speechRate > 0 ? settings.speechRate : (profile?.style.rate ?? 0.48)
    }

    // MARK: Einstellungen: Mikrofon & Neustart

    /// Pegel-Anzeige für das gewählte Mikrofon. Gibt eine Fehlermeldung zurück, wenn es nicht startet.
    func startMicTest(level: @escaping @MainActor (Float) -> Void) async -> String? {
        guard await SpeechIO.authorize() else {
            return "Kein Zugriff aufs Mikrofon. Erlauben unter Systemeinstellungen › Datenschutz & Sicherheit › Mikrofon."
        }
        return speech.startMicTest(level: level)
    }

    func stopMicTest() { speech.stopMicTest() }

    /// Alles neu starten: Sprache stoppen, das lokale Modell (Ollama) beenden, Helferlein neu öffnen.
    func restartAll() {
        speech.stopAll()
        Actions.run("/usr/bin/pkill", ["-x", "ollama"])
        Actions.run("/usr/bin/pkill", ["-x", "Ollama"])
        AppRelaunch.relaunch()
    }

    // MARK: Ablauf

    func greet() {
        guard let p = profile else { return }
        let text = p.style.greeting(name: p.firstName, timeGreeting: Self.timeGreeting())
            + " Wenn du lieber tippen willst, drück einfach Enter."
        add(.assistant, text)
        history.append(.init(role: "assistant", content: text))
        mode = .voice
        reprompts = 0
        say(text)
    }

    /// Klick aufs Menüleisten-Symbol: Fenster ist offen, Tippen ist bereit.
    func reopened() {
        if needsOnboarding || showingSettings { return }
        if messages.isEmpty { greet(); return }
        mode = .text
        focusRequest += 1
    }

    func closed() {
        speech.stopAll()
        applyStyle()
        mode = .text
        liveTranscript = ""
        if phase != .thinking { phase = .idle }
    }

    func switchToText() {
        speech.stopAll()
        mode = .text
        liveTranscript = ""
        if phase != .thinking { phase = .idle }
        focusRequest += 1
    }

    /// 🎤 im Schreib-Modus: zurück zum Sprechen. Kurzes „Ich höre dir zu“, dann frisch zuhören.
    func switchToVoice() {
        speech.stopAll()
        liveTranscript = ""
        mode = .voice
        reprompts = 0
        guard phase != .thinking else { return } // nach der Antwort wird automatisch zugehört
        phase = .idle
        say("Ich höre dir zu.")
    }

    func submitText() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, phase != .thinking else { return }
        input = ""
        send(text)
    }

    /// Startkarte angeklickt.
    func quickStart(_ text: String) {
        guard phase != .thinking else { return }
        speech.stopAll()
        send(text)
    }

    func open(_ url: URL) {
        let actions = self.actions
        Task.detached { _ = actions.open(url) }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Sprache

    private func say(_ text: String, then next: (@MainActor () -> Void)? = nil) {
        guard mode == .voice else { phase = .idle; next?(); return }
        phase = .speaking
        speech.speak(text) { [weak self] in
            guard let self else { return }
            self.phase = .idle
            if let next { next() } else { self.listen() }
        }
    }

    private func listen() {
        guard mode == .voice, !needsOnboarding, !showingSettings else { return }
        phase = .listening
        liveTranscript = ""
        speech.listen(
            partial: { [weak self] t in self?.liveTranscript = t },
            final: { [weak self] t in self?.heard(t) },
            failure: { [weak self] msg in
                guard let self else { return }
                self.add(.info, msg, symbol: "mic.slash")
                self.switchToText()
            })
    }

    private func heard(_ text: String) {
        liveTranscript = ""
        phase = .idle
        guard text.isEmpty else { send(text); return }
        guard let p = profile else { return }

        // Stille: erst nachfragen („Michaela, hörst du mich?“), dann leise in den Tipp-Modus
        if reprompts < settings.maxReprompts {
            reprompts += 1
            let ask = p.style.reprompt(name: p.firstName)
            add(.assistant, ask)
            say(ask)
        } else {
            reprompts = 0
            add(.info, "Ich bin hier oben, wenn du mich brauchst. Schreib mir oder tipp auf „Sprechen“.", symbol: "moon.zzz")
            switchToText()
        }
    }

    // MARK: Denken & Handeln

    private func send(_ text: String) {
        guard let p = profile else { return }
        reprompts = 0
        add(.user, text)
        history.append(.init(role: "user", content: text))
        phase = .thinking
        let allowed = AgentReply.Action.allowed(for: p)
        let system = Prompt.system(settings, profile: p)
        let apps = p.tools
        Task {
            do {
                let reply = try await llm.chat(system: system, history: history, allowed: allowed, apps: apps)
                await handle(reply, allowed: allowed)
            } catch {
                phase = .idle
                add(.info, "Technisches Problem: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
                say("Entschuldige, da hat gerade etwas nicht geklappt. Probier es bitte nochmal oder starte mich in den Einstellungen neu.")
            }
        }
    }

    private func handle(_ reply: AgentReply, allowed: [AgentReply.Action]) async {
        var spoken = reply.reply.isEmpty ? "Okay." : reply.reply
        var note: ChatMessage?
        let actions = self.actions
        // Sicherheitsnetz: abgewählte Programme werden nie benutzt, auch wenn das Modell es versucht
        var action = allowed.contains(reply.action) ? reply.action : .none
        // Sagt sie „PDF“, wird es ein PDF – egal, was das Modell gewählt hat
        if action == .create_document, allowed.contains(.create_pdf), Self.mentionsPDF(lastUserText) {
            action = .create_pdf
        }

        func fileNote(_ url: URL, _ result: Actions.OpenResult, verb: String, symbol: String) -> ChatMessage {
            var text = "„\(url.lastPathComponent)“ \(verb) in \(result.label) geöffnet."
            if let hint = result.hint { text += "\n" + hint }
            return ChatMessage(role: .info, text: text, symbol: symbol, fileURL: url)
        }

        do {
            switch action {
            case .create_document, .create_pdf:
                let title = reply.title?.nonEmpty ?? "Dokument"
                let sections = reply.sections ?? []
                let pdf = action == .create_pdf
                let url = try await Task.detached {
                    try pdf ? actions.createPDF(title: title, sections: sections)
                            : actions.createDocument(title: title, sections: sections)
                }.value
                let result = await Task.detached { actions.open(url) }.value
                note = fileNote(url, result, verb: "gespeichert und", symbol: pdf ? Tool.pdf.symbol : Tool.word.symbol)

            case .create_presentation:
                let title = reply.title?.nonEmpty ?? "Präsentation"
                let slides = reply.slides ?? []
                let url = try await Task.detached { try actions.createPresentation(title: title, slides: slides) }.value
                let result = await Task.detached { actions.open(url) }.value
                note = fileNote(url, result, verb: "gespeichert und", symbol: Tool.powerpoint.symbol)

            case .create_spreadsheet:
                let title = reply.title?.nonEmpty ?? "Tabelle"
                let columns = reply.columns ?? []
                let rows = reply.rows ?? []
                let url = try await Task.detached { try actions.createSpreadsheet(title: title, columns: columns, rows: rows) }.value
                let result = await Task.detached { actions.open(url) }.value
                note = fileNote(url, result, verb: "gespeichert und", symbol: Tool.excel.symbol)

            case .proofread_file:
                let query = reply.query ?? ""
                let found = await Task.detached(operation: { actions.findFile(query, extensions: ["docx"]) }).value
                guard let file = found else {
                    spoken = query.isEmpty ? "Ich habe noch kein Word-Dokument gefunden."
                        : "Ich habe kein Word-Dokument mit „\(query)“ gefunden. Wie heißt es denn?"
                    break
                }
                let fixed = try Proofreader.correct(file, fallbackDir: settings.outputDir)
                if fixed.changes.isEmpty {
                    spoken = "Ich habe „\(file.deletingPathExtension().lastPathComponent)“ geprüft und keine Rechtschreibfehler gefunden."
                    try? FileManager.default.removeItem(at: fixed.output)
                } else {
                    let list = fixed.changes.prefix(12).map { "\($0.from) → \($0.to)" }.joined(separator: ", ")
                    let more = fixed.changes.count > 12 ? " und \(fixed.changes.count - 12) weitere" : ""
                    spoken = "Ich habe \(fixed.changes.count) Fehler korrigiert und eine korrigierte Kopie geöffnet."
                    let result = await Task.detached { actions.open(fixed.output) }.value
                    var n = fileNote(fixed.output, result, verb: "gespeichert und", symbol: "text.badge.checkmark")
                    n = ChatMessage(role: .info, text: n.text + "\nKorrigiert: \(list)\(more).", symbol: n.symbol, fileURL: n.fileURL)
                    note = n
                }

            case .open_app:
                guard let tool = reply.appTool, profileHas(tool) else {
                    spoken = "Welches Programm soll ich öffnen?"
                    break
                }
                let result = await Task.detached { actions.launch(tool) }.value
                if let hint = result.hint {
                    spoken = hint
                } else {
                    note = ChatMessage(role: .info, text: "\(tool.label) geöffnet.", symbol: tool.symbol)
                }

            case .open_file:
                let query = reply.query ?? ""
                if let url = await Task.detached(operation: { actions.findFile(query) }).value {
                    let result = await Task.detached { actions.open(url) }.value
                    note = fileNote(url, result, verb: "", symbol: "folder.fill")
                } else if let tool = reply.appTool ?? Self.toolMentioned(in: lastUserText), profileHas(tool) {
                    // Keine Datei gefunden, aber ein Programm gemeint („Öffne mir DeckCraft“) → Programm starten
                    let result = await Task.detached { actions.launch(tool) }.value
                    spoken = result.hint ?? "Ich habe \(tool.label) für dich geöffnet."
                } else {
                    spoken = query.isEmpty
                        ? "Ich habe noch kein Dokument von mir gefunden."
                        : "Ich habe leider keine Datei mit „\(query)“ gefunden. Weißt du noch, wie sie heißt?"
                }

            case .open_website:
                let address = reply.url ?? ""
                try await Task.detached { try actions.openWebsite(address) }.value
                note = ChatMessage(role: .info, text: "\(address) in Brave geöffnet.", symbol: "globe")

            case .web_search:
                let query = reply.query?.nonEmpty ?? reply.title ?? ""
                await Task.detached { actions.webSearch(query) }.value
                note = ChatMessage(role: .info, text: "In Brave gesucht: „\(query)“", symbol: "magnifyingglass")

            case .close, .none:
                break
            }
        } catch {
            spoken = "Entschuldige, das hat leider nicht geklappt."
            note = ChatMessage(role: .info, text: "Fehler: \(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }

        phase = .idle
        add(.assistant, spoken)
        if let note { messages.append(note) }
        history.append(.init(role: "assistant", content: spoken + (note.map { " [\($0.text)]" } ?? "")))

        if action == .close {
            if mode == .voice {
                say(spoken) { [weak self] in self?.onClose?() }
            } else {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self?.onClose?()
                }
            }
        } else {
            say(spoken)
        }
    }

    // MARK: Helfer

    private func profileHas(_ tool: Tool) -> Bool { profile?.has(tool) ?? false }

    private var lastUserText: String {
        history.last { $0.role == "user" }?.content ?? ""
    }

    static func mentionsPDF(_ text: String) -> Bool {
        text.range(of: #"\bpdfs?\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// „Öffne mir DeckCraft“ / „… PowerPoint“ → .powerpoint
    static func toolMentioned(in text: String) -> Tool? {
        let t = text.lowercased()
        return Tool.allCases.first { tool in
            t.contains(tool.label.lowercased()) || tool.appNames.contains { t.contains($0.lowercased()) }
        }
    }

    private func add(_ role: ChatMessage.Role, _ text: String, symbol: String? = nil) {
        messages.append(ChatMessage(role: role, text: text, symbol: symbol))
    }

    static func timeGreeting(_ date: Date = Date()) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: return "Guten Morgen"
        case 11..<18: return "Hallo"
        default: return "Guten Abend"
        }
    }
}

extension String {
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
