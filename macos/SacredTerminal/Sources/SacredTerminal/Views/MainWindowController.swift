import AppKit

/// The main window: a collapsible rail (projects → agent sessions) beside the
/// terminal workspace (tabs + splits), with a titlebar crumb (spec §5).
final class MainWindowController: NSWindowController {
    private let rail = RailViewController()
    private let workspace = WorkspaceViewController()
    private var rootVC: RootViewController!

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "The Sacred Terminal"
        window.minSize = NSSize(width: 900, height: 640)
        // Don't let macOS restore a stale frame over our intended launch size.
        window.isRestorable = false
        super.init(window: window)

        // Root hosts the 38px titlebar + the rail/workspace split (RootViewController,
        // Auto Layout with a breakable preferred 1240 width). The window adopts the
        // content's fitting size, so set the launch size AFTER assigning the content
        // VC (which resets size limits from the VC's constraints).
        rootVC = RootViewController(rail: rail, workspace: workspace)
        window.contentViewController = rootVC
        window.setContentSize(NSSize(width: 1240, height: 820))
        window.center()

        // The project › task crumb lives in RootViewController's own 38px titlebar,
        // and RootViewController syncs rail collapse — so the window controller only
        // listens for menu-bar "focus this session" requests.
        NotificationCenter.default.addObserver(self, selector: #selector(focusSession(_:)),
                                               name: .sacredFocusSession, object: nil)
        installShortcuts()
    }

    required init?(coder: NSCoder) { fatalError() }

    // Re-assert the launch frame once after show, in case anything nudged it.
    private var didSizeOnce = false
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard !didSizeOnce else { return }
        didSizeOnce = true
        guard let window, window.frame.width < 1200 else { return }
        window.setFrame(NSRect(x: 0, y: 0, width: 1240, height: 820), display: true)
        window.center()
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
