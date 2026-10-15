import AppKit
import ApplicationServices
import SwiftUI

/// Einstellungen (Zahnrad): Profil, Mikrofon, Stimme, WordCraft auf Deutsch, Bedienungshilfen, Autostart, Neustart.
struct SettingsView: View {
    @ObservedObject var assistant: Assistant

    @State private var devices: [AudioInputDevice] = []
    @State private var micUID: String = AudioDevices.selectedUID ?? ""
    @State private var testing = false
    @State private var testLevel: Float = 0
    @State private var testError: String?
    @State private var autostart = false
    @State private var trusted = false
    @State private var wordcraftGerman = false
    @State private var loaded = false
    @State private var confirmRestart = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { assistant.closeSettings() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .help("Zurück")
                Text("Einstellungen").font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(16)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Profil
                    Card(symbol: "person.crop.circle", title: "Profil & Programme",
                         text: profileSummary) {
                        Button("Ändern") { assistant.editProfile() }
                    }

                    // Mikrofon
                    Card(symbol: "mic.fill", title: "Mikrofon", text: "Welches Mikrofon Helferlein benutzt.") {
                        EmptyView()
                    } extra: {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("", selection: $micUID) {
                                Text("Systemstandard (\(AudioDevices.defaultInputName() ?? "–"))").tag("")
                                ForEach(devices) { d in Text(d.name).tag(d.uid) }
                            }
                            .labelsHidden()
                            .onChange(of: micUID) { uid in
                                AudioDevices.selectedUID = uid.isEmpty ? nil : uid
                                if testing { Task { await restartTest() } }
                            }
                            HStack(spacing: 10) {
                                Button(testing ? "Test stoppen" : "Mikrofon testen") {
                                    if testing { stopTest() } else { Task { await restartTest() } }
                                }
                                .controlSize(.small)
                                if testing {
                                    LevelBar(level: testLevel)
                                    Text("Sprich etwas …").font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                            if let testError {
                                Text(testError).font(.system(size: 11)).foregroundStyle(.orange)
                            }
                        }
                    }

                    // Stimme
                    Card(symbol: "speaker.wave.2.fill", title: "Stimme",
                         text: SpeechIO.hasHighQualityVoice ? "Hochwertige deutsche Stimme aktiv."
                             : "Lade „Anna (Premium)“ für eine natürlichere Stimme.") {
                        Button("Stimmen …") { SetupManager.openVoiceSettings() }
                    }

                    // WordCraft auf Deutsch
                    Card(symbol: "character.book.closed.fill", title: "Word auf Deutsch",
                         text: wordcraftGerman
                             ? "Installiert: Word (WordCraft) prüft deutsche Rechtschreibung. Nach einem WordCraft-Update bitte erneut ausführen."
                             : "Bringt Word (WordCraft) deutsche Rechtschreibprüfung und eine deutsche Oberfläche bei.") {
                        Button(wordcraftGerman ? "Erneut ausführen" : "Installieren") { WordCraftGerman.runInstaller() }
                    }

                    // Bedienungshilfen
                    Card(symbol: "hand.raised.fill", title: "Dateien automatisch öffnen",
                         text: trusted ? "Erlaubt: Helferlein kann Dateien auch in PowerPoint & Co. über „Öffnen“ laden."
                             : "Manche Programme (z. B. PowerPoint/DeckCraft) nehmen Dateien nur über ihren Öffnen-Dialog. Dafür braucht Helferlein die Erlaubnis „Bedienungshilfen“.") {
                        if !trusted {
                            Button("Erlauben") {
                                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                                trusted = AXIsProcessTrustedWithOptions(options)
                            }
                        }
                    }

                    // Autostart
                    Card(symbol: "power", title: "Beim Anmelden starten",
                         text: "Helferlein öffnet sich nach dem Einloggen und fragt, ob du Hilfe brauchst.") {
                        Toggle("", isOn: $autostart)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: autostart) { on in if loaded { LoginItem.setEnabled(on) } }
                    }

                    // Neustart
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            confirmRestart = true
                        } label: {
                            Label("Alles neu starten", systemImage: "arrow.clockwise.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.large)
                        Text("Hilft, wenn Helferlein hängt oder nicht mehr antwortet: beendet die KI und startet alles frisch.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)

                    Text("Helferlein \(Self.version) · Dokumente: Dokumente › Helferlein")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
        }
        .frame(width: 420, height: 600)
        .onAppear {
            devices = AudioDevices.inputDevices()
            trusted = AXIsProcessTrusted()
            wordcraftGerman = WordCraftGerman.isInstalled
            autostart = LoginItem.isEnabled
            loaded = true
        }
        .onDisappear { stopTest() }
        .alert("Alles neu starten?", isPresented: $confirmRestart) {
            Button("Neu starten", role: .destructive) { assistant.restartAll() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Helferlein und die KI werden beendet und in ein paar Sekunden wieder geöffnet.")
        }
    }

    private var profileSummary: String {
        guard let p = assistant.profile else { return "Noch nicht eingerichtet." }
        let tools = p.tools.map(\.label).joined(separator: ", ")
        return "\(p.firstName) · Stil: \(p.style.label)\nProgramme: \(tools.isEmpty ? "keine" : tools)"
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

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}

/// Eine Einstellungs-Karte mit Symbol, Titel, Text, Knopf rechts und optionalem Inhalt darunter.
private struct Card<Accessory: View, Extra: View>: View {
    let symbol: String
    let title: String
    let text: String
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var extra: () -> Extra

    init(symbol: String, title: String, text: String,
         @ViewBuilder accessory: @escaping () -> Accessory,
         @ViewBuilder extra: @escaping () -> Extra) {
        self.symbol = symbol
        self.title = title
        self.text = text
        self.accessory = accessory
        self.extra = extra
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                accessory().controlSize(.small)
            }
            extra().padding(.leading, 38)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension Card where Extra == EmptyView {
    init(symbol: String, title: String, text: String, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.init(symbol: symbol, title: title, text: text, accessory: accessory, extra: { EmptyView() })
    }
}

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
        .frame(width: 110, height: 8)
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
    static func runInstaller() {
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
        let command = target.appendingPathComponent("WordCraft auf Deutsch.command")
        let script = "#!/bin/bash\ncd \"$(dirname \"$0\")\" && /bin/bash ./install.sh\necho\nread -n 1 -s -r -p \"Fertig – beliebige Taste schließt das Fenster.\"\n"
        try? script.write(to: command, atomically: true, encoding: .utf8)
        Actions.run("/bin/chmod", ["+x", command.path, target.appendingPathComponent("install.sh").path])
        NSWorkspace.shared.open(command)
    }
}
