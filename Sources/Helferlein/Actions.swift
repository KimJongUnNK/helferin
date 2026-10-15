import AppKit
import Foundation
import UniformTypeIdentifiers

/// Alles, was Helferlein am Mac tun darf: Dokumente bauen, Programme und Dateien öffnen, Brave benutzen.
struct Actions: Sendable {
    enum Failure: LocalizedError {
        case helperMissing, helper(String), badURL(String)
        var errorDescription: String? {
            switch self {
            case .helperMissing: return "Das Dokument-Werkzeug fehlt. Bitte Helferlein neu installieren."
            case let .helper(msg): return "Dokument-Werkzeug: \(msg)"
            case let .badURL(s): return "Ungültige Adresse: \(s)"
            }
        }
    }

    /// Ergebnis beim Öffnen: in welchem Programm, und ggf. ein Hinweis für die Person.
    struct OpenResult: Sendable {
        let label: String
        var hint: String? = nil
    }

    let settings: Settings

    // MARK: Dokumente erstellen

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

    func createSpreadsheet(title: String, columns: [String], rows: [[String]]) throws -> URL {
        try runHelper([
            "kind": "xlsx", "title": title, "out_dir": settings.outputDir.path,
            "columns": columns, "rows": rows,
        ])
    }

    /// Sprache der erstellten Dokumente: Deutsch mit der Region dieses Macs (de-AT, de-CH …), sonst de-DE.
    static var documentLanguage: String {
        let region = Locale.current.region?.identifier.uppercased() ?? ""
        return ["AT", "CH", "LI", "LU", "BE"].contains(region) ? "de-\(region)" : "de-DE"
    }

    private func runHelper(_ request: [String: Any]) throws -> URL {
        var payload = request
        payload["lang"] = Self.documentLanguage
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: settings.pythonURL.path),
              fm.fileExists(atPath: settings.helperURL.path) else { throw Failure.helperMissing }

        let p = Process()
        p.executableURL = settings.pythonURL
        p.arguments = ["-I", settings.helperURL.path]
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

    /// Prüft, ob das Dokument-Werkzeug startklar ist (Python + Bibliotheken).
    func helperWorks() -> Bool {
        guard FileManager.default.isExecutableFile(atPath: settings.pythonURL.path) else { return false }
        return Self.run(settings.pythonURL.path, ["-I", "-c", "import docx, pptx, reportlab, openpyxl"]) == 0
    }

    // MARK: Programme

    func appURL(for tool: Tool) -> URL? {
        AppLocator.find(settings.appNames(for: tool))
    }

    func installedTools() -> Set<Tool> {
        Set(Tool.allCases.filter { appURL(for: $0) != nil })
    }

    /// Startet ein Programm ohne Datei („Öffne mir PowerPoint“).
    func launch(_ tool: Tool) -> OpenResult {
        guard let app = appURL(for: tool) else {
            return OpenResult(label: tool.label, hint: "\(tool.label) ist auf diesem Mac nicht installiert.")
        }
        Self.run("/usr/bin/open", ["-a", app.path])
        return OpenResult(label: tool.label)
    }

    // MARK: Dateien öffnen

    /// Öffnet die Datei im passenden ArtCraft-Programm.
    /// Meldet das Programm das Format bei macOS nicht an (z. B. DeckCraft bei .pptx), geht es über seinen Öffnen-Dialog.
    func open(_ file: URL) -> OpenResult {
        let ext = file.pathExtension.lowercased()
        guard let tool = Tool.forExtension(ext), let app = appURL(for: tool) else {
            Self.run("/usr/bin/open", [file.path]) // Standard-App
            return OpenResult(label: "der Standard-App")
        }

        if AppLocator.declares(app, fileExtension: ext),
           Self.run("/usr/bin/open", ["-a", app.path, file.path]) == 0 {
            return OpenResult(label: tool.label)
        }
        if Self.openViaDialog(app: app, file: file) {
            return OpenResult(label: tool.label,
                              hint: "Falls die Datei nicht aufgeht: In \(tool.label) auf „Open“ klicken und „\(file.lastPathComponent)“ wählen.")
        }
        // Ohne Erlaubnis für Bedienungshilfen: Programm öffnen, Datei im Finder zeigen, erklären
        Self.run("/usr/bin/open", ["-a", app.path])
        Self.run("/usr/bin/open", ["-R", file.path])
        return OpenResult(label: tool.label, hint: """
            \(tool.label) nimmt die Datei nicht direkt an. Klick dort auf „Open“ und wähl „\(file.lastPathComponent)“ – \
            ich hab sie dir im Finder markiert. Wenn du Helferlein in den Einstellungen unter „Bedienungshilfen“ erlaubst, \
            mache ich das künftig automatisch.
            """)
    }

    /// Öffnet die Datei über ⌘O → ⌘⇧G (Pfad einfügen) → Enter im Programm.
    /// Braucht einmalig die Erlaubnis „Bedienungshilfen“. Gibt false zurück, wenn das nicht geht.
    static func openViaDialog(app: URL, file: URL) -> Bool {
        let script = """
        on run argv
            set filePath to item 1 of argv
            set appPath to item 2 of argv
            set appName to item 3 of argv
            set oldClip to ""
            try
                set oldClip to the clipboard as text
            end try
            do shell script "open -a " & quoted form of appPath
            delay 2
            tell application "System Events"
                tell process appName to set frontmost to true
                delay 0.5
                keystroke "o" using command down
                delay 1.2
                set the clipboard to filePath
                keystroke "g" using {command down, shift down}
                delay 0.8
                keystroke "v" using command down
                delay 0.5
                key code 36
                delay 0.8
                key code 36
            end tell
            delay 0.3
            set the clipboard to oldClip
        end run
        """
        let appName = app.deletingPathExtension().lastPathComponent
        return run("/usr/bin/osascript", ["-e", script, file.path, app.path, appName]) == 0
    }

    /// Sucht in den üblichen Ordnern nach einer Datei. Leere Suche = neueste Helferlein-Datei.
    /// `extensions` schränkt die Dateitypen ein (z. B. nur ["docx"]); nil = alle bekannten.
    func findFile(_ query: String, extensions: Set<String>? = nil) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let allExt = extensions ?? Tool.allCases.reduce(into: Set<String>()) { $0.formUnion($1.fileExtensions) }
        let words = Self.searchWords(query)

        let roots = words.isEmpty ? [settings.outputDir] : [
            settings.outputDir,
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Pictures"),
            home.appendingPathComponent("Movies"),
            home.appendingPathComponent("Music"),
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
        if let brave = appURL(for: .internet), Self.run("/usr/bin/open", ["-a", brave.path, url.absoluteString]) == 0 { return }
        Self.run("/usr/bin/open", [url.absoluteString]) // Brave fehlt → Standardbrowser
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

/// Findet installierte Apps und prüft, welche Dateiformate sie bei macOS anmelden.
enum AppLocator {
    static var searchDirs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
    }

    /// Erster Treffer für einen der Namen: erst exakt, dann „enthält“ (Groß-/Kleinschreibung egal), bis 2 Ordner tief.
    static func find(_ names: [String]) -> URL? {
        let apps = allApps()
        let key = { (u: URL) in u.deletingPathExtension().lastPathComponent.lowercased().replacingOccurrences(of: " ", with: "") }
        for name in names {
            let n = name.lowercased().replacingOccurrences(of: " ", with: "")
            if let hit = apps.first(where: { key($0) == n }) { return hit }
        }
        for name in names {
            let n = name.lowercased().replacingOccurrences(of: " ", with: "")
            if let hit = apps.first(where: { key($0).contains(n) }) { return hit }
        }
        return nil
    }

    static func allApps() -> [URL] {
        var result: [URL] = []
        for dir in searchDirs {
            guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for item in items {
                if item.pathExtension == "app" {
                    result.append(item)
                } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                          let sub = try? FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil) {
                    result.append(contentsOf: sub.filter { $0.pathExtension == "app" })
                }
            }
        }
        return result
    }

    /// Hat die App dieses Format in ihrer Info.plist angemeldet?
    static func declares(_ app: URL, fileExtension ext: String) -> Bool {
        guard let info = Bundle(url: app)?.infoDictionary,
              let types = info["CFBundleDocumentTypes"] as? [[String: Any]] else { return false }
        let fileType = UTType(filenameExtension: ext)
        for t in types {
            if let exts = t["CFBundleTypeExtensions"] as? [String],
               exts.contains(where: { $0.lowercased() == ext || $0 == "*" }) { return true }
            if let ids = t["LSItemContentTypes"] as? [String], let fileType,
               ids.contains(where: { id in UTType(id).map { fileType.conforms(to: $0) } ?? false }) { return true }
        }
        return false
    }
}
