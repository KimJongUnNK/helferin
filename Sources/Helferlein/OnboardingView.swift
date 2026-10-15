import AppKit
import SwiftUI

/// Einrichtung beim ersten Start (und später übers Zahnrad):
/// Vorname → wofür → welche Programme → wie soll er reden.
struct OnboardingView: View {
    @ObservedObject var assistant: Assistant

    @State private var step = 0
    @State private var firstName = ""
    @State private var purposes: Set<String> = []
    @State private var purposeNote = ""
    @State private var tools: Set<Tool> = Set(Tool.allCases)
    @State private var style: Style = .casual
    @FocusState private var nameFocused: Bool

    private let lastStep = 4
    private var isEditing: Bool { assistant.profile != nil }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ScrollView {
                content
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            bottomBar.padding(14)
        }
        .frame(width: 420, height: 600)
        .onAppear(perform: loadExisting)
        .onDisappear { assistant.stopPreview() }
    }

    // MARK: Leisten

    private var topBar: some View {
        HStack {
            Text(isEditing ? "Einstellungen" : "Einrichtung")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Spacer()
            HStack(spacing: 6) {
                ForEach(0...lastStep, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: i == step ? 18 : 7, height: 7)
                }
            }
            .animation(.easeOut(duration: 0.2), value: step)
            if isEditing {
                Button { assistant.cancelEditProfile() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .padding(.leading, 10)
                    .help("Abbrechen")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var bottomBar: some View {
        HStack {
            if step > 0 {
                Button("Zurück") { withAnimation { step -= 1 } }
                    .controlSize(.large)
            }
            Spacer()
            Button(step == lastStep ? "Fertig" : (step == 0 ? "Los geht’s" : "Weiter")) { next() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(!canContinue)
        }
    }

    private var canContinue: Bool {
        step != 1 || !firstName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func next() {
        guard canContinue else { return }
        if step < lastStep {
            withAnimation { step += 1 }
            if step == 1 { Task { @MainActor in nameFocused = true } }
            return
        }
        assistant.stopPreview()
        assistant.completeOnboarding(Profile(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            purposes: Profile.purposeChoices.filter { purposes.contains($0) },
            purposeNote: purposeNote.trimmingCharacters(in: .whitespacesAndNewlines),
            tools: Tool.allCases.filter { tools.contains($0) },
            style: style))
    }

    private func loadExisting() {
        guard let p = assistant.profile else { return }
        firstName = p.firstName
        purposes = Set(p.purposes)
        purposeNote = p.purposeNote
        tools = Set(p.tools)
        style = p.style
        step = 1
    }

    // MARK: Schritte

    @ViewBuilder private var content: some View {
        switch step {
        case 0: welcome
        case 1: nameStep
        case 2: purposeStep
        case 3: toolsStep
        default: styleStep
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                .padding(.top, 30)
            Text("Hallo! Ich bin Helferlein.")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Ich helfe dir am Computer – mit Briefen, PDFs, Präsentationen und Fragen ans Internet. Du kannst mit mir reden oder schreiben.\n\nLass uns kurz einrichten, das dauert nur eine Minute.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(title: "Wie heißt du?", subtitle: "Dein Vorname reicht. So spreche ich dich an.")
            TextField("Vorname", text: $firstName)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .medium))
                .padding(14)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                .focused($nameFocused) // Enter = „Weiter“ (Standard-Knopf)
        }
    }

    private var purposeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepTitle(title: "Wofür brauchst du mich?",
                      subtitle: "Tipp alles an, was passt. Dann weiß ich, womit ich dir am besten helfe.")
            FlowChips(items: Profile.purposeChoices, selected: $purposes)
            TextField("Oder in eigenen Worten …", text: $purposeNote, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(2...4)
                .padding(12)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var toolsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepTitle(title: "Welche Programme soll ich benutzen?",
                      subtitle: "Was du abwählst, fasse ich nicht an. Du kannst es später beim Zahnrad ändern.")
            ForEach(Tool.allCases) { tool in
                let on = tools.contains(tool)
                Button {
                    if on { tools.remove(tool) } else { tools.insert(tool) }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 20))
                            .foregroundStyle(on ? Color.white : Color.accentColor)
                            .frame(width: 42, height: 42)
                            .background(on ? Color.accentColor : Color.accentColor.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.label).font(.system(size: 16, weight: .semibold))
                            Text(tool.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.5))
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(on ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var styleStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepTitle(title: "Wie soll ich mit dir reden?",
                      subtitle: "Tipp auf 🔊, um reinzuhören.")
            ForEach(Style.allCases) { s in
                let on = style == s
                HStack(spacing: 14) {
                    Text(s.emoji).font(.system(size: 28))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.label).font(.system(size: 16, weight: .semibold))
                        Text(s.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { style = s; assistant.preview(s, name: firstName) } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .frame(width: 32, height: 32)
                            .background(Color.secondary.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Probehören")
                }
                .padding(12)
                .background(on ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(on ? Color.accentColor : Color.clear, lineWidth: 2))
                .contentShape(RoundedRectangle(cornerRadius: 14))
                .onTapGesture { style = s }
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

// MARK: - Bausteine

private struct StepTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }
}

/// Auswahl-Chips, die automatisch umbrechen (zwei Spalten reichen bei 420 pt Breite).
private struct FlowChips: View {
    let items: [String]
    @Binding var selected: Set<String>

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                  alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                let on = selected.contains(item)
                Button {
                    if on { selected.remove(item) } else { selected.insert(item) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: on ? "checkmark" : "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text(item).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .background(on ? Color.accentColor : Color.secondary.opacity(0.1), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
