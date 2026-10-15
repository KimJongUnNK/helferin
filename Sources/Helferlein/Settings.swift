import Foundation

/// Technische Einstellungen aus ~/Library/Application Support/Helferlein/config.json.
/// Persönliches (Name, Stil, Programme) steht im Profil (profile.json).
/// Fehlende Werte fallen auf die Standardwerte zurück – die Datei ist optional.
struct Settings: Codable, Sendable {
    var model = "qwen2.5:7b"
    var ollamaHost = "http://127.0.0.1:11434"
    /// Eigene App-Namen je Programm, z. B. {"powerpoint": "DeckCraft"}. Leer = automatisch suchen.
    var apps: [String: String] = [:]
    /// 0 = Tempo kommt vom gewählten Stil.
    var speechRate: Float = 0
    var silenceSeconds: Double = 1.6
    /// Exakter Stimmenname, z. B. "Anna (Premium)". Leer = automatisch beste weibliche deutsche Stimme.
    var voiceName = ""
    /// So lange Stille, bis nachgefragt wird („<Name>, hörst du mich?“).
    var noSpeechSeconds: Double = 7
    /// Wie oft nachgefragt wird, bevor er still in den Tipp-Modus geht.
    var maxReprompts = 1

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

    var outputDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Helferlein", isDirectory: true)
    }

    /// App-Namen, in dieser Reihenfolge gesucht: eigener Name aus der config, dann die bekannten Namen.
    func appNames(for tool: Tool) -> [String] {
        ([apps[tool.rawValue]].compactMap { $0 } + tool.appNames).filter { !$0.isEmpty }
    }

    init() {}

    private enum LegacyKeys: String, CodingKey { case wordApp, pdfApp, deckApp, gridApp, browserApp }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        ollamaHost = try c.decodeIfPresent(String.self, forKey: .ollamaHost) ?? d.ollamaHost
        apps = try c.decodeIfPresent([String: String].self, forKey: .apps) ?? [:]
        speechRate = try c.decodeIfPresent(Float.self, forKey: .speechRate) ?? d.speechRate
        silenceSeconds = try c.decodeIfPresent(Double.self, forKey: .silenceSeconds) ?? d.silenceSeconds
        voiceName = try c.decodeIfPresent(String.self, forKey: .voiceName) ?? d.voiceName
        noSpeechSeconds = try c.decodeIfPresent(Double.self, forKey: .noSpeechSeconds) ?? d.noSpeechSeconds
        maxReprompts = try c.decodeIfPresent(Int.self, forKey: .maxReprompts) ?? d.maxReprompts

        // Ältere config.json (wordApp, deckApp …) weiter verstehen
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        let map: [(LegacyKeys, Tool)] = [(.wordApp, .word), (.pdfApp, .pdf), (.deckApp, .powerpoint),
                                         (.gridApp, .excel), (.browserApp, .internet)]
        for (key, tool) in map where apps[tool.rawValue] == nil {
            if let name = try legacy.decodeIfPresent(String.self, forKey: key) { apps[tool.rawValue] = name }
        }
    }

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: configURL),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return s
    }
}
