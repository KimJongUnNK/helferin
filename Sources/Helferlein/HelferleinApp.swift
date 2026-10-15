import AppKit

// Helferlein wird pro Benutzer-Account installiert (~/Applications + eigener Autostart).
// Andere Accounts auf demselben Mac bekommen davon nichts mit.
@main
@MainActor
enum HelferleinApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // kein Dock-Icon, nur Menüleiste
        withExtendedLifetime(delegate) { app.run() }
    }
}
