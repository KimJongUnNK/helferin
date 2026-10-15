import AppKit
import Foundation

/// Korrigiert die Rechtschreibung in einem Word-Dokument (.docx) mit der deutschen Rechtschreibprüfung von macOS.
/// Das Original bleibt unverändert; es entsteht „<Name> (korrigiert).docx“ daneben.
@MainActor
enum Proofreader {
    struct Change: Sendable, Hashable {
        let from: String
        let to: String
    }

    struct Result: Sendable {
        let output: URL
        let changes: [Change]
    }

    enum Failure: LocalizedError {
        case notDocx, unreadable, writeFailed
        var errorDescription: String? {
            switch self {
            case .notDocx: return "Ich kann nur Word-Dokumente (.docx) korrigieren."
            case .unreadable: return "Das Dokument konnte ich nicht lesen."
            case .writeFailed: return "Die korrigierte Kopie konnte ich nicht speichern."
            }
        }
    }

    static let language = "de"

    static func correct(_ file: URL, fallbackDir: URL) throws -> Result {
        guard file.pathExtension.lowercased() == "docx" else { throw Failure.notDocx }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("helferlein-proof-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: work) }
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        guard Actions.run("/usr/bin/ditto", ["-x", "-k", file.path, work.path]) == 0 else { throw Failure.unreadable }

        let checker = NSSpellChecker.shared
        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: tag) }

        var changes: [Change] = []
        // Haupttext, Kopf-/Fußzeilen, Fußnoten
        let wordDir = work.appendingPathComponent("word")
        let parts = ((try? fm.contentsOfDirectory(atPath: wordDir.path)) ?? [])
            .filter { $0 == "document.xml" || $0.hasPrefix("header") || $0.hasPrefix("footer") || $0 == "footnotes.xml" }
        guard parts.contains("document.xml") else { throw Failure.unreadable }

        for part in parts {
            let url = wordDir.appendingPathComponent(part)
            guard let xml = try? XMLDocument(contentsOf: url, options: [.nodePreserveAll]) else { continue }
            let texts = (try? xml.nodes(forXPath: "//*[local-name()='t']")) ?? []
            var touched = false
            for node in texts {
                guard let text = node.stringValue, !text.isEmpty else { continue }
                let (fixed, found) = correctText(text, checker: checker, tag: tag)
                if !found.isEmpty {
                    node.stringValue = fixed
                    changes.append(contentsOf: found)
                    touched = true
                }
            }
            if touched {
                guard (try? xml.xmlData(options: [.nodePreserveAll]).write(to: url)) != nil else { throw Failure.writeFailed }
            }
        }

        let base = file.deletingPathExtension().lastPathComponent + " (korrigiert)"
        let dir = fm.isWritableFile(atPath: file.deletingLastPathComponent().path) ? file.deletingLastPathComponent() : fallbackDir
        var output = dir.appendingPathComponent(base + ".docx")
        var n = 2
        while fm.fileExists(atPath: output.path) {
            output = dir.appendingPathComponent("\(base) \(n).docx")
            n += 1
        }
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = work
        zip.arguments = ["-q", "-X", "-r", output.path, "."]
        try zip.run()
        zip.waitUntilExit()
        guard zip.terminationStatus == 0 else { throw Failure.writeFailed }

        // Gleiche Korrektur nur einmal melden
        var seen = Set<Change>()
        return Result(output: output, changes: changes.filter { seen.insert($0).inserted })
    }

    /// Ersetzt falsch geschriebene Wörter durch die sichere macOS-Korrektur.
    /// Bei unsicheren Fällen (mehrere Vorschläge, Abkürzungen, Zahlen) bleibt das Wort stehen.
    static func correctText(_ text: String, checker: NSSpellChecker, tag: Int) -> (String, [Change]) {
        let ns = NSMutableString(string: text)
        var changes: [Change] = []
        var offset = 0
        while offset < ns.length {
            let range = checker.checkSpelling(of: ns as String, startingAt: offset, language: language,
                                              wrap: false, inSpellDocumentWithTag: tag, wordCount: nil)
            guard range.location != NSNotFound, range.length > 0 else { break }
            let word = ns.substring(with: range)
            var replacement: String?
            if isCorrectable(word) {
                replacement = checker.correction(forWordRange: range, in: ns as String, language: language,
                                                 inSpellDocumentWithTag: tag)
                if replacement == nil,
                   let guesses = checker.guesses(forWordRange: range, in: ns as String, language: language,
                                                 inSpellDocumentWithTag: tag),
                   guesses.count == 1 {
                    replacement = guesses[0]
                }
            }
            if let replacement, replacement != word {
                ns.replaceCharacters(in: range, with: replacement)
                changes.append(Change(from: word, to: replacement))
                offset = range.location + (replacement as NSString).length
            } else {
                offset = range.location + range.length
            }
        }
        return (ns as String, changes)
    }

    /// Keine Abkürzungen (ABC), keine Zahlen/Codes, keine Ein-Buchstaben-Wörter.
    static func isCorrectable(_ word: String) -> Bool {
        guard word.count > 1, word.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        let letters = word.filter(\.isLetter)
        return !(letters.count > 1 && letters == letters.uppercased())
    }
}
