import AppKit

// Helferlein wird pro Benutzer-Account installiert (~/Applications + eigener Autostart).
// Andere Accounts auf demselben Mac bekommen davon nichts mit.
@main
@MainActor
enum HelferleinApp {
    static func main() {
        // Nur einmal laufen (Autostart + Doppelklick + Neustart dürfen sich nicht doppeln)
        let me = NSRunningApplication.current
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != me && !$0.isTerminated }) {
            exit(0)
        }
        // Download-Version: Quarantäne vom eigenen Paket entfernen, damit das eingebaute Python starten darf
        Actions.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", Bundle.main.bundlePath])

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // kein Dock-Icon, nur Menüleiste
        withExtendedLifetime(delegate) { app.run() }
    }
}
