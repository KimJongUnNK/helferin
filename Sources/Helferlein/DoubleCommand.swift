import AppKit

/// Erkennt „⌘ zweimal kurz drücken“ – in jedem Programm (globaler Monitor) und in Helferlein selbst.
/// Außerhalb von Helferlein liefert macOS diese Tasten nur mit der Erlaubnis „Bedienungshilfen“.
@MainActor
final class DoubleCommandDetector {
    var onTrigger: (() -> Void)?

    /// Max. Dauer eines Tipps und max. Abstand zwischen beiden Tipps (Sekunden).
    static let tapMax: TimeInterval = 0.35
    static let gapMax: TimeInterval = 0.45

    private var monitors: [Any] = []
    private var commandDown = false
    private var downAt: TimeInterval = 0
    private var otherInput = false
    private var lastTap: TimeInterval = 0

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        stop()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        reset()
    }

    private func reset() {
        commandDown = false
        otherInput = false
        lastTap = 0
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown {
            // ⌘ + Taste (z. B. ⌘C) ist kein Doppel-⌘
            otherInput = true
            lastTap = 0
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandKey = event.keyCode == 55 || event.keyCode == 54 // links / rechts
        if isCommandKey && flags == .command {
            commandDown = true
            otherInput = false
            downAt = event.timestamp
        } else if isCommandKey && commandDown && !flags.contains(.command) {
            commandDown = false
            guard !otherInput, event.timestamp - downAt <= Self.tapMax else { lastTap = 0; return }
            if lastTap > 0, event.timestamp - lastTap <= Self.gapMax {
                lastTap = 0
                onTrigger?()
            } else {
                lastTap = event.timestamp
            }
        } else {
            // Andere Sondertasten (⇧, ⌥, ⌃) dazwischen → kein Doppel-⌘
            commandDown = false
            lastTap = 0
        }
    }
}
