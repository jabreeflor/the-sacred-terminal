import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: MainWindowController?
    private var statusItem: StatusItemController?
    private var socket: SocketServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock / app-switcher icon (spec §9 — the branching sacred-timeline mark).
        // The dev build runs unbundled, so set it at runtime; packaging also embeds it.
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }

        // Touch the Ghostty app early so libghostty is initialized once.
        _ = GhosttyApp.shared

        buildMenu()

        let main = MainWindowController()
        main.showWindow(nil)
        mainWindow = main

        // The "always running" menu-bar item — surfaces every session's pulse (§11).
        statusItem = StatusItemController()

        // Unix-socket control API + CLI, à la cmux's TerminalController.
        socket = SocketServer()
        try? socket?.start()

        NSApp.activate(ignoringOtherApps: true)
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
}
