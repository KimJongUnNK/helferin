import Foundation

/// Strukturierte Antwort des Modells. Ollama erzwingt dieses Format per JSON-Schema.
struct AgentReply: Decodable {
    enum Action: String, CaseIterable {
        case none, create_document, create_pdf, create_presentation, open_file, open_website, web_search, close

        /// Welche Aktionen das Profil erlaubt (abgewählte Programme fallen raus).
        static func allowed(for profile: Profile) -> [Action] {
            allCases.filter {
                switch $0 {
                case .create_document: return profile.has(.word)
                case .create_pdf: return profile.has(.pdf)
                case .create_presentation: return profile.has(.powerpoint)
                case .open_website, .web_search: return profile.has(.internet)
                case .none, .open_file, .close: return true
                }
            }
        }
    }
    struct Section: Codable { var heading: String; var text: String }
    struct Slide: Codable { var title: String; var bullets: [String] }

    var reply: String
    var action: Action
    var title: String?
    var sections: [Section]?
    var slides: [Slide]?
    var query: String?
    var url: String?

    enum CodingKeys: String, CodingKey { case reply, action, title, sections, slides, query, url }

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
    }

    static func schema(allowed: [Action]) -> [String: Any] { [
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
        ],
        "required": ["reply", "action"],
    ] }
}

struct OllamaClient {
    struct Message: Codable { let role: String; let content: String }

    enum Failure: LocalizedError {
        case notRunning, http(Int, String)
        var errorDescription: String? {
            switch self {
            case .notRunning: return "Ollama läuft nicht."
            case let .http(code, body): return "Ollama-Fehler \(code): \(body)"
            }
        }
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
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-g", "-a", "Ollama"]
        try? p.run()
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

    func chat(system: String, history: [Message], allowed: [AgentReply.Action]) async throws -> AgentReply {
        guard await ensureRunning() else { throw Failure.notRunning }
        let messages = [["role": "system", "content": system]]
            + history.suffix(20).map { ["role": $0.role, "content": $0.content] }
        let body: [String: Any] = [
            "model": settings.model,
            "messages": messages,
            "stream": false,
            "format": AgentReply.schema(allowed: allowed),
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
