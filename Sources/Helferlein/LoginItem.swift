import AppKit
import ServiceManagement

/// Autostart beim Anmelden: über macOS (SMAppService), sonst über einen LaunchAgent.
@MainActor
enum LoginItem {
    static let agentLabel = "at.boenke.helferlein"
    private static let configuredKey = "loginItemConfigured"

    static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled || FileManager.default.fileExists(atPath: agentURL.path)
    }

    static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(true, forKey: configuredKey)
        if on {
            do {
                try SMAppService.mainApp.register()
                removeAgent()
            } catch {
                NSLog("Helferlein: SMAppService ging nicht (\(error.localizedDescription)), nehme LaunchAgent")
                writeAgent()
            }
        } else {
            try? SMAppService.mainApp.unregister()
            removeAgent()
        }
    }

    /// Beim ersten Start einmal einschalten – auch bei Installationen über install.sh.
    static func enableOnFirstRun() {
        guard !UserDefaults.standard.bool(forKey: configuredKey) else { return }
        setEnabled(true)
    }

    private static func writeAgent() {
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true,
        ]
        let dir = agentURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: agentURL)
        }
    }

    private static func removeAgent() {
        try? FileManager.default.removeItem(at: agentURL)
    }
}

/// Helferlein beenden und gleich wieder öffnen.
@MainActor
enum AppRelaunch {
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 2; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }
}
