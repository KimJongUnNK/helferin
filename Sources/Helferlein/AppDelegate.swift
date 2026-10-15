import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var assistant: Assistant!
    private var keyMonitor: Any?
    private var phaseWatch: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        assistant = Assistant()
        assistant.onClose = { [weak self] in self?.popover.performClose(nil) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Helferlein")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.contentSize = NSSize(width: 420, height: 600)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: RootView(assistant: assistant))

        // Enter während Sprachmodus = leise stellen und zum Tippen wechseln
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown, !self.assistant.needsOnboarding else { return event }
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            guard isReturn else { return event }
            if self.assistant.mode == .voice {
                self.assistant.switchToText()
                return nil
            }
            if event.modifierFlags.contains(.shift) { // Shift+Enter = neue Zeile
                self.assistant.input += "\n"
                return nil
            }
            return event
        }

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

        // Nach dem Login kurz warten, bis Menüleiste und Audio bereit sind
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self else { return }
            self.showPopover()
            self.assistant.start()
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
            assistant.reopened()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        assistant.closed()
    }
}
