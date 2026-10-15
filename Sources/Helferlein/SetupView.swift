import AppKit
import SwiftUI

/// Vorbereitung beim allerersten Start der Download-Version: KI laden, Programme finden.
struct SetupView: View {
    @ObservedObject var setup: SetupManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Helferlein wird vorbereitet").font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("Einmalig – danach läuft alles ohne Internet.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    StepRow(title: "KI-Programm (Ollama)", state: setup.ollama, symbol: "cpu")
                    VStack(alignment: .leading, spacing: 6) {
                        StepRow(title: "Sprachmodell", state: setup.model, symbol: "brain")
                        if case .working = setup.model {
                            ProgressView(value: setup.modelProgress)
                                .padding(.leading, 34)
                        }
                    }
                    StepRow(title: "Dokument-Werkzeug", state: setup.helper, symbol: "doc.on.doc")

                    Divider().padding(.vertical, 4)

                    Text("Programme").font(.system(size: 13, weight: .semibold))
                    ForEach(Tool.Group.allCases) { group in
                        let tools = Tool.allCases.filter { $0.group == group }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.rawValue).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                                ForEach(tools) { tool in
                                    let found = setup.installedTools.contains(tool)
                                    HStack(spacing: 6) {
                                        Image(systemName: found ? "checkmark.circle.fill" : "circle.dashed")
                                            .foregroundStyle(found ? Color.green : Color.secondary)
                                        Text(tool.label).font(.system(size: 12))
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                        }
                    }
                    if !Tool.allCases.filter({ $0.group != .web }).allSatisfy({ setup.installedTools.contains($0) }) {
                        HStack {
                            Button("ArtCraft-Programme laden") { NSWorkspace.shared.open(SetupManager.artCraftLauncher) }
                            if !setup.installedTools.contains(.internet) {
                                Button("Brave laden") { NSWorkspace.shared.open(SetupManager.braveDownload) }
                            }
                            Button("Neu suchen") { setup.refreshTools() }
                        }
                        .controlSize(.small)
                        Text("Fehlende Programme kannst du jederzeit nachinstallieren. Helferlein öffnet Dateien sonst mit der Standard-App.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }

                    Divider().padding(.vertical, 4)

                    HStack(spacing: 10) {
                        Image(systemName: setup.goodVoice ? "checkmark.circle.fill" : "speaker.wave.2")
                            .foregroundStyle(setup.goodVoice ? Color.green : Color.accentColor)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Schöne Stimme").font(.system(size: 13, weight: .medium))
                            Text(setup.goodVoice ? "Hochwertige deutsche Stimme gefunden."
                                 : "Tipp: Lade „Anna (Premium)“ – klingt viel natürlicher.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !setup.goodVoice {
                            Button("Stimme laden") { SetupManager.openVoiceSettings() }.controlSize(.small)
                        }
                    }
                }
                .padding(18)
            }

            Divider()
            HStack {
                if hasFailure {
                    Button("Nochmal versuchen") { Task { await setup.run() } }
                        .controlSize(.large)
                }
                Spacer()
                if setup.isRunning {
                    ProgressView().controlSize(.small)
                    Text("Bitte warten …").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
        .frame(width: 420, height: 600)
        .task { await setup.run() }
    }

    private var hasFailure: Bool {
        [setup.ollama, setup.model, setup.helper].contains { if case .failed = $0 { return true } else { return false } }
    }
}

private struct StepRow: View {
    let title: String
    let state: SetupManager.State
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                switch state {
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
                case .working: ProgressView().controlSize(.small)
                case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
                case .waiting: Image(systemName: symbol).foregroundStyle(Color.secondary)
                }
            }
            .frame(width: 24, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium))
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var detail: String? {
        switch state {
        case .waiting: return "Wartet …"
        case let .working(text): return text
        case .done: return nil
        case let .failed(text): return text
        }
    }
}
