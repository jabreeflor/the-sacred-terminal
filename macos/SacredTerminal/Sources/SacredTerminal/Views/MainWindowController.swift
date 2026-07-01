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
        window.delegate = self

        // The project › task crumb lives in RootViewController's own 38px titlebar,
        // and RootViewController syncs rail collapse — so the window controller only
        // listens for menu-bar "focus this session" requests.
        NotificationCenter.default.addObserver(self, selector: #selector(focusSession(_:)),
                                               name: .sacredFocusSession, object: nil)
        installShortcuts()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The intended launch size — matches the design mock (docs/mock-design/index.html).
    private static let launchSize = NSSize(width: 1240, height: 820)
    /// Bounded number of launch-frame correction passes (see `ensureLaunchFrame`).
    private var launchFramePassesLeft = 6

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        ensureLaunchFrame()
    }

    /// Defends the launch size against the Finder/`open` path. With a `contentViewController`
    /// the window derives its size from the content's Auto Layout fitting size, and on
    /// that launch path LaunchServices can order the window in *before* that size
    /// resolves — so it briefly comes up 0×0 (the documented symptom). A single
    /// synchronous re-assert can be re-clamped by a later layout pass, so instead we run
    /// a short, bounded series of passes over the first few runloop ticks: each pass
    /// snaps the frame back to the design size if it's degenerate, then the passes are
    /// exhausted. Because they all run during the first ~100ms of launch (long before
    /// the user can resize), this never fights a legitimate resize on reopen.
    func ensureLaunchFrame() {
        guard let window, launchFramePassesLeft > 0 else { return }
        launchFramePassesLeft -= 1
        if window.frame.width < 1200 || window.frame.height < 600 {
            window.setFrame(NSRect(origin: .zero, size: Self.launchSize), display: true)
            window.center()
        }
        DispatchQueue.main.async { [weak self] in self?.ensureLaunchFrame() }
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
            if let project, let window { AgentPickerController.present(projectID: project.id, in: window) }
            return true
        default:
            return false
        }
    }
}

// MARK: - Window focus → libghostty (matches Ghostty's BaseTerminalController)

extension MainWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        GhosttyApp.shared.setAppFocus(true)
        // LaunchServices often leaves first responder on the window itself.
        if window?.firstResponder === window {
            workspace.focusActiveTerminal()
        } else {
            workspace.syncTerminalFocus()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        GhosttyApp.shared.setAppFocus(false)
        workspace.syncTerminalFocus()
    }
}
