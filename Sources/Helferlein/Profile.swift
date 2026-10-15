import Foundation

/// Was die Person bei der ersten Nutzung eingibt. Liegt in ~/Library/Application Support/Helferlein/profile.json.
struct Profile: Codable, Equatable {
    var firstName: String
    var purposes: [String]
    var purposeNote: String
    var tools: [Tool]
    var style: Style

    static let purposeChoices = ["Briefe & Formulare", "Arbeit", "Schule & Studium", "Verein", "Privates & Hobby", "Einkaufen & Rezepte"]

    static var fileURL: URL { Settings.supportDir.appendingPathComponent("profile.json") }

    static func load() -> Profile? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Profile.self, from: data)
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Settings.supportDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: Self.fileURL, options: .atomic)
    }

    func has(_ tool: Tool) -> Bool { tools.contains(tool) }

    var purposeText: String {
        let note = purposeNote.trimmingCharacters(in: .whitespacesAndNewlines)
        return (purposes + (note.isEmpty ? [] : [note])).joined(separator: ", ")
    }
}

/// Programme, die der Agent benutzen darf. Anzeigenamen bewusst einfach gehalten.
enum Tool: String, Codable, CaseIterable, Identifiable {
    case word, pdf, powerpoint, internet
    var id: String { rawValue }

    var label: String {
        switch self {
        case .word: return "Word"
        case .pdf: return "PDF Acrobat"
        case .powerpoint: return "PowerPoint"
        case .internet: return "Internet"
        }
    }

    var detail: String {
        switch self {
        case .word: return "Briefe, Listen, Texte"
        case .pdf: return "PDFs erstellen und öffnen"
        case .powerpoint: return "Präsentationen"
        case .internet: return "Suchen und Webseiten im Brave Browser"
        }
    }

    var symbol: String {
        switch self {
        case .word: return "doc.text.fill"
        case .pdf: return "doc.richtext.fill"
        case .powerpoint: return "rectangle.on.rectangle.angled"
        case .internet: return "globe"
        }
    }
}

/// Wie der Agent redet.
enum Style: String, Codable, CaseIterable, Identifiable {
    case casual, ruhig, witzig, ehrenlos
    var id: String { rawValue }

    var label: String {
        switch self {
        case .casual: return "Casual"
        case .ruhig: return "Ruhig & genau"
        case .witzig: return "Witzig"
        case .ehrenlos: return "Ehrenlos"
        }
    }

    var detail: String {
        switch self {
        case .casual: return "Locker und freundlich, wie ein guter Freund."
        case .ruhig: return "Geduldig, langsam, Schritt für Schritt."
        case .witzig: return "Hilft gern – mit einem Augenzwinkern."
        case .ehrenlos: return "Frech, roastet dich liebevoll. Nichts für Zarte."
        }
    }

    var emoji: String {
        switch self {
        case .casual: return "😊"
        case .ruhig: return "🧘"
        case .witzig: return "😄"
        case .ehrenlos: return "😈"
        }
    }

    /// Sprechtempo je Stil (AVSpeechUtterance.rate).
    var rate: Float {
        switch self {
        case .casual: return 0.48
        case .ruhig: return 0.43
        case .witzig: return 0.5
        case .ehrenlos: return 0.52
        }
    }

    /// Anweisung für das Modell.
    var instruction: String {
        switch self {
        case .casual:
            return "Rede locker, herzlich und unkompliziert wie ein guter Freund. Kurze Sätze, gern mal ein „easy“ oder „passt“."
        case .ruhig:
            return "Rede ruhig, geduldig und sehr genau. Erkläre in kleinen, klaren Schritten. Keine Witze, keine Umgangssprache. Lieber einmal mehr nachfragen als etwas falsch machen."
        case .witzig:
            return "Rede humorvoll und gut gelaunt. Bau gern ein kleines Wortspiel oder einen lockeren Spruch ein, aber die Hilfe steht immer im Vordergrund."
        case .ehrenlos:
            return "Rede frech, schlagfertig und respektlos-lustig, wie ein bester Freund, der dich liebevoll roastet. Jugendsprache ist erlaubt („digga“, „lowkey“, „ehrenlos“, „wild“). Grenzen: keine echten Beleidigungen, keine Schimpfwörter unter der Gürtellinie, nichts über Aussehen, Herkunft oder Religion. Die Aufgabe erledigst du trotzdem perfekt. Der Inhalt von Dokumenten bleibt seriös, außer sie will es ausdrücklich anders."
        }
    }

    func greeting(name: String, timeGreeting: String) -> String {
        switch self {
        case .casual: return "Hey \(name)! Brauchst du heute Hilfe?"
        case .ruhig: return "\(timeGreeting), \(name). Brauchst du heute Hilfe? Ich nehme mir gern Zeit für dich."
        case .witzig: return "\(timeGreeting), \(name)! Dein Helferlein meldet sich zum Dienst. Brauchst du heute Hilfe?"
        case .ehrenlos: return "Yo \(name), na, was hast du heute wieder verbockt? Spaß. Brauchst du Hilfe?"
        }
    }

    func reprompt(name: String) -> String {
        switch self {
        case .casual: return "\(name), hörst du mich?"
        case .ruhig: return "\(name), hörst du mich? Lass dir ruhig Zeit."
        case .witzig: return "\(name), hörst du mich? Oder rede ich gerade mit der Kaffeemaschine?"
        case .ehrenlos: return "\(name), hörst du mich? Oder bist du eingepennt, digga?"
        }
    }

    func sample(name: String) -> String {
        switch self {
        case .casual: return "Hey \(name), easy, das machen wir zusammen."
        case .ruhig: return "Hallo \(name). Wir machen das ganz in Ruhe, Schritt für Schritt."
        case .witzig: return "Hallo \(name)! Ich bin schneller als jeder Kugelschreiber – und kleckse nie."
        case .ehrenlos: return "Yo \(name), lass mich das machen, bevor du wieder alles zerschießt."
        }
    }
}
