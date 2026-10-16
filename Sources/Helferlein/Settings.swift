import Foundation

/// Alle Einstellungen aus ~/Library/Application Support/Helferlein/config.json.
/// Persönliches (Name, Stil, Programme) steht im Profil (profile.json).
/// Fehlende Werte fallen auf die Standardwerte zurück – die Datei ist optional.
struct Settings: Codable, Sendable, Equatable {
    // MARK: KI
    var model = "qwen2.5:7b"
    var ollamaHost = "http://127.0.0.1:11434"
    /// 0 = sehr genau … 1 = sehr kreativ
    var temperature: Double = 0.4
    var answerLength: AnswerLength = .normal

    // MARK: Stimme
    /// Exakter Stimmenname/ID, z. B. "Anna (Premium)". Leer = automatisch beste weibliche deutsche Stimme.
    var voiceName = ""
    /// 0 = Tempo kommt vom gewählten Stil.
    var speechRate: Float = 0
    var voicePitch: Float = 1.05
    var voiceVolume: Float = 1.0

    // MARK: Zuhören
    /// So lange Pause, bis ein Satz als fertig gilt.
    var silenceSeconds: Double = 1.6
    /// So lange Stille, bis nachgefragt wird („<Name>, hörst du mich?“).
    var noSpeechSeconds: Double = 7
    /// Wie oft nachgefragt wird, bevor er still in den Tipp-Modus geht.
    var maxReprompts = 1

    // MARK: Start
    /// Beim Login das Fenster öffnen und begrüßen.
    var greetOnLogin = true
    var startMode: StartMode = .voice
    /// ⌘ zweimal kurz drücken (in jedem Programm) = Helferlein springt auf und hört zu.
    var doubleCommand = true

    // MARK: Programme
    /// Eigene App-Namen je Programm, z. B. {"powerpoint": "DeckCraft"}. Leer = automatisch suchen.
    var apps: [String: String] = [:]
    /// Fest gewählte App-Pfade je Programm (Einstellungen › Programme › „App wählen …“).
    var appPaths: [String: String] = [:]
    var browser: String = "Brave Browser"
    var searchEngine: SearchEngine = .brave

    // MARK: Dokumente
    /// Leer = ~/Documents/Helferlein
    var documentsFolder = ""
    /// "auto" = Region dieses Macs, sonst z. B. "de-AT"
    var documentLanguage = "auto"
    var documentFont = "Calibri"
    var documentFontSize: Double = 12
    /// Erstellte Dateien gleich im Programm öffnen.
    var openCreatedFiles = true

    enum AnswerLength: String, Codable, CaseIterable, Sendable {
        case short, normal, long
        var label: String {
            switch self {
            case .short: return "Kurz (1–2 Sätze)"
            case .normal: return "Normal (2–3 Sätze)"
            case .long: return "Ausführlich (bis 5 Sätze)"
            }
        }
        var instruction: String {
            switch self {
            case .short: return "höchstens 1–2 kurze Sätze"
            case .normal: return "höchstens 2–3 kurze Sätze"
            case .long: return "bis zu 5 Sätze, ruhig etwas genauer erklärt"
            }
        }
    }

    enum StartMode: String, Codable, CaseIterable, Sendable {
        case voice, text
        var label: String { self == .voice ? "Sprechen" : "Tippen (leise)" }
    }

    enum SearchEngine: String, Codable, CaseIterable, Sendable {
        case brave, duckduckgo, startpage, ecosia, google
        var label: String {
            switch self {
            case .brave: return "Brave Search"
            case .duckduckgo: return "DuckDuckGo"
            case .startpage: return "Startpage"
            case .ecosia: return "Ecosia"
            case .google: return "Google"
            }
        }
        func url(for query: String) -> URL {
            let base: String
            switch self {
            case .brave: base = "https://search.brave.com/search"
            case .duckduckgo: base = "https://duckduckgo.com/"
            case .startpage: base = "https://www.startpage.com/do/search"
            case .ecosia: base = "https://www.ecosia.org/search"
            case .google: base = "https://www.google.com/search"
            }
            var c = URLComponents(string: base)!
            c.queryItems = [URLQueryItem(name: "q", value: query)]
            return c.url!
        }
    }

    // MARK: Pfade

    static var supportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Helferlein", isDirectory: true)
    }
    static var configURL: URL { supportDir.appendingPathComponent("config.json") }

    /// Python: die in die App eingebaute Version (Download-Version) oder die venv aus install.sh.
    var pythonURL: URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("python/bin/python3"),
           FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        return Self.supportDir.appendingPathComponent("venv/bin/python3")
    }

    var helperURL: URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("craftdocs.py"),
           FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return Self.supportDir.appendingPathComponent("craftdocs.py")
    }

    static var defaultOutputDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Helferlein", isDirectory: true)
    }

    var outputDir: URL {
        documentsFolder.isEmpty ? Self.defaultOutputDir : URL(fileURLWithPath: documentsFolder, isDirectory: true)
    }

    /// Sprache der erstellten Dokumente: gewählt, oder Deutsch mit der Region dieses Macs.
    var resolvedDocumentLanguage: String {
        if documentLanguage != "auto", !documentLanguage.isEmpty { return documentLanguage }
        let region = Locale.current.region?.identifier.uppercased() ?? ""
        return ["AT", "CH", "LI", "LU", "BE"].contains(region) ? "de-\(region)" : "de-DE"
    }

    /// App-Namen, in dieser Reihenfolge gesucht: eigener Name aus der config, dann die bekannten Namen.
    func appNames(for tool: Tool) -> [String] {
        let custom = tool == .internet ? [browser] : [apps[tool.rawValue]].compactMap { $0 }
        return (custom + tool.appNames).filter { !$0.isEmpty }
    }

    // MARK: Laden & Speichern

    init() {}

    private enum LegacyKeys: String, CodingKey { case wordApp, pdfApp, deckApp, gridApp, browserApp }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        model = v(.model, d.model)
        ollamaHost = v(.ollamaHost, d.ollamaHost)
        temperature = v(.temperature, d.temperature)
        answerLength = v(.answerLength, d.answerLength)
        voiceName = v(.voiceName, d.voiceName)
        speechRate = v(.speechRate, d.speechRate)
        voicePitch = v(.voicePitch, d.voicePitch)
        voiceVolume = v(.voiceVolume, d.voiceVolume)
        silenceSeconds = v(.silenceSeconds, d.silenceSeconds)
        noSpeechSeconds = v(.noSpeechSeconds, d.noSpeechSeconds)
        maxReprompts = v(.maxReprompts, d.maxReprompts)
        greetOnLogin = v(.greetOnLogin, d.greetOnLogin)
        startMode = v(.startMode, d.startMode)
        doubleCommand = v(.doubleCommand, d.doubleCommand)
        apps = v(.apps, d.apps)
        appPaths = v(.appPaths, d.appPaths)
        browser = v(.browser, d.browser)
        searchEngine = v(.searchEngine, d.searchEngine)
        documentsFolder = v(.documentsFolder, d.documentsFolder)
        documentLanguage = v(.documentLanguage, d.documentLanguage)
        documentFont = v(.documentFont, d.documentFont)
        documentFontSize = v(.documentFontSize, d.documentFontSize)
        openCreatedFiles = v(.openCreatedFiles, d.openCreatedFiles)

        // Ältere config.json (wordApp, deckApp …) weiter verstehen
        if let legacy = try? decoder.container(keyedBy: LegacyKeys.self) {
            let map: [(LegacyKeys, Tool)] = [(.wordApp, .word), (.pdfApp, .pdf), (.deckApp, .powerpoint), (.gridApp, .excel)]
            for (key, tool) in map where apps[tool.rawValue] == nil {
                if let name = try? legacy.decodeIfPresent(String.self, forKey: key) { apps[tool.rawValue] = name }
            }
            if let b = try? legacy.decodeIfPresent(String.self, forKey: .browserApp), !b.isEmpty, browser == d.browser {
                browser = b
            }
        }
    }

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: configURL),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return s
    }

    func save() {
        try? FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) { try? data.write(to: Self.configURL, options: .atomic) }
    }
}
