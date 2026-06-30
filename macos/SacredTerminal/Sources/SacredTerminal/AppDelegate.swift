import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: MainWindowController?
    private var statusItem: StatusItemController?
    private var socket: SocketServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A GUI app launched via Finder/`open` inherits a minimal PATH that omits the
        // user's shell additions (nvm, Homebrew, ~/.local/bin), so agent CLIs like
        // `gemini` / `claude` can't be found and their sessions die on launch. Import
        // the login shell's PATH once so every libghostty-spawned command resolves.
        importShellPath()

        // Dock / app-switcher icon (spec §9 — the branching sacred-timeline mark).
        // The dev build runs unbundled, so set it at runtime; packaging also embeds it.
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }

        buildMenu()

        // Build + show the main window FIRST so its chrome (titlebar, rail, workspace)
        // paints immediately at the launch size. libghostty initializes lazily when the
        // first terminal surface enters the window — and that surface spin-up is itself
        // deferred a runloop tick (see SurfaceView) — so heavy GPU/PTY work no longer
        // blocks the window from appearing. (Previously `_ = GhosttyApp.shared` ran here,
        // before the window existed, leaving a Dock icon and no window on a cold launch.)
        // `showWindow` also kicks off a short, bounded series of launch-frame
        // corrections (see MainWindowController.ensureLaunchFrame) that defend the
        // Finder/`open` path, where LaunchServices can order the window in at 0×0
        // before its content size resolves.
        let main = MainWindowController()
        mainWindow = main
        main.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        // The "always running" menu-bar item — surfaces every session's pulse (§11).
        statusItem = StatusItemController()

        // Unix-socket control API + CLI, à la cmux's TerminalController.
        socket = SocketServer()
        try? socket?.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The window is disposable; sessions keep running (spec §11).
        false
    }

    // Reopen the main window from the menu-bar (snap-back).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { mainWindow?.showWindow(nil) }
        return true
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit The Sacred Terminal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // Edit menu (copy/paste reach the focused surface).
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettings() { SettingsWindowController.shared.show(tab: .agents) }

    /// Replace the process PATH with the user's login-shell PATH (run once at launch,
    /// before any session spawns). `-ilc` sources the interactive profile so nvm /
    /// Homebrew / ~/.local/bin land on PATH, matching what the user sees in a terminal.
    private func importShellPath() {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-ilc", "printf '%s' \"$PATH\""]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                setenv("PATH", path, 1)
            }
        } catch {
            // Keep the inherited PATH; absolute-path resolution in GhosttySurface still helps.
        }
    }
}
