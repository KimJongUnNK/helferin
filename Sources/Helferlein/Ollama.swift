import Foundation

/// Strukturierte Antwort des Modells. Ollama erzwingt dieses Format per JSON-Schema.
struct AgentReply: Decodable, Sendable {
    enum Action: String, CaseIterable, Sendable {
        case none, create_document, create_pdf, create_presentation, create_spreadsheet,
             proofread_file, open_app, open_file, open_website, web_search, close

        /// Welche Aktionen das Profil erlaubt (abgewählte Programme fallen raus).
        static func allowed(for profile: Profile) -> [Action] {
            allCases.filter {
                switch $0 {
                case .create_document, .proofread_file: return profile.has(.word)
                case .create_pdf: return profile.has(.pdf)
                case .create_presentation: return profile.has(.powerpoint)
                case .create_spreadsheet: return profile.has(.excel)
                case .open_website, .web_search: return profile.has(.internet)
                case .open_app: return !profile.tools.isEmpty
                case .none, .open_file, .close: return true
                }
            }
        }
    }
    struct Section: Codable, Sendable { var heading: String; var text: String }
    struct Slide: Codable, Sendable { var title: String; var bullets: [String] }

    var reply: String
    var action: Action
    var title: String?
    var sections: [Section]?
    var slides: [Slide]?
    var query: String?
    var url: String?
    var app: String?
    var columns: [String]?
    var rows: [[String]]?

    enum CodingKeys: String, CodingKey { case reply, action, title, sections, slides, query, url, app, columns, rows }

    init(reply: String, action: Action = .none) {
        self.reply = reply
        self.action = action
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reply = (try? c.decode(String.self, forKey: .reply)) ?? ""
        let raw = (try? c.decode(String.self, forKey: .action)) ?? "none"
        action = Action(rawValue: raw) ?? .none
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        sections = try? c.decodeIfPresent([Section].self, forKey: .sections)
        slides = try? c.decodeIfPresent([Slide].self, forKey: .slides)
        query = try? c.decodeIfPresent(String.self, forKey: .query)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        app = try? c.decodeIfPresent(String.self, forKey: .app)
        columns = try? c.decodeIfPresent([String].self, forKey: .columns)
        rows = try? c.decodeIfPresent([[String]].self, forKey: .rows)
    }

    /// Programm aus "app" – akzeptiert Schlüssel ("powerpoint"), Anzeigenamen ("PowerPoint") und Craft-Namen ("DeckCraft").
    var appTool: Tool? {
        guard let raw = app?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else { return nil }
        let key = raw.replacingOccurrences(of: " ", with: "")
        return Tool(rawValue: key) ?? Tool.allCases.first {
            $0.label.lowercased().replacingOccurrences(of: " ", with: "") == key
                || $0.appNames.contains { $0.lowercased() == key }
        }
    }

    static func schema(allowed: [Action], apps: [Tool]) -> [String: Any] { [
        "type": "object",
        "properties": [
            "reply": ["type": "string"],
            "action": ["type": "string", "enum": allowed.map(\.rawValue)],
            "title": ["type": "string"],
            "sections": ["type": "array", "items": [
                "type": "object",
                "properties": ["heading": ["type": "string"], "text": ["type": "string"]],
                "required": ["heading", "text"],
            ]],
            "slides": ["type": "array", "items": [
                "type": "object",
                "properties": ["title": ["type": "string"],
                               "bullets": ["type": "array", "items": ["type": "string"]]],
                "required": ["title", "bullets"],
            ]],
            "query": ["type": "string"],
            "url": ["type": "string"],
            "app": ["type": "string", "enum": apps.map(\.rawValue)],
            "columns": ["type": "array", "items": ["type": "string"]],
            "rows": ["type": "array", "items": ["type": "array", "items": ["type": "string"]]],
        ],
        "required": ["reply", "action"],
    ] }
}

struct OllamaClient: Sendable {
    struct Message: Codable, Sendable { let role: String; let content: String }

    enum Failure: LocalizedError {
        case notRunning, http(Int, String), pull(String)
        var errorDescription: String? {
            switch self {
            case .notRunning: return "Ollama läuft nicht."
            case let .http(code, body): return "Ollama-Fehler \(code): \(body)"
            case let .pull(msg): return "Modell-Download: \(msg)"
            }
        }
    }

    static let downloadURL = URL(string: "https://ollama.com/download/Ollama-darwin.zip")!
    static let brewBinaries = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]

    /// Wo Ollama.app liegt (falls installiert).
    static var appURL: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [URL(fileURLWithPath: "/Applications/Ollama.app"), home.appendingPathComponent("Applications/Ollama.app")]
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static var brewBinary: String? {
        brewBinaries.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isInstalled: Bool { appURL != nil || brewBinary != nil }

    /// Lädt Ollama.app herunter und legt sie nach ~/Applications (braucht kein Admin-Passwort).
    static func install() async throws {
        let (tmp, response) = try await URLSession.shared.download(from: downloadURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.http(0, "Download fehlgeschlagen") }
        let dest = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let status = Actions.run("/usr/bin/ditto", ["-x", "-k", tmp.path, dest.path])
        try? FileManager.default.removeItem(at: tmp)
        guard status == 0, appURL != nil else { throw Failure.http(0, "Entpacken fehlgeschlagen") }
    }

    /// Ist das Modell schon geladen?
    func hasModel() async -> Bool {
        var req = URLRequest(url: base.appendingPathComponent("api/tags"))
        req.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else { return false }
        let wanted = settings.model.contains(":") ? settings.model : settings.model + ":latest"
        return models.contains { ($0["name"] as? String) == wanted || ($0["model"] as? String) == wanted }
    }

    /// Lädt das Modell und meldet den Fortschritt (0…1, Statustext).
    func pull(progress: @escaping @Sendable (Double, String) -> Void) async throws {
        var req = URLRequest(url: base.appendingPathComponent("api/pull"))
        req.httpMethod = "POST"
        req.timeoutInterval = 3600
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": settings.model, "stream": true])
        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.pull("Server antwortet nicht") }
        for try await line in bytes.lines {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if let error = obj["error"] as? String { throw Failure.pull(error) }
            let status = obj["status"] as? String ?? ""
            if status == "success" { progress(1, "Fertig"); return }
            if let total = (obj["total"] as? NSNumber)?.doubleValue, total > 0 {
                let done = (obj["completed"] as? NSNumber)?.doubleValue ?? 0
                let gb = { (v: Double) in String(format: "%.1f", v / 1_000_000_000) }
                progress(done / total, "\(gb(done)) von \(gb(total)) GB")
            } else {
                progress(-1, status)
            }
        }
        guard await hasModel() else { throw Failure.pull("abgebrochen") }
    }

    let settings: Settings
    private var base: URL { URL(string: settings.ollamaHost)! }

    func isRunning() async -> Bool {
        var req = URLRequest(url: base.appendingPathComponent("api/tags"))
        req.timeoutInterval = 2
        guard let result = try? await URLSession.shared.data(for: req) else { return false }
        return (result.1 as? HTTPURLResponse)?.statusCode == 200
    }

    /// Startet Ollama, falls nötig, und wartet bis zu 30 Sekunden.
    func ensureRunning() async -> Bool {
        if await isRunning() { return true }
        if let app = Self.appURL {
            Actions.run("/usr/bin/open", ["-g", "-j", app.path])
        } else if let bin = Self.brewBinary {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = ["serve"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
        } else {
            return false
        }
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if await isRunning() { return true }
        }
        return false
    }

    /// Lädt das Modell in den Speicher, damit die erste Antwort schnell kommt.
    func warmUp() async {
        guard await ensureRunning() else { return }
        _ = try? await post("api/generate", ["model": settings.model, "keep_alive": "30m"], timeout: 120)
    }

    func chat(system: String, history: [Message], allowed: [AgentReply.Action], apps: [Tool]) async throws -> AgentReply {
        guard await ensureRunning() else { throw Failure.notRunning }
        let messages = [["role": "system", "content": system]]
            + history.suffix(20).map { ["role": $0.role, "content": $0.content] }
        let body: [String: Any] = [
            "model": settings.model,
            "messages": messages,
            "stream": false,
            "format": AgentReply.schema(allowed: allowed, apps: apps.isEmpty ? [.word] : apps),
            "keep_alive": "30m",
            "options": ["temperature": 0.4, "num_ctx": 8192],
        ]
        let data = try await post("api/chat", body, timeout: 300)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw Failure.http(200, "Unerwartete Antwort")
        }
        return Self.parse(content)
    }

    static func parse(_ content: String) -> AgentReply {
        if let d = content.data(using: .utf8),
           let r = try? JSONDecoder().decode(AgentReply.self, from: d),
           !r.reply.isEmpty || r.action != .none {
            return r
        }
        return AgentReply(reply: content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func post(_ path: String, _ body: [String: Any], timeout: TimeInterval) async throws -> Data {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Failure.http(code, String(decoding: data, as: UTF8.self)) }
        return data
    }
}
