import AppKit
import AVFoundation
import Foundation

/// Erste Vorbereitung der Download-Version: KI (Ollama) installieren, Sprachmodell laden,
/// Dokument-Werkzeug prüfen, Programme und Stimme erkennen. Bei der install.sh-Version ist meist schon alles da.
@MainActor
final class SetupManager: ObservableObject {
    enum State: Equatable {
        case waiting, working(String), done, failed(String)
        var isDone: Bool { self == .done }
    }

    @Published private(set) var ollama: State = .waiting
    @Published private(set) var model: State = .waiting
    @Published private(set) var modelProgress: Double = 0
    @Published private(set) var helper: State = .waiting
    @Published private(set) var installedTools: Set<Tool> = []
    @Published private(set) var goodVoice = false
    @Published private(set) var isRunning = false

    /// Wird einmal aufgerufen, sobald alles bereit ist.
    var onReady: (() -> Void)?
    private var announced = false

    var isReady: Bool { ollama.isDone && model.isDone && helper.isDone }

    private let settings: Settings
    private var llm: OllamaClient { OllamaClient(settings: settings) }
    private var actions: Actions { Actions(settings: settings) }

    init(settings: Settings) {
        self.settings = settings
    }

    /// Schnell prüfen, ohne etwas zu installieren. true = alles bereit.
    @discardableResult
    func check() async -> Bool {
        let actions = self.actions
        helper = await Task.detached { actions.helperWorks() }.value
            ? .done : .failed("Das Dokument-Werkzeug fehlt. Bitte Helferlein neu herunterladen.")
        installedTools = await Task.detached { actions.installedTools() }.value
        goodVoice = SpeechIO.hasHighQualityVoice

        if await llm.ensureRunning() {
            ollama = .done
            model = await llm.hasModel() ? .done : .waiting
        } else {
            ollama = OllamaClient.isInstalled ? .failed("Ollama startet nicht.") : .waiting
            model = .waiting
        }
        announceIfReady()
        return isReady
    }

    /// Alles Fehlende installieren / laden.
    func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        // 1. Ollama
        if !ollama.isDone {
            if !OllamaClient.isInstalled {
                ollama = .working("Lade das KI-Programm Ollama (ca. 200 MB) …")
                do { try await OllamaClient.install() } catch {
                    ollama = .failed("Download fehlgeschlagen: \(error.localizedDescription)")
                    return
                }
            }
            ollama = .working("Starte Ollama …")
            guard await llm.ensureRunning() else {
                ollama = .failed("Ollama startet nicht. Öffne einmal „Ollama“ aus dem Programme-Ordner und versuch es nochmal.")
                return
            }
            ollama = .done
        }

        // 2. Sprachmodell
        if !model.isDone {
            if await llm.hasModel() {
                model = .done
            } else {
                model = .working("Lade das Sprachmodell (ca. 4,7 GB) …")
                modelProgress = 0
                do {
                    try await llm.pull { [weak self] fraction, status in
                        Task { @MainActor in
                            guard let self else { return }
                            if fraction >= 0 { self.modelProgress = fraction }
                            if !status.isEmpty { self.model = .working(status) }
                        }
                    }
                    model = .done
                    modelProgress = 1
                } catch {
                    model = .failed(error.localizedDescription)
                    return
                }
            }
        }

        // 3. Programme und Stimme noch einmal ansehen
        let actions = self.actions
        installedTools = await Task.detached { actions.installedTools() }.value
        goodVoice = SpeechIO.hasHighQualityVoice
        announceIfReady()
    }

    func refreshTools() {
        installedTools = actions.installedTools()
        goodVoice = SpeechIO.hasHighQualityVoice
    }

    private func announceIfReady() {
        guard isReady, !announced else { return }
        announced = true
        onReady?()
    }

    // MARK: Links

    static let artCraftLauncher = URL(string: "https://github.com/storytold/craft-launcher/releases/latest")!
    static let braveDownload = URL(string: "https://brave.com/download/")!

    static func openVoiceSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent",
            "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent",
        ]
        for c in candidates {
            if let url = URL(string: c), NSWorkspace.shared.open(url) { return }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
