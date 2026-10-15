import Foundation

/// Alles, was Helferlein am Mac tun darf: Dokumente bauen, Dateien öffnen, Brave benutzen.
struct Actions {
    enum Failure: LocalizedError {
        case helperMissing, helper(String), badURL(String)
        var errorDescription: String? {
            switch self {
            case .helperMissing: return "Das Dokument-Werkzeug fehlt. Bitte install.sh nochmal ausführen."
            case let .helper(msg): return "Dokument-Werkzeug: \(msg)"
            case let .badURL(s): return "Ungültige Adresse: \(s)"
            }
        }
    }

    let settings: Settings

    static let wordExtensions: Set<String> = ["docx", "doc", "odt", "rtf", "txt"]
    static let deckExtensions: Set<String> = ["pptx", "ppt", "odp"]
    static let gridExtensions: Set<String> = ["xlsx", "xls", "ods", "csv"]
    static let pdfExtensions: Set<String> = ["pdf"]

    // MARK: Dokumente

    func createDocument(title: String, sections: [AgentReply.Section]) throws -> URL {
        try runHelper([
            "kind": "docx", "title": title, "out_dir": settings.outputDir.path,
            "sections": sections.map { ["heading": $0.heading, "text": $0.text] },
        ])
    }

    func createPDF(title: String, sections: [AgentReply.Section]) throws -> URL {
        try runHelper([
            "kind": "pdf", "title": title, "out_dir": settings.outputDir.path,
            "sections": sections.map { ["heading": $0.heading, "text": $0.text] },
        ])
    }

    func createPresentation(title: String, slides: [AgentReply.Slide]) throws -> URL {
        try runHelper([
            "kind": "pptx", "title": title, "out_dir": settings.outputDir.path,
            "slides": slides.map { ["title": $0.title, "bullets": $0.bullets] },
        ])
    }

    private func runHelper(_ payload: [String: Any]) throws -> URL {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: settings.pythonURL.path),
              fm.fileExists(atPath: settings.helperURL.path) else { throw Failure.helperMissing }

        let p = Process()
        p.executableURL = settings.pythonURL
        p.arguments = [settings.helperURL.path]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = errors
        try p.run()
        input.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: payload))
        try? input.fileHandleForWriting.close()
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = errors.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        guard p.terminationStatus == 0 else {
            throw Failure.helper(String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let path = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: path)
    }

    // MARK: Öffnen

    /// Öffnet die Datei in der passenden Craft-App.
    /// Gibt den einfachen Anzeigenamen zurück („Word“, „PDF Acrobat“, „PowerPoint“ …).
    @discardableResult
    func open(_ file: URL) -> String {
        let ext = file.pathExtension.lowercased()
        let target: (app: String, label: String)? =
            Self.wordExtensions.contains(ext) ? (settings.wordApp, Tool.word.label) :
            Self.pdfExtensions.contains(ext) ? (settings.pdfApp, Tool.pdf.label) :
            Self.deckExtensions.contains(ext) ? (settings.deckApp, Tool.powerpoint.label) :
            Self.gridExtensions.contains(ext) ? (settings.gridApp, "Excel") : nil
        if let target, Self.run("/usr/bin/open", ["-a", target.app, file.path]) == 0 { return target.label }
        Self.run("/usr/bin/open", [file.path]) // Fallback: Standard-App
        return "der Standard-App"
    }

    /// Sucht in den üblichen Ordnern nach einem Dokument. Leere Suche = neuestes Helferlein-Dokument.
    func findFile(_ query: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let allExt = Self.wordExtensions.union(Self.deckExtensions).union(Self.gridExtensions).union(Self.pdfExtensions)
        let words = Self.searchWords(query)

        let roots = words.isEmpty ? [settings.outputDir] : [
            settings.outputDir,
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"),
        ]

        var best: (score: Int, date: Date, url: URL)?
        for root in roots {
            guard let e = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                if e.level > 4 { e.skipDescendants(); continue }
                guard allExt.contains(url.pathExtension.lowercased()) else { continue }
                let name = Self.normalize(url.deletingPathExtension().lastPathComponent)
                let score = words.isEmpty ? 1 : words.filter { name.contains($0) }.count
                guard score > 0 else { continue }
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if best == nil || score > best!.score || (score == best!.score && date > best!.date) {
                    best = (score, date, url)
                }
            }
        }
        return best?.url
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }

    static let stopWords: Set<String> = ["der", "die", "das", "den", "dem", "mein", "meine", "meinen",
                                         "dokument", "datei", "von", "vom", "an", "fur", "mit", "und", "ein", "eine"]

    static func searchWords(_ query: String) -> [String] {
        normalize(query)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !stopWords.contains($0) }
    }

    // MARK: Brave

    func openWebsite(_ raw: String) throws {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "https://" + s }
        guard let url = URL(string: s), url.host?.contains(".") == true else { throw Failure.badURL(raw) }
        openInBrowser(url)
    }

    func webSearch(_ query: String) {
        var c = URLComponents(string: "https://search.brave.com/search")!
        c.queryItems = [URLQueryItem(name: "q", value: query)]
        openInBrowser(c.url!)
    }

    private func openInBrowser(_ url: URL) {
        if Self.run("/usr/bin/open", ["-a", settings.browserApp, url.absoluteString]) != 0 {
            Self.run("/usr/bin/open", [url.absoluteString]) // Brave fehlt → Standardbrowser
        }
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
