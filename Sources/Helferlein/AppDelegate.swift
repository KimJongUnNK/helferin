import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var assistant: Assistant!
    private var setup: SetupManager!
    private var settingsWindow: SettingsWindowController!
    private let doubleCommand = DoubleCommandDetector()
    private var keyMonitor: Any?
    private var phaseWatch: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        assistant = Assistant()
        setup = SetupManager(settings: assistant.settings)
        settingsWindow = SettingsWindowController(assistant: assistant, setup: setup)
        LoginItem.enableOnFirstRun()

        assistant.onClose = { [weak self] in self?.popover.performClose(nil) }
        assistant.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        assistant.onSettingsChanged = { [weak self] s in self?.applyDoubleCommand(s.doubleCommand) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Helferlein")
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.contentSize = NSSize(width: 420, height: 600)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: RootView(assistant: assistant, setup: setup))

        // Enter während Sprachmodus = leise stellen und zum Tippen wechseln; Shift+Enter = neue Zeile
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown, self.setup.isReady,
                  !self.assistant.needsOnboarding else { return event }
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            guard isReturn else { return event }
            if self.assistant.mode == .voice {
                self.assistant.switchToText()
                return nil
            }
            if event.modifierFlags.contains(.shift) {
                self.assistant.input += "\n"
                return nil
            }
            return event
        }

        // ⌘ zweimal drücken = Helferlein springt auf und hört zu
        doubleCommand.onTrigger = { [weak self] in self?.listenNow() }
        applyDoubleCommand(assistant.settings.doubleCommand)

        // Menüleisten-Symbol zeigt, was gerade passiert
        phaseWatch = assistant.$phase.sink { [weak self] phase in
            let symbol: String
            switch phase {
            case .listening: symbol = "mic.fill"
            case .speaking: symbol = "waveform"
            case .thinking: symbol = "ellipsis.circle"
            case .idle: symbol = "sparkles"
            }
            self?.statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Helferlein")
        }

        // Nach dem Login kurz warten, bis Menüleiste und Audio bereit sind.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self else { return }
            let greet = self.assistant.settings.greetOnLogin
            self.setup.onReady = { [weak self] in
                guard let self else { return }
                if greet || self.assistant.profile == nil { self.assistant.start() }
            }
            let ready = await self.setup.check() // meist sofort fertig; sonst zeigt das Fenster die Vorbereitung
            if !ready || greet || self.assistant.profile == nil { self.showPopover() }
        }
    }

    private func applyDoubleCommand(_ on: Bool) {
        if on {
            if !doubleCommand.isRunning { doubleCommand.start() }
            Permissions.requestAccessibilityOnce()
        } else {
            doubleCommand.stop()
        }
    }

    /// ⌘⌘: Fenster öffnen und sofort zuhören.
    private func listenNow() {
        showPopover()
        guard setup.isReady else { return }
        assistant.activateVoice()
    }

    @objc private func statusItemClicked() {
        // Rechtsklick: kleines Menü mit Einstellungen und Neustart
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
            if setup.isReady { assistant.reopened() }
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Zuhören (⌘⌘)", action: #selector(menuListen), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Einstellungen …", action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Alles neu starten", action: #selector(menuRestart), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Helferlein beenden", action: #selector(menuQuit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuListen() { listenNow() }
    @objc private func menuSettings() { assistant.openSettings() }
    @objc private func menuRestart() { assistant.restartAll() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        assistant.closed()
    }
}
