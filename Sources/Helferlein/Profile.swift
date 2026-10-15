import Foundation

/// Was die Person bei der ersten Nutzung eingibt. Liegt in ~/Library/Application Support/Helferlein/profile.json.
struct Profile: Codable, Equatable, Sendable {
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

    init(firstName: String, purposes: [String], purposeNote: String, tools: [Tool], style: Style) {
        self.firstName = firstName
        self.purposes = purposes
        self.purposeNote = purposeNote
        self.tools = tools
        self.style = style
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstName = try c.decode(String.self, forKey: .firstName)
        purposes = (try? c.decode([String].self, forKey: .purposes)) ?? []
        purposeNote = (try? c.decode(String.self, forKey: .purposeNote)) ?? ""
        tools = ((try? c.decode([String].self, forKey: .tools)) ?? []).compactMap(Tool.init(rawValue:))
        style = (try? c.decode(Style.self, forKey: .style)) ?? .casual
    }

    func has(_ tool: Tool) -> Bool { tools.contains(tool) }

    var purposeText: String {
        let note = purposeNote.trimmingCharacters(in: .whitespacesAndNewlines)
        return (purposes + (note.isEmpty ? [] : [note])).joined(separator: ", ")
    }
}

/// Programme, die der Agent benutzen darf: die ArtCraft-Familie + Brave.
/// Anzeigenamen bewusst so, wie man sie kennt (Word statt WordCraft usw.).
enum Tool: String, Codable, CaseIterable, Identifiable, Sendable {
    // Büro
    case word, excel, powerpoint, pdf
    // Kreativ
    case photoshop, lightroom, illustrator, indesign, premiere, aftereffects, protools, autocad, figma
    // Internet
    case internet

    var id: String { rawValue }

    enum Group: String, CaseIterable, Identifiable {
        case office = "Büro", creative = "Kreativ", web = "Internet"
        var id: String { rawValue }
    }

    var group: Group {
        switch self {
        case .word, .excel, .powerpoint, .pdf: return .office
        case .internet: return .web
        default: return .creative
        }
    }

    var label: String {
        switch self {
        case .word: return "Word"
        case .excel: return "Excel"
        case .powerpoint: return "PowerPoint"
        case .pdf: return "PDF Acrobat"
        case .photoshop: return "Photoshop"
        case .lightroom: return "Lightroom"
        case .illustrator: return "Illustrator"
        case .indesign: return "InDesign"
        case .premiere: return "Premiere"
        case .aftereffects: return "After Effects"
        case .protools: return "Pro Tools"
        case .autocad: return "AutoCAD"
        case .figma: return "Figma"
        case .internet: return "Internet"
        }
    }

    var detail: String {
        switch self {
        case .word: return "Briefe, Listen, Texte"
        case .excel: return "Tabellen, Haushaltsbuch, Listen"
        case .powerpoint: return "Präsentationen"
        case .pdf: return "PDFs erstellen und öffnen"
        case .photoshop: return "Fotos bearbeiten"
        case .lightroom: return "Fotos sortieren und entwickeln"
        case .illustrator: return "Logos und Grafiken"
        case .indesign: return "Flyer, Plakate, Zeitungen"
        case .premiere: return "Videos schneiden"
        case .aftereffects: return "Animationen und Effekte"
        case .protools: return "Audio und Musik"
        case .autocad: return "Pläne und Zeichnungen"
        case .figma: return "App- und Web-Design"
        case .internet: return "Suchen und Webseiten im Brave Browser"
        }
    }

    var symbol: String {
        switch self {
        case .word: return "doc.text.fill"
        case .excel: return "tablecells.fill"
        case .powerpoint: return "rectangle.on.rectangle.angled"
        case .pdf: return "doc.richtext.fill"
        case .photoshop: return "photo.fill"
        case .lightroom: return "camera.aperture"
        case .illustrator: return "pencil.and.outline"
        case .indesign: return "newspaper.fill"
        case .premiere: return "film.fill"
        case .aftereffects: return "sparkles.tv.fill"
        case .protools: return "waveform"
        case .autocad: return "ruler.fill"
        case .figma: return "square.on.circle"
        case .internet: return "globe"
        }
    }

    /// Mögliche App-Namen auf dem Mac (aktueller Name zuerst, dann frühere).
    var appNames: [String] {
        switch self {
        case .word: return ["WordCraft"]
        case .excel: return ["GridCraft"]
        case .powerpoint: return ["DeckCraft"]
        case .pdf: return ["PdfCraft", "PDFCraft", "PrintCraft"]
        case .photoshop: return ["PhotoCraft"]
        case .lightroom: return ["LightCraft"]
        case .illustrator: return ["VectorCraft"]
        case .indesign: return ["DesignCraft"]
        case .premiere: return ["FilmCraft"]
        case .aftereffects: return ["EffectCraft"]
        case .protools: return ["SoundCraft"]
        case .autocad: return ["CADCraft", "CadCraft"]
        case .figma: return ["FigCraft"]
        case .internet: return ["Brave Browser"]
        }
    }

    /// Dateiendungen, die zu diesem Programm gehören.
    var fileExtensions: Set<String> {
        switch self {
        case .word: return ["docx", "doc", "odt", "rtf", "txt", "md"]
        case .excel: return ["xlsx", "xls", "ods", "csv"]
        case .powerpoint: return ["pptx", "ppt", "potx", "ppsx", "odp"]
        case .pdf: return ["pdf"]
        case .photoshop: return ["psd", "png", "jpg", "jpeg", "heic", "webp", "tif", "tiff", "gif", "bmp"]
        case .lightroom: return ["dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2"]
        case .illustrator: return ["svg", "ai", "eps"]
        case .indesign: return ["indd", "idml"]
        case .premiere: return ["mp4", "mov", "m4v", "avi", "mkv"]
        case .aftereffects: return ["aep"]
        case .protools: return ["wav", "mp3", "aiff", "aif", "m4a", "flac"]
        case .autocad: return ["dwg", "dxf"]
        case .figma: return ["fig"]
        case .internet: return []
        }
    }

    /// Welches Programm öffnet diese Dateiendung?
    static func forExtension(_ ext: String) -> Tool? {
        let e = ext.lowercased()
        return allCases.first { $0.fileExtensions.contains(e) }
    }

    /// Standardauswahl bei der Einrichtung: Büro + Internet, Kreativ-Apps nur wenn installiert.
    static func defaultSelection(installed: Set<Tool>) -> Set<Tool> {
        Set(allCases.filter { $0.group != .creative || installed.contains($0) })
    }
}

/// Wie der Agent redet.
enum Style: String, Codable, CaseIterable, Identifiable, Sendable {
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
