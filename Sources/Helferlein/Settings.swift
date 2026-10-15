import Foundation

/// Technische Einstellungen aus ~/Library/Application Support/Helferlein/config.json.
/// Persönliches (Name, Stil, Programme) steht im Profil (profile.json).
/// Fehlende Werte fallen auf die Standardwerte zurück.
struct Settings: Codable {
    var model = "qwen2.5:7b"
    var ollamaHost = "http://127.0.0.1:11434"
    /// Echte App-Namen auf dem Mac. In der Oberfläche heißen sie Word, PDF Acrobat, PowerPoint.
    var wordApp = "WordCraft"
    var pdfApp = "PDFCraft"
    var deckApp = "DeckCraft"
    var gridApp = "GridCraft"
    var browserApp = "Brave Browser"
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

    var pythonURL: URL { Self.supportDir.appendingPathComponent("venv/bin/python3") }
    var helperURL: URL { Self.supportDir.appendingPathComponent("craftdocs.py") }
    var outputDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Helferlein", isDirectory: true)
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        ollamaHost = try c.decodeIfPresent(String.self, forKey: .ollamaHost) ?? d.ollamaHost
        wordApp = try c.decodeIfPresent(String.self, forKey: .wordApp) ?? d.wordApp
        pdfApp = try c.decodeIfPresent(String.self, forKey: .pdfApp) ?? d.pdfApp
        deckApp = try c.decodeIfPresent(String.self, forKey: .deckApp) ?? d.deckApp
        gridApp = try c.decodeIfPresent(String.self, forKey: .gridApp) ?? d.gridApp
        browserApp = try c.decodeIfPresent(String.self, forKey: .browserApp) ?? d.browserApp
        speechRate = try c.decodeIfPresent(Float.self, forKey: .speechRate) ?? d.speechRate
        silenceSeconds = try c.decodeIfPresent(Double.self, forKey: .silenceSeconds) ?? d.silenceSeconds
        voiceName = try c.decodeIfPresent(String.self, forKey: .voiceName) ?? d.voiceName
        noSpeechSeconds = try c.decodeIfPresent(Double.self, forKey: .noSpeechSeconds) ?? d.noSpeechSeconds
        maxReprompts = try c.decodeIfPresent(Int.self, forKey: .maxReprompts) ?? d.maxReprompts
    }

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: configURL),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return s
    }
}
