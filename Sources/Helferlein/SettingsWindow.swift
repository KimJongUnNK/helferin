import AppKit
import ApplicationServices
import AVFoundation
import Speech
import SwiftUI

/// Eigenes Einstellungsfenster (Zahnrad im Helferlein-Fenster).
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let assistant: Assistant
    private let setup: SetupManager

    init(assistant: Assistant, setup: SetupManager) {
        self.assistant = assistant
        self.setup = setup
    }

    func show(pane: SettingsPane = .profile) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 580),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Helferlein – Einstellungen"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(
                rootView: SettingsWindowView(assistant: assistant, setup: setup, initialPane: pane))
            w.setContentSize(NSSize(width: 780, height: 580))
            w.minSize = NSSize(width: 680, height: 480)
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case profile, programs, voice, listening, ai, documents, system, maintenance
    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: return "Profil & Stil"
        case .programs: return "Programme"
        case .voice: return "Stimme"
        case .listening: return "Zuhören & Mikrofon"
        case .ai: return "KI-Modell"
        case .documents: return "Dokumente"
        case .system: return "System & Rechte"
        case .maintenance: return "Wartung & Hilfe"
        }
    }

    var symbol: String {
        switch self {
        case .profile: return "person.crop.circle.fill"
        case .programs: return "square.grid.2x2.fill"
        case .voice: return "speaker.wave.2.fill"
        case .listening: return "mic.fill"
        case .ai: return "brain.head.profile"
        case .documents: return "doc.text.fill"
        case .system: return "lock.shield.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        }
    }
}

struct SettingsWindowView: View {
    @ObservedObject var assistant: Assistant
    @ObservedObject var setup: SetupManager
    @State private var pane: SettingsPane?

    init(assistant: Assistant, setup: SetupManager, initialPane: SettingsPane) {
        self.assistant = assistant
        self.setup = setup
        _pane = State(initialValue: initialPane)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { p in
                Label(p.title, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            Group {
                switch pane ?? .profile {
                case .profile: ProfilePane(assistant: assistant)
                case .programs: ProgramsPane(assistant: assistant, setup: setup)
                case .voice: VoicePane(assistant: assistant)
                case .listening: ListeningPane(assistant: assistant)
                case .ai: AIPane(assistant: assistant)
                case .documents: DocumentsPane(assistant: assistant)
                case .system: SystemPane(assistant: assistant)
                case .maintenance: MaintenancePane(assistant: assistant)
                }
            }
            .formStyle(.grouped)
            .navigationTitle((pane ?? .profile).title)
        }
    }
}

// MARK: - Bindings

@MainActor
private func setting<T>(_ a: Assistant, _ kp: WritableKeyPath<Settings, T>) -> Binding<T> {
    Binding(get: { a.settings[keyPath: kp] }, set: { v in a.updateSettings { $0[keyPath: kp] = v } })
}

@MainActor
private func profileValue<T>(_ a: Assistant, _ kp: WritableKeyPath<Profile, T>, fallback: T) -> Binding<T> {
    Binding(get: { a.profile?[keyPath: kp] ?? fallback }, set: { v in a.updateProfile { $0[keyPath: kp] = v } })
}

private func hint(_ text: String) -> some View {
    Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
}

// MARK: - Profil & Stil

private struct ProfilePane: View {
    @ObservedObject var assistant: Assistant

    var body: some View {
        Form {
            Section("Über dich") {
                TextField("Vorname", text: profileValue(assistant, \.firstName, fallback: ""))
                hint("So spricht Helferlein dich an – auch bei „\(assistant.profile?.firstName ?? "Name"), hörst du mich?“.")
            }
            Section("Wofür brauchst du Helferlein?") {
                ForEach(Profile.purposeChoices, id: \.self) { choice in
                    Toggle(choice, isOn: Binding(
                        get: { assistant.profile?.purposes.contains(choice) ?? false },
                        set: { on in assistant.updateProfile { p in
                            if on { if !p.purposes.contains(choice) { p.purposes.append(choice) } }
                            else { p.purposes.removeAll { $0 == choice } }
                        } }))
                }
                TextField("In eigenen Worten", text: profileValue(assistant, \.purposeNote, fallback: ""), axis: .vertical)
                    .lineLimit(1...3)
            }
            Section("Wie soll Helferlein mit dir reden?") {
                Picker("Stil", selection: profileValue(assistant, \.style, fallback: .casual)) {
                    ForEach(Style.allCases) { s in Text("\(s.emoji)  \(s.label)").tag(s) }
                }
                .pickerStyle(.radioGroup)
                if let s = assistant.profile?.style {
                    hint(s.detail)
                }
                Button("Probehören") { assistant.previewVoice() }
            }
            Section {
                Button("Einrichtung komplett neu durchgehen …") { assistant.editProfile() }
                hint("Öffnet die Einrichtung im Helferlein-Fenster oben rechts.")
            }
        }
    }
}

// MARK: - Programme

private struct ProgramsPane: View {
    @ObservedObject var assistant: Assistant
    @ObservedObject var setup: SetupManager
    @State private var wordcraftGerman = false

    var body: some View {
        Form {
            ForEach(Tool.Group.allCases) { group in
                Section(group.rawValue) {
                    ForEach(Tool.allCases.filter { $0.group == group }) { tool in
                        ToolRow(assistant: assistant, tool: tool)
                    }
                }
            }
            Section("Internet") {
                Picker("Suchmaschine", selection: setting(assistant, \.searchEngine)) {
                    ForEach(Settings.SearchEngine.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("Browser (App-Name)", text: setting(assistant, \.browser))
                hint("Standard ist „Brave Browser“. Fehlt der Browser, nimmt Helferlein den Standardbrowser.")
            }
            Section("Word auf Deutsch") {
                LabeledContent("Status") {
                    Text(wordcraftGerman ? "Installiert ✓" : "Nicht installiert")
                        .foregroundStyle(wordcraftGerman ? Color.green : Color.secondary)
                }
                hint("WordCraft prüft von sich aus kein Deutsch. Das Deutsch-Paket bringt deutsche Rechtschreibprüfung (mit Komposita und Vorschlägen), deutsche Wörterbücher und eine deutsche Oberfläche. Nach einem WordCraft-Update erneut ausführen.")
                HStack {
                    Button(wordcraftGerman ? "Erneut ausführen" : "Installieren") { WordCraftGerman.runInstaller() }
                    if wordcraftGerman {
                        Button("Original wiederherstellen") { WordCraftGerman.runInstaller(restore: true) }
                    }
                }
            }
            Section {
                HStack {
                    Button("ArtCraft-Programme laden") { NSWorkspace.shared.open(SetupManager.artCraftLauncher) }
                    Button("Brave laden") { NSWorkspace.shared.open(SetupManager.braveDownload) }
                    Button("Neu suchen") { setup.refreshTools() }
                }
            }
        }
        .onAppear { wordcraftGerman = WordCraftGerman.isInstalled }
    }
}

private struct ToolRow: View {
    @ObservedObject var assistant: Assistant
    let tool: Tool

    var body: some View {
        let app = assistant.actions.appURL(for: tool)
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { assistant.profile?.has(tool) ?? false },
                set: { on in assistant.updateProfile { p in
                    if on { if !p.tools.contains(tool) { p.tools.append(tool) } } else { p.tools.removeAll { $0 == tool } }
                } })) {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tool.label).font(.body.weight(.medium))
                        Text("\(tool.detail) · \(tool == .internet ? assistant.settings.browser : tool.appNames[0])")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: tool.symbol).foregroundStyle(Color.accentColor)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: app == nil ? "xmark.circle" : "checkmark.circle.fill")
                    .foregroundStyle(app == nil ? Color.secondary : Color.green)
                Text(app?.path ?? "Nicht gefunden").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("App wählen …") { chooseApp() }.controlSize(.small)
                if assistant.settings.appPaths[tool.rawValue] != nil {
                    Button("Automatisch") { assistant.updateSettings { $0.appPaths[tool.rawValue] = nil } }.controlSize(.small)
                }
                if app != nil {
                    Button("Testen") {
                        let actions = assistant.actions
                        Task.detached { _ = actions.launch(tool) }
                    }.controlSize(.small)
                }
            }
            .padding(.leading, 28)
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "App für \(tool.label) wählen"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            assistant.updateSettings { $0.appPaths[tool.rawValue] = url.path }
        }
    }
}

// MARK: - Stimme

private struct VoicePane: View {
    @ObservedObject var assistant: Assistant
    @State private var voices: [AVSpeechSynthesisVoice] = []

    var body: some View {
        Form {
            Section("Stimme") {
                Picker("Stimme", selection: setting(assistant, \.voiceName)) {
                    Text("Automatisch (beste weibliche Stimme)").tag("")
                    ForEach(voices, id: \.identifier) { v in
                        Text("\(v.name) · \(SpeechIO.qualityLabel(v)) · \(v.language)").tag(v.identifier)
                    }
                }
                HStack {
                    Button("Probehören") { assistant.previewVoice() }
                    Button("Schönere Stimmen laden …") { SetupManager.openVoiceSettings() }
                }
                hint("Am natürlichsten klingt „Anna (Premium)“: Systemeinstellungen › Bedienungshilfen › Gesprochene Inhalte › Systemstimme › Stimmen verwalten › Deutsch. Danach hier „Automatisch“ lassen oder Anna wählen.")
            }
            Section("Klang") {
                Toggle("Tempo vom Sprechstil übernehmen", isOn: Binding(
                    get: { assistant.settings.speechRate == 0 },
                    set: { on in assistant.updateSettings { $0.speechRate = on ? 0 : 0.48 } }))
                if assistant.settings.speechRate > 0 {
                    LabeledContent("Tempo") {
                        Slider(value: setting(assistant, \.speechRate), in: 0.35...0.6) {
                            EmptyView()
                        } minimumValueLabel: { Text("langsam") } maximumValueLabel: { Text("schnell") }
                    }
                }
                LabeledContent("Tonhöhe") {
                    Slider(value: setting(assistant, \.voicePitch), in: 0.8...1.3) {
                        EmptyView()
                    } minimumValueLabel: { Text("tiefer") } maximumValueLabel: { Text("höher") }
                }
                LabeledContent("Lautstärke") {
                    Slider(value: setting(assistant, \.voiceVolume), in: 0.2...1.0) {
                        EmptyView()
                    } minimumValueLabel: { Image(systemName: "speaker.fill") } maximumValueLabel: { Image(systemName: "speaker.wave.3.fill") }
                }
                Button("Klang zurücksetzen") {
                    assistant.updateSettings { $0.speechRate = 0; $0.voicePitch = 1.05; $0.voiceVolume = 1 }
                }
            }
        }
        .onAppear { voices = SpeechIO.germanVoices }
    }
}

// MARK: - Zuhören & Mikrofon

private struct ListeningPane: View {
    @ObservedObject var assistant: Assistant
    @State private var devices: [AudioInputDevice] = []
    @State private var micUID = ""
    @State private var testing = false
    @State private var testLevel: Float = 0
    @State private var testError: String?
    @State private var trusted = false

    var body: some View {
        Form {
            Section("Mikrofon") {
                Picker("Mikrofon", selection: $micUID) {
                    Text("Systemstandard (\(AudioDevices.defaultInputName() ?? "–"))").tag("")
                    ForEach(devices) { d in Text(d.name).tag(d.uid) }
                }
                .onChange(of: micUID) { uid in
                    AudioDevices.selectedUID = uid.isEmpty ? nil : uid
                    if testing { Task { await restartTest() } }
                }
                HStack(spacing: 12) {
                    Button(testing ? "Test stoppen" : "Mikrofon testen") {
                        if testing { stopTest() } else { Task { await restartTest() } }
                    }
                    if testing {
                        LevelBar(level: testLevel)
                        Text("Sprich etwas …").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Liste aktualisieren") { devices = AudioDevices.inputDevices() }
                }
                if let testError { Text(testError).font(.caption).foregroundStyle(.orange) }
            }
            Section("Aktivieren") {
                Toggle("⌘ zweimal drücken = Helferlein hört zu", isOn: setting(assistant, \.doubleCommand))
                hint("Funktioniert in jedem Programm: zweimal kurz die Befehlstaste (⌘) drücken, und Helferlein springt auf und hört zu. Außerhalb von Helferlein braucht das die Erlaubnis „Bedienungshilfen“.")
                if assistant.settings.doubleCommand && !trusted {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Bedienungshilfen noch nicht erlaubt – ⌘⌘ geht dann nur, wenn Helferlein vorne ist.").font(.caption)
                        Spacer()
                        Button("Erlauben") { Permissions.requestAccessibility(); trusted = AXIsProcessTrusted() }
                    }
                }
            }
            Section("Gespräch") {
                LabeledContent("Satz ist fertig nach") {
                    Stepper(value: setting(assistant, \.silenceSeconds), in: 0.8...4, step: 0.2) {
                        Text(String(format: "%.1f s Pause", assistant.settings.silenceSeconds))
                    }
                }
                LabeledContent("Nachfragen nach") {
                    Stepper(value: setting(assistant, \.noSpeechSeconds), in: 3...30, step: 1) {
                        Text("\(Int(assistant.settings.noSpeechSeconds)) s Stille")
                    }
                }
                LabeledContent("Wie oft nachfragen") {
                    Stepper(value: setting(assistant, \.maxReprompts), in: 0...3) {
                        Text(assistant.settings.maxReprompts == 0 ? "nie" : "\(assistant.settings.maxReprompts)×")
                    }
                }
                hint("Nach der Nachfrage („\(assistant.profile?.firstName ?? "Name"), hörst du mich?“) wird Helferlein still und wartet oben in der Menüleiste.")
            }
            Section("Start") {
                Toggle("Beim Login öffnen und begrüßen", isOn: setting(assistant, \.greetOnLogin))
                Picker("Starten mit", selection: setting(assistant, \.startMode)) {
                    ForEach(Settings.StartMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .onAppear {
            devices = AudioDevices.inputDevices()
            micUID = AudioDevices.selectedUID ?? ""
            trusted = AXIsProcessTrusted()
        }
        .onDisappear { stopTest() }
    }

    private func restartTest() async {
        stopTest()
        testError = await assistant.startMicTest { level in testLevel = level }
        testing = testError == nil
    }

    private func stopTest() {
        assistant.stopMicTest()
        testing = false
        testLevel = 0
    }
}

// MARK: - KI-Modell

private struct AIPane: View {
    @ObservedObject var assistant: Assistant
    @State private var installed: [OllamaClient.ModelInfo] = []
    @State private var pulling: String?
    @State private var progress: Double = 0
    @State private var status = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section("Aktives Modell") {
                Picker("Modell", selection: setting(assistant, \.model)) {
                    ForEach(installed) { m in
                        Text("\(m.name)  (\(m.info))").tag(m.name)
                    }
                    if !installed.contains(where: { $0.name == assistant.settings.model }) {
                        Text("\(assistant.settings.model) (nicht geladen)").tag(assistant.settings.model)
                    }
                }
                hint("Alles läuft lokal über Ollama. Größere Modelle sind klüger, aber langsamer. Für 16 GB RAM ist qwen2.5:7b der beste Kompromiss.")
            }
            Section("Weitere Modelle laden") {
                ForEach(OllamaClient.recommendedModels) { m in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(m.name).font(.body.monospaced())
                            Text(m.info).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if installed.contains(where: { $0.name == m.name }) {
                            Text("geladen ✓").foregroundStyle(.green).font(.caption)
                        } else if pulling == m.name {
                            ProgressView(value: progress).frame(width: 120)
                        } else {
                            Button("Laden") { Task { await pull(m.name) } }.disabled(pulling != nil)
                        }
                    }
                }
                if pulling != nil { Text(status).font(.caption).foregroundStyle(.secondary) }
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            Section("Antworten") {
                LabeledContent("Kreativität") {
                    Slider(value: setting(assistant, \.temperature), in: 0...1, step: 0.1) {
                        EmptyView()
                    } minimumValueLabel: { Text("genau") } maximumValueLabel: { Text("kreativ") }
                }
                Picker("Antwortlänge", selection: setting(assistant, \.answerLength)) {
                    ForEach(Settings.AnswerLength.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            Section("Verwalten") {
                ForEach(installed.filter { $0.name != assistant.settings.model }) { m in
                    HStack {
                        Text(m.name).font(.body.monospaced())
                        Spacer()
                        Button("Löschen", role: .destructive) {
                            Task {
                                await OllamaClient(settings: assistant.settings).deleteModel(m.name)
                                await refresh()
                            }
                        }
                    }
                }
                TextField("Ollama-Adresse", text: setting(assistant, \.ollamaHost))
                hint("Nur ändern, wenn Ollama auf einem anderen Rechner läuft.")
            }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        installed = await OllamaClient(settings: assistant.settings).installedModels()
    }

    private func pull(_ name: String) async {
        var s = assistant.settings
        s.model = name
        pulling = name
        progress = 0
        error = nil
        do {
            try await OllamaClient(settings: s).pull { fraction, text in
                Task { @MainActor in
                    if fraction >= 0 { progress = fraction }
                    status = text
                }
            }
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
        pulling = nil
    }
}

// MARK: - Dokumente

private struct DocumentsPane: View {
    @ObservedObject var assistant: Assistant
    private let fonts = ["Calibri", "Arial", "Helvetica", "Verdana", "Georgia", "Times New Roman", "Garamond"]
    private let languages = ["auto", "de-AT", "de-DE", "de-CH"]

    private func languageName(_ code: String) -> String {
        switch code {
        case "de-AT": return "Deutsch (Österreich)"
        case "de-DE": return "Deutsch (Deutschland)"
        case "de-CH": return "Deutsch (Schweiz)"
        default: return "Automatisch (Region dieses Macs)"
        }
    }

    var body: some View {
        Form {
            Section("Speicherort") {
                LabeledContent("Ordner") {
                    Text(assistant.settings.outputDir.path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Ordner wählen …") { chooseFolder() }
                    Button("Im Finder zeigen") {
                        try? FileManager.default.createDirectory(at: assistant.settings.outputDir, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(assistant.settings.outputDir)
                    }
                    if !assistant.settings.documentsFolder.isEmpty {
                        Button("Standard") { assistant.updateSettings { $0.documentsFolder = "" } }
                    }
                }
            }
            Section("Sprache der Dokumente") {
                Picker("Sprache", selection: setting(assistant, \.documentLanguage)) {
                    ForEach(languages, id: \.self) { Text(languageName($0)).tag($0) }
                }
                hint("Bestimmt, in welcher Sprache Word, PowerPoint & Co. die Rechtschreibung prüfen. Jetzt: \(assistant.settings.resolvedDocumentLanguage).")
            }
            Section("Schrift") {
                Picker("Schriftart", selection: setting(assistant, \.documentFont)) {
                    ForEach(fonts, id: \.self) { Text($0).font(.custom($0, size: 13)).tag($0) }
                }
                LabeledContent("Schriftgröße") {
                    Stepper(value: setting(assistant, \.documentFontSize), in: 9...20, step: 1) {
                        Text("\(Int(assistant.settings.documentFontSize)) pt")
                    }
                }
            }
            Section("Nach dem Erstellen") {
                Toggle("Datei gleich im Programm öffnen", isOn: setting(assistant, \.openCreatedFiles))
                hint("Aus: Helferlein speichert nur und zeigt „Öffnen“ und „Im Finder zeigen“ im Chat.")
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Ordner für Helferlein-Dokumente"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = assistant.settings.outputDir
        if panel.runModal() == .OK, let url = panel.url {
            assistant.updateSettings { $0.documentsFolder = url.path }
        }
    }
}

// MARK: - System & Rechte

private struct SystemPane: View {
    @ObservedObject var assistant: Assistant
    @State private var autostart = false
    @State private var mic = false
    @State private var speech = false
    @State private var accessibility = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section("Autostart") {
                Toggle("Beim Anmelden starten", isOn: $autostart)
                    .onChange(of: autostart) { on in if loaded { LoginItem.setEnabled(on) } }
                hint("Startet Helferlein nur in diesem Benutzer-Account.")
            }
            Section("Erlaubnisse") {
                PermissionRow(title: "Mikrofon", ok: mic, detail: "Zum Zuhören.") {
                    Permissions.openPrivacy("Privacy_Microphone")
                }
                PermissionRow(title: "Spracherkennung", ok: speech, detail: "Wandelt Sprache in Text um (auf dem Mac).") {
                    Permissions.openPrivacy("Privacy_SpeechRecognition")
                }
                PermissionRow(title: "Bedienungshilfen", ok: accessibility,
                              detail: "Für ⌘⌘ in jedem Programm und zum Öffnen von Dateien in PowerPoint & Co.") {
                    Permissions.requestAccessibility()
                }
                Button("Neu prüfen") { refresh() }
                hint("Nach einem Helferlein-Update muss „Bedienungshilfen“ eventuell neu erlaubt werden (Eintrag entfernen und wieder hinzufügen).")
            }
            Section("Offline-Spracherkennung") {
                hint("Damit die Spracherkennung ganz ohne Internet läuft: Systemeinstellungen › Tastatur › Diktat einschalten und Deutsch wählen.")
                Button("Tastatur-Einstellungen öffnen") { Permissions.openPane("com.apple.Keyboard-Settings.extension") }
            }
        }
        .onAppear { refresh(); loaded = true }
    }

    private func refresh() {
        autostart = LoginItem.isEnabled
        mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speech = SFSpeechRecognizer.authorizationStatus() == .authorized
        accessibility = AXIsProcessTrusted()
    }
}

private struct PermissionRow: View {
    let title: String
    let ok: Bool
    let detail: String
    let fix: () -> Void

    var body: some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? Color.green : Color.orange)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !ok { Button("Erlauben …", action: fix) }
        }
    }
}

// MARK: - Wartung & Hilfe

private struct MaintenancePane: View {
    @ObservedObject var assistant: Assistant
    @State private var confirmRestart = false
    @State private var confirmReset = false
    @State private var confirmUninstall = false
    @State private var update: String?

    var body: some View {
        Form {
            Section("Wenn etwas hängt") {
                Button {
                    confirmRestart = true
                } label: {
                    Label("Alles neu starten", systemImage: "arrow.clockwise.circle.fill")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                hint("Beendet die KI (Ollama) und Helferlein und startet beides in ein paar Sekunden frisch.")
                Button("Gespräch löschen") { assistant.clearConversation() }
            }
            Section("Einstellungen") {
                Button("Alle Einstellungen zurücksetzen …") { confirmReset = true }
                Button("Einstellungs-Ordner öffnen") {
                    try? FileManager.default.createDirectory(at: Settings.supportDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(Settings.supportDir)
                }
                hint("Profil (Name, Stil, Programme) bleibt beim Zurücksetzen erhalten.")
            }
            Section("Version") {
                LabeledContent("Helferlein", value: Self.version)
                HStack {
                    Button("Nach Updates suchen") { Task { update = await Self.checkUpdate() } }
                    if let update { Text(update).font(.caption) }
                }
                Button("Hilfe & Quellcode auf GitHub") { NSWorkspace.shared.open(Self.repo) }
            }
            Section("Entfernen") {
                Button("Helferlein deinstallieren …", role: .destructive) { confirmUninstall = true }
                hint("Entfernt App, Einstellungen und Autostart. Deine Dokumente bleiben.")
            }
        }
        .alert("Alles neu starten?", isPresented: $confirmRestart) {
            Button("Neu starten", role: .destructive) { assistant.restartAll() }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Helferlein und die KI werden beendet und gleich wieder geöffnet.") }
        .alert("Einstellungen zurücksetzen?", isPresented: $confirmReset) {
            Button("Zurücksetzen", role: .destructive) { assistant.resetSettings(); AudioDevices.selectedUID = nil }
            Button("Abbrechen", role: .cancel) {}
        }
        .alert("Helferlein wirklich deinstallieren?", isPresented: $confirmUninstall) {
            Button("Deinstallieren", role: .destructive) { Self.uninstall() }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Deine Dokumente in „Dokumente › Helferlein“ bleiben erhalten.") }
    }

    static let repo = URL(string: "https://github.com/KimJongUnNK/helferin")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static func checkUpdate() async -> String {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/KimJongUnNK/helferin/releases/latest")!)
        req.timeoutInterval = 10
        guard let response = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: response.0) as? [String: Any],
              let tag = obj["tag_name"] as? String else {
            return "Konnte nicht prüfen (kein Internet oder Repo privat)."
        }
        let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        if latest.compare(version, options: .numeric) == .orderedDescending {
            NSWorkspace.shared.open(repo.appendingPathComponent("releases/latest"))
            return "Version \(latest) ist da – Download geöffnet."
        }
        return "Du hast die neueste Version."
    }

    static func uninstall() {
        LoginItem.setEnabled(false)
        try? FileManager.default.removeItem(at: Settings.supportDir)
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "at.boenke.helferlein")
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}

// MARK: - Helfer

private struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(level > 0.85 ? Color.orange : Color.green)
                    .frame(width: max(4, geo.size.width * CGFloat(level)))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .frame(width: 140, height: 8)
    }
}

@MainActor
enum Permissions {
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) { openPrivacy("Privacy_Accessibility") }
    }

    /// Einmal beim ersten Start fragen (für ⌘⌘), danach nur noch über die Einstellungen.
    static func requestAccessibilityOnce() {
        let key = "askedAccessibility"
        guard !AXIsProcessTrusted(), !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openPrivacy(_ anchor: String) {
        openURL("x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    static func openPane(_ id: String) {
        openURL("x-apple.systempreferences:\(id)")
    }

    private static func openURL(_ s: String) {
        if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}

/// Das Deutsch-Paket für WordCraft (extras/wordcraft-deutsch), in der App mitgeliefert.
@MainActor
enum WordCraftGerman {
    static var isInstalled: Bool {
        guard let app = AppLocator.find(Tool.word.appNames) else { return false }
        return FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Resources/helferlein-deutsch.txt").path)
    }

    /// Kopiert Skript + Patch nach Application Support und startet es im Terminal (zeigt Fortschritt, fragt ggf. nach dem Passwort).
    static func runInstaller(restore: Bool = false) {
        let fm = FileManager.default
        let target = Settings.supportDir.appendingPathComponent("wordcraft-deutsch", isDirectory: true)
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("wordcraft-deutsch"),
              fm.fileExists(atPath: source.appendingPathComponent("install.sh").path) else {
            NSWorkspace.shared.open(URL(string: "https://github.com/KimJongUnNK/helferin/tree/main/extras/wordcraft-deutsch")!)
            return
        }
        for name in ["install.sh", "wordcraft-deutsch.patch", "BASE_COMMIT"] {
            let dest = target.appendingPathComponent(name)
            try? fm.removeItem(at: dest)
            try? fm.copyItem(at: source.appendingPathComponent(name), to: dest)
        }
        let command = target.appendingPathComponent(restore ? "WordCraft Original.command" : "WordCraft auf Deutsch.command")
        let args = restore ? " --restore" : ""
        let script = "#!/bin/bash\ncd \"$(dirname \"$0\")\" && /bin/bash ./install.sh\(args)\necho\nread -n 1 -s -r -p \"Fertig – beliebige Taste schließt das Fenster.\"\n"
        try? script.write(to: command, atomically: true, encoding: .utf8)
        Actions.run("/bin/chmod", ["+x", command.path, target.appendingPathComponent("install.sh").path])
        NSWorkspace.shared.open(command)
    }
}
