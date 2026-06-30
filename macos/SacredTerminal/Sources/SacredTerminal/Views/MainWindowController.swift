import AppKit

/// The main window: a collapsible rail (projects → agent sessions) beside the
/// terminal workspace (tabs + splits), with a titlebar crumb (spec §5).
final class MainWindowController: NSWindowController, NSSplitViewControllerDelegate {
    private let rail = RailViewController()
    private let workspace = WorkspaceViewController()
    private let titlebar = TitlebarController()
    private var splitController: NSSplitViewController!
    private var sidebarItem: NSSplitViewItem!

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "The Sacred Terminal"
        window.center()
        window.setFrameAutosaveName("SacredMainWindow")
        super.init(window: window)

        splitController = NSSplitViewController()
        splitController.delegate = self

        sidebarItem = NSSplitViewItem(sidebarWithViewController: rail)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 320
        sidebarItem.canCollapse = true

        let mainItem = NSSplitViewItem(viewController: workspace)
        splitController.addSplitViewItem(sidebarItem)
        splitController.addSplitViewItem(mainItem)

        window.contentViewController = splitController

        // Titlebar accessory holds the project › session crumb + browser toggle.
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        accessory.view = titlebar.view
        window.addTitlebarAccessoryViewController(accessory)

        NotificationCenter.default.addObserver(self, selector: #selector(stateChanged),
                                               name: .sacredStateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(focusSession(_:)),
                                               name: .sacredFocusSession, object: nil)
        installShortcuts()
        syncSidebar()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func stateChanged() { syncSidebar() }

    private func syncSidebar() {
        sidebarItem.animator().isCollapsed = !AppState.shared.sidebarOpen
    }

    @objc private func focusSession(_ note: Notification) {
        if let id = note.object as? String { AppState.shared.setActive(id) }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Keyboard shortcuts (spec §6)

    private func installShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        let cmd = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        let opt = event.modifierFlags.contains(.option)
        guard cmd else { return false }
        let state = AppState.shared
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b" where opt:
            state.toggleBrowser(nil); return true
        case "b":
            state.toggleSidebar(); return true
        case "t":
            if let id = state.activeSessionID { state.addPane(id) }; return true
        case "d" where shift:
            if let id = state.activeSessionID { state.split(id, .vertical) }; return true
        case "d":
            if let id = state.activeSessionID { state.split(id, .horizontal) }; return true
        case "w":
            if let ctx = state.activeContext, ctx.session.panes.count > 1 {
                state.closePane(ctx.session.id, ctx.session.activePaneID); return true
            }
            return false
        case "n":
            let project = state.activeContext?.project ?? state.projects.first
            if let project { AgentPickerController.present(projectID: project.id, relativeTo: rail.view) }
            return true
        default:
            return false
        }
    }
}
