import AppKit

/// The right pane: the active session's Ghostty-style tab bar and terminal area
/// (with optional split + browser). The embedded Ghostty surface IS the input —
/// there is no separate composer row (spec §5, §6, §12).
///
/// Critical performance contract: each pane's `SurfaceView` is cached by `pane.id`
/// so a `.sacredStateChanged` rebuild reuses the live libghostty surface instead of
/// respawning the PTY.
///
/// To make that safe given that `SurfaceView.removeFromSuperview()` frees ghostty,
/// each surface lives permanently inside a plain `NSView` *host* (`PaneHost`). We
/// only ever reparent the host (a vanilla view with no teardown override) into the
/// freshly built layout; the surface never leaves its host until the pane is truly
/// closed — at which point freeing the PTY is exactly what we want.
final class WorkspaceViewController: NSViewController {

    /// A plain container that owns one live `SurfaceView` for a pane's lifetime.
    private final class PaneHost: NSView {
        let surface: SurfaceView
        init(surface: SurfaceView) {
            self.surface = surface
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = Theme.terminalBg.cgColor
            surface.translatesAutoresizingMaskIntoConstraints = false
            addSubview(surface)
            NSLayoutConstraint.activate([
                surface.topAnchor.constraint(equalTo: topAnchor),
                surface.leadingAnchor.constraint(equalTo: leadingAnchor),
                surface.trailingAnchor.constraint(equalTo: trailingAnchor),
                surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    }

    // Live pane hosts (each wrapping one libghostty surface), keyed by pane id.
    private var hosts: [String: PaneHost] = [:]

    // The currently mounted browser panel, if any (rebuilt on session change).
    private var browserController: BrowserPanelController?
    private var browserSessionID: String?

    // MARK: - View

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.chromeBg.cgColor
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(stateChanged),
                                               name: .sacredStateChanged, object: nil)
        rebuild()
    }

    @objc private func stateChanged() { rebuild() }

    // MARK: - Rebuild

    /// Re-create the chrome (tab bar, layout, input) from the active session.
    /// Pane hosts are reparented (not recreated), so their PTYs survive.
    private func rebuild() {
        let ctx = AppState.shared.activeContext

        // Detach hosts from the old layout WITHOUT freeing surfaces: a PaneHost is
        // a plain NSView, so `removeFromSuperview()` here is harmless.
        for host in hosts.values { host.removeFromSuperview() }

        // Drop the rest of the chrome (tab bar, splits, browser view).
        view.subviews.forEach { $0.removeFromSuperview() }

        guard let ctx else {
            tearDownAllHosts()
            tearDownBrowser()
            buildEmptyState()
            return
        }

        let project = ctx.project
        let session = ctx.session

        // Reap hosts whose panes no longer exist in the active session. Only one
        // session is visible at a time, so a host for any other pane is dead.
        let liveIDs = Set(session.panes.map(\.id))
        for (paneID, host) in hosts where !liveIDs.contains(paneID) {
            host.surface.removeFromSuperview()   // frees the libghostty surface
            hosts.removeValue(forKey: paneID)
        }

        let tabBar = buildTabBar(project: project, session: session)
        let terminalArea = buildTerminalArea(project: project, session: session)

        for v in [tabBar, terminalArea] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: view.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 32),

            // The Ghostty surface is the input, so the terminal fills to the bottom.
            terminalArea.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            terminalArea.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            terminalArea.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            terminalArea.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Focus the active pane's surface so keystrokes land where the eye is.
        focusActiveTerminal()
    }

    /// Make the active pane's libghostty surface first responder and sync focus.
    func focusActiveTerminal() {
        guard let id = AppState.shared.activeContext?.session.activePaneID,
              let host = hosts[id] else { return }
        DispatchQueue.main.async {
            let surface = host.surface
            if surface.window?.firstResponder === surface {
                surface.syncGhosttyFocus()
            } else {
                surface.focusSurface()
            }
        }
    }

    /// Reconcile libghostty focus flags after window key-state changes.
    func syncTerminalFocus() {
        for host in hosts.values { host.surface.syncGhosttyFocus() }
    }

    // MARK: - Empty state

    private func buildEmptyState() {
        let hasProjects = !AppState.shared.projects.isEmpty

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: hasProjects ? "No session open" : "No projects yet")
        title.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        title.textColor = Theme.textDim
        title.alignment = .center

        let hint = NSTextField(labelWithString: hasProjects
            ? "Hover a project and pick an agent, or press ⌘N."
            : "Add a project folder to start running agents.")
        hint.font = NSFont.systemFont(ofSize: 12)
        hint.textColor = Theme.textFaint
        hint.alignment = .center

        let pill = makeAccentPill(hasProjects ? "+ New session" : "+ Add project")

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(hint)
        stack.setCustomSpacing(16, after: hint)
        stack.addArrangedSubview(pill)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    /// A flat accent pill button (mock `.empty .pill`).
    private func makeAccentPill(_ title: String) -> NSButton {
        let b = NSButton(title: title, target: self, action: #selector(openPicker))
        b.translatesAutoresizingMaskIntoConstraints = false
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.wantsLayer = true
        b.layer?.backgroundColor = Theme.accent.cgColor
        b.layer?.cornerRadius = 8
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold)])
        b.heightAnchor.constraint(equalToConstant: 32).isActive = true
        b.widthAnchor.constraint(greaterThanOrEqualToConstant: 132).isActive = true
        return b
    }

    /// New-session affordance. With a project present, open the agent picker; with
    /// none, let the user choose a real folder first, then pick an agent for it.
    @objc private func openPicker() {
        if let project = AppState.shared.activeContext?.project ?? AppState.shared.projects.first {
            AgentPickerController.present(projectID: project.id, relativeTo: view)
        } else {
            importFolderThenPick()
        }
    }

    private func importFolderThenPick() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Project"
        panel.message = "Choose a project folder for your agents"
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url, let self else { return }
            AppState.shared.addProject(name: url.lastPathComponent, path: url.path)
            if let p = AppState.shared.projects.last {
                AgentPickerController.present(projectID: p.id, relativeTo: self.view)
            }
        }
    }

    // MARK: - Tab bar (spec §6)

    private func buildTabBar(project: Project, session: Session) -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Theme.titlebarBg.cgColor

        let hairline = NSView()
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = Theme.hairlineSoft.cgColor   // mock #222228
        hairline.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(hairline)

        let tabsStack = NSStackView()
        tabsStack.orientation = .horizontal
        tabsStack.alignment = .centerY
        tabsStack.spacing = 2
        tabsStack.translatesAutoresizingMaskIntoConstraints = false
        tabsStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        for pane in session.panes {
            tabsStack.addArrangedSubview(makeTab(session: session, pane: pane))
        }

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 2   // mock `.term-tab-actions { gap: 2px }`
        actions.translatesAutoresizingMaskIntoConstraints = false

        // The mock's content header has split/split/new-tab actions only — outline
        // rect+line glyphs (not filled SF Symbols). The session's working state is
        // shown by the rail spinner, not a pill here.
        let splitRight = makeActionButton(glyph: .splitRight,
                                          tip: "Split right (⌘D)",
                                          label: "Split right",
                                          identifier: "workspace-split-right",
                                          action: #selector(splitRightAction))
        let splitDown = makeActionButton(glyph: .splitDown,
                                         tip: "Split down (⌘⇧D)",
                                         label: "Split down",
                                         identifier: "workspace-split-down",
                                         action: #selector(splitDownAction))
        let newTab = makeActionButton(glyph: .newTab,
                                      tip: "New tab (⌘T)",
                                      label: "New tab",
                                      identifier: "workspace-new-tab",
                                      action: #selector(newTabAction))
        actions.addArrangedSubview(splitRight)
        actions.addArrangedSubview(splitDown)
        actions.addArrangedSubview(newTab)

        bar.addSubview(tabsStack)
        bar.addSubview(actions)

        NSLayoutConstraint.activate([
            hairline.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),

            tabsStack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8),
            tabsStack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            tabsStack.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -4),

            actions.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -6),
            actions.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])

        return bar
    }

    private func makeTab(session: Session, pane: Pane) -> NSView {
        let isActive = pane.id == session.activePaneID
        let tab = TabButton(sessionID: session.id, paneID: pane.id)
        tab.isActiveTab = isActive
        tab.wantsLayer = true
        tab.layer?.cornerRadius = 6
        // mock .term-tab.active { background: rgba(255,255,255,.06); border: 1px #2a2a30 }
        if isActive {
            tab.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
            tab.layer?.borderWidth = 1
            tab.layer?.borderColor = Theme.pickerLine.cgColor
        } else {
            tab.layer?.backgroundColor = NSColor.clear.cgColor
        }
        tab.target = self
        tab.action = #selector(tabClicked(_:))
        tab.translatesAutoresizingMaskIntoConstraints = false
        tab.setAccessibilityLabel("\(tabTitle(session: session, pane: pane)) tab")
        tab.setAccessibilityIdentifier("workspace-tab-\(pane.id)")
        tab.setAccessibilityValue(isActive ? "selected" : "not selected")

        // Brand mark for an agent pane, terminal glyph for a shell.
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        if pane.kind == .agent, let img = Theme.agentImage(session.agent) {
            icon.image = img
        } else {
            icon.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "shell")
            icon.contentTintColor = Theme.textDim
        }

        let title = NSTextField(labelWithString: tabTitle(session: session, pane: pane))
        title.font = Theme.monoSmall
        title.textColor = isActive ? Theme.text : Theme.textDim
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        tab.addSubview(icon)
        tab.addSubview(title)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: tab.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: tab.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            title.centerYAnchor.constraint(equalTo: tab.centerYAnchor),

            tab.heightAnchor.constraint(equalToConstant: 24),
            tab.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
            tab.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
        ])

        // Close button when more than one pane; otherwise pin title to trailing.
        if session.panes.count > 1 {
            let close = CloseButton(sessionID: session.id, paneID: pane.id)
            close.target = self
            close.action = #selector(closeTab(_:))
            close.translatesAutoresizingMaskIntoConstraints = false
            tab.addSubview(close)
            NSLayoutConstraint.activate([
                title.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -4),
                close.trailingAnchor.constraint(equalTo: tab.trailingAnchor, constant: -6),
                close.centerYAnchor.constraint(equalTo: tab.centerYAnchor),
                close.widthAnchor.constraint(equalToConstant: 14),
                close.heightAnchor.constraint(equalToConstant: 14),
            ])
        } else {
            title.trailingAnchor.constraint(equalTo: tab.trailingAnchor, constant: -8).isActive = true
        }

        return tab
    }

    private func tabTitle(session: Session, pane: Pane) -> String {
        if pane.kind == .agent { return Agents.def(session.agent).name }
        return pane.title.isEmpty ? "shell" : pane.title
    }

    /// The mock's `.term-tab-actions` glyphs: stroked rounded rect + a divider line
    /// (split right/down) and a plus (new tab).
    enum ActionGlyph { case splitRight, splitDown, newTab }

    private func makeActionButton(glyph: ActionGlyph,
                                  tip: String,
                                  label: String,
                                  identifier: String,
                                  action: Selector) -> NSButton {
        let b = HoverIconButton(image: actionGlyph(glyph), target: self, action: action)
        b.toolTip = tip
        b.setAccessibilityLabel(label)
        b.setAccessibilityIdentifier(identifier)
        b.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: 24),
            b.heightAnchor.constraint(equalToConstant: 24),
        ])
        return b
    }

    /// Draw the mock's outline icon (13×13) into a template image so contentTintColor
    /// applies. Geometry matches the mock SVG (24-unit viewBox: rect x3 y4 w18 h16).
    private func actionGlyph(_ kind: ActionGlyph) -> NSImage {
        let img = NSImage(size: NSSize(width: 13, height: 13), flipped: false) { _ in
            let s = 13.0 / 24.0
            let lw: CGFloat = 1.5
            NSColor.black.setStroke()
            let box = NSRect(x: 3 * s, y: 4 * s, width: 18 * s, height: 16 * s)
            let rect = NSBezierPath(roundedRect: box, xRadius: 2 * s, yRadius: 2 * s)
            rect.lineWidth = lw
            let line = NSBezierPath()
            line.lineWidth = lw
            line.lineCapStyle = .round
            switch kind {
            case .splitRight:
                rect.stroke()
                line.move(to: NSPoint(x: 12 * s, y: 4 * s)); line.line(to: NSPoint(x: 12 * s, y: 20 * s))
            case .splitDown:
                rect.stroke()
                line.move(to: NSPoint(x: 3 * s, y: 12 * s)); line.line(to: NSPoint(x: 21 * s, y: 12 * s))
            case .newTab:
                // Plus made of two strokes (no surrounding rect).
                line.move(to: NSPoint(x: 12 * s, y: 5 * s)); line.line(to: NSPoint(x: 12 * s, y: 19 * s))
                let h = NSBezierPath(); h.lineWidth = lw; h.lineCapStyle = .round
                h.move(to: NSPoint(x: 5 * s, y: 12 * s)); h.line(to: NSPoint(x: 19 * s, y: 12 * s))
                h.stroke()
            }
            line.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: - Tab / action targets

    @objc private func tabClicked(_ sender: TabButton) {
        AppState.shared.setActivePane(sender.sessionID, sender.paneID)
    }

    @objc private func closeTab(_ sender: CloseButton) {
        AppState.shared.closePane(sender.sessionID, sender.paneID)
    }

    @objc private func splitRightAction() {
        guard let id = AppState.shared.activeSessionID else { return }
        AppState.shared.split(id, .horizontal)
    }

    @objc private func splitDownAction() {
        guard let id = AppState.shared.activeSessionID else { return }
        AppState.shared.split(id, .vertical)
    }

    @objc private func newTabAction() {
        guard let id = AppState.shared.activeSessionID else { return }
        AppState.shared.addPane(id, kind: .shell)
    }

    // MARK: - Terminal area (+ optional browser, spec §12)

    private func buildTerminalArea(project: Project, session: Session) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = Theme.terminalBg.cgColor

        let panesView = buildPanes(project: project, session: session)

        if session.browserOpen {
            let browserView = browserPanelView(for: session)
            let split = SeamSplitView()
            split.isVertical = true            // side-by-side: terminal | browser
            split.dividerStyle = .thin
            split.translatesAutoresizingMaskIntoConstraints = false
            split.addArrangedSubview(panesView)
            split.addArrangedSubview(browserView)
            container.addSubview(split)
            pin(split, to: container)
            // Mock: term-workspace ~48% / browser ~52% — a breakable ratio constraint
            // (NSSplitView's setPosition timing is unreliable for the initial layout).
            let ratio = panesView.widthAnchor.constraint(equalTo: split.widthAnchor, multiplier: 0.48)
            ratio.priority = NSLayoutConstraint.Priority(700)
            ratio.isActive = true
        } else {
            tearDownBrowser()
            container.addSubview(panesView)
            pin(panesView, to: container)
        }

        return container
    }

    /// Build the pane layout: a 2-pane split (each cell ringed when focused), or
    /// just the active pane.
    private func buildPanes(project: Project, session: Session) -> NSView {
        if session.splitLayout != .none, session.panes.count >= 2 {
            let first = host(for: session.panes[0], project: project, session: session)
            let second = host(for: session.panes[1], project: project, session: session)

            let split = SeamSplitView()
            // horizontal layout => side-by-side (vertical divider);
            // vertical layout => stacked (horizontal divider).
            split.isVertical = (session.splitLayout == .horizontal)
            split.dividerStyle = .thin
            split.translatesAutoresizingMaskIntoConstraints = false
            split.addArrangedSubview(focusCell(first, focused: session.panes[0].id == session.activePaneID))
            split.addArrangedSubview(focusCell(second, focused: session.panes[1].id == session.activePaneID))
            return split
        } else {
            let active = session.activePane
            return host(for: active, project: project, session: session)
        }
    }

    /// Wrap a pane host in a cell that shows the mock's amber inset focus ring when
    /// it's the active pane (mock `.term-cell.focused`).
    private func focusCell(_ host: NSView, focused: Bool) -> NSView {
        let cell = NSView()
        cell.translatesAutoresizingMaskIntoConstraints = false
        cell.wantsLayer = true
        if focused {
            cell.layer?.borderWidth = 1
            cell.layer?.borderColor = Theme.sessionActive.withAlphaComponent(0.35).cgColor
        }
        host.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(host)
        pin(host, to: cell)
        return cell
    }

    /// Fetch (or lazily create) the cached `PaneHost` for a pane.
    private func host(for pane: Pane, project: Project, session: Session) -> PaneHost {
        if let existing = hosts[pane.id] { return existing }

        let key: AgentKey = (pane.kind == .shell) ? .shell : session.agent
        let argv = Agents.launchArgv(key, yolo: session.yolo)
        let surfaceView = SurfaceView(sessionID: session.id,
                                      paneID: pane.id,
                                      argv: argv,
                                      directory: project.path)
        let sessionID = session.id
        surfaceView.onFocus = { paneID in
            AppState.shared.setActivePane(sessionID, paneID)
        }
        let host = PaneHost(surface: surfaceView)
        host.translatesAutoresizingMaskIntoConstraints = false
        hosts[pane.id] = host
        return host
    }

    // MARK: - Browser panel (spec §12)

    private func browserPanelView(for session: Session) -> NSView {
        if browserController == nil || browserSessionID != session.id {
            tearDownBrowser()
            let controller = BrowserPanelController(session: session)
            addChild(controller)
            browserController = controller
            browserSessionID = session.id
        }
        let v = browserController!.view
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    private func tearDownBrowser() {
        guard let controller = browserController else { return }
        controller.view.removeFromSuperview()
        controller.removeFromParent()
        browserController = nil
        browserSessionID = nil
    }

    // MARK: - Host teardown

    private func tearDownAllHosts() {
        for host in hosts.values {
            host.surface.removeFromSuperview()   // frees the libghostty surface
        }
        hosts.removeAll()
    }

    // MARK: - Layout helpers

    private func pin(_ child: NSView, to parent: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

// MARK: - Lightweight controls carrying their pane identity

/// A clickable tab that remembers which session/pane it represents. Inactive tabs
/// take the mock's `.term-tab:hover` background; the active tab keeps its styling.
private final class TabButton: NSButton {
    let sessionID: String
    let paneID: String
    var isActiveTab = false
    private var tracking: NSTrackingArea?
    init(sessionID: String, paneID: String) {
        self.sessionID = sessionID
        self.paneID = paneID
        super.init(frame: .zero)
        isBordered = false
        title = ""
        setAccessibilityRole(.button)
        setButtonType(.momentaryChange)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .assumeInside], owner: self)
        addTrackingArea(a); tracking = a
    }
    override func mouseEntered(with event: NSEvent) {
        if !isActiveTab { layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor }
    }
    override func mouseExited(with event: NSEvent) {
        if !isActiveTab { layer?.backgroundColor = NSColor.clear.cgColor }
    }
}

/// An NSSplitView whose divider matches the mock's faint rgba(255,255,255,.06) seam.
private final class SeamSplitView: NSSplitView {
    override var dividerColor: NSColor { NSColor.white.withAlphaComponent(0.06) }
    override var dividerThickness: CGFloat { 1 }
}

/// The per-tab close affordance.
private final class CloseButton: NSButton {
    let sessionID: String
    let paneID: String
    init(sessionID: String, paneID: String) {
        self.sessionID = sessionID
        self.paneID = paneID
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .texturedRounded
        if let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: "close tab") {
            image = img
            contentTintColor = Theme.textDim
        } else {
            title = "×"
        }
        toolTip = "Close tab (⌘W)"
        setAccessibilityLabel("Close tab")
        setAccessibilityIdentifier("workspace-tab-close-\(paneID)")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
}

/// A borderless icon button that reproduces the mock `.term-tab-actions button`:
/// faint tint at rest, and on hover a rgba(255,255,255,.06) background + brighter
/// tint.
private final class HoverIconButton: NSButton {
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    convenience init(image: NSImage, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.image = image
        self.target = target
        self.action = action
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    private func commonInit() {
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        title = ""
        wantsLayer = true
        layer?.cornerRadius = 6
        contentTintColor = Theme.textFaint
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .assumeInside],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        contentTintColor = Theme.text
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
        contentTintColor = Theme.textFaint
    }
}
