import SwiftUI

/// Wurzel des Fensters: Einrichtung oder Chat.
struct RootView: View {
    @ObservedObject var assistant: Assistant

    var body: some View {
        Group {
            if assistant.needsOnboarding {
                OnboardingView(assistant: assistant)
            } else {
                ChatView(assistant: assistant)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: assistant.needsOnboarding)
    }
}

struct ChatView: View {
    @ObservedObject var assistant: Assistant
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(assistant.messages) { message in
                            MessageRow(message: message,
                                       open: { assistant.open($0) },
                                       reveal: { assistant.reveal($0) })
                                .id(message.id)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        if assistant.showsQuickStart {
                            QuickStart(tools: assistant.profile?.tools ?? []) { assistant.quickStart($0) }
                                .padding(.top, 6)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(16)
                    .animation(.easeOut(duration: 0.25), value: assistant.messages.count)
                }
                .onChange(of: assistant.messages.count) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            Divider()
            footer.padding(14)
        }
        .frame(width: 420, height: 600)
        .onChange(of: assistant.focusRequest) { _ in
            DispatchQueue.main.async { inputFocused = true }
        }
    }

    // MARK: Kopf

    private var header: some View {
        HStack(spacing: 14) {
            Orb(phase: assistant.phase, level: assistant.level)
            VStack(alignment: .leading, spacing: 3) {
                Text("Helferlein").font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(status).font(.system(size: 13)).foregroundStyle(.secondary)
                    .animation(.none, value: status)
            }
            Spacer()
            Button { assistant.editProfile() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .frame(width: 32, height: 32)
                    .background(Color.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Einstellungen: Name, Programme, Stil")
            Button {
                assistant.mode == .voice ? assistant.switchToText() : assistant.switchToVoice()
            } label: {
                Image(systemName: assistant.mode == .voice ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 15))
                    .frame(width: 32, height: 32)
                    .background(Color.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .help(assistant.mode == .voice ? "Leise stellen (Enter)" : "Wieder sprechen")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var status: String {
        switch assistant.phase {
        case .speaking: return "Spricht …"
        case .listening: return "Hört dir zu …"
        case .thinking: return "Denkt nach …"
        case .idle: return assistant.mode == .voice ? "Bereit" : "Leise – schreib mir einfach"
        }
    }

    // MARK: Fuß

    @ViewBuilder private var footer: some View {
        if assistant.mode == .voice {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(assistant.liveTranscript.isEmpty ? voiceHint : assistant.liveTranscript)
                        .font(.system(size: 16))
                        .foregroundStyle(assistant.liveTranscript.isEmpty ? Color.secondary : Color.primary)
                        .lineLimit(3)
                    Text("Enter drücken = leise stellen und tippen")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { assistant.switchToText() } label: {
                    Label("Tippen", systemImage: "keyboard")
                }
                .controlSize(.large)
            }
        } else {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Schreib mir hier …", text: $assistant.input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .onSubmit { assistant.submitText() }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.secondary.opacity(0.2)))
                RoundButton(symbol: "arrow.up", filled: true, help: "Senden (Enter)") { assistant.submitText() }
                    .disabled(assistant.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || assistant.phase == .thinking)
                RoundButton(symbol: "mic.fill", filled: false, help: "Wieder sprechen") { assistant.switchToVoice() }
            }
        }
    }

    private var voiceHint: String {
        switch assistant.phase {
        case .listening: return "Sprich einfach mit mir …"
        case .thinking: return "Einen Moment …"
        default: return "…"
        }
    }
}

// MARK: - Bausteine

private struct RoundButton: View {
    let symbol: String
    let filled: Bool
    let help: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(filled ? Color.white : Color.accentColor)
                .frame(width: 36, height: 36)
                .background(filled ? Color.accentColor : Color.accentColor.opacity(0.14), in: Circle())
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct QuickStart: View {
    let tools: [Tool]
    let pick: (String) -> Void

    private struct Item: Identifiable {
        let symbol, title, subtitle, prompt: String
        var id: String { title }
    }

    /// Nur Karten für Programme, die im Profil eingeschaltet sind.
    private var items: [Item] {
        var list: [Item] = []
        if tools.contains(.word) {
            list.append(Item(symbol: Tool.word.symbol, title: "Brief schreiben", subtitle: "in Word", prompt: "Ich möchte einen Brief schreiben."))
        }
        if tools.contains(.pdf) {
            list.append(Item(symbol: Tool.pdf.symbol, title: "PDF erstellen", subtitle: "in PDF Acrobat", prompt: "Ich möchte ein PDF erstellen."))
        }
        if tools.contains(.powerpoint) {
            list.append(Item(symbol: Tool.powerpoint.symbol, title: "Präsentation", subtitle: "in PowerPoint", prompt: "Ich möchte eine Präsentation machen."))
        }
        if tools.contains(.internet) {
            list.append(Item(symbol: "magnifyingglass", title: "Im Internet suchen", subtitle: "mit Brave", prompt: "Ich möchte etwas im Internet suchen."))
        }
        list.append(Item(symbol: "folder.fill", title: "Dokument öffnen", subtitle: "mein letztes Dokument", prompt: "Öffne bitte mein letztes Dokument."))
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Oder einfach antippen:").font(.system(size: 12)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(items) { item in
                    Button { pick(item.prompt) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: item.symbol).font(.system(size: 20)).foregroundStyle(Color.accentColor)
                            Text(item.title).font(.system(size: 14, weight: .semibold))
                            Text(item.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.15)))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let open: (URL) -> Void
    let reveal: (URL) -> Void

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        switch message.role {
        case .info:
            infoCard
        case .user, .assistant:
            bubble
        }
    }

    private var bubble: some View {
        let mine = message.role == .user
        return HStack(alignment: .bottom) {
            if mine { Spacer(minLength: 50) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                Text(message.text)
                    .font(.system(size: 16))
                    .textSelection(.enabled)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(mine ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.13)),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(mine ? Color.white : Color.primary)
                Text(Self.time.string(from: message.date))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
            }
            if !mine { Spacer(minLength: 50) }
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: message.symbol ?? "info.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let url = message.fileURL {
                HStack(spacing: 8) {
                    Button { open(url) } label: { Label("Öffnen", systemImage: "arrow.up.forward.app") }
                    Button { reveal(url) } label: { Label("Im Finder zeigen", systemImage: "folder") }
                }
                .controlSize(.small)
                .padding(.leading, 30)
            }
        }
        .padding(11)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
