import AppKit

/// The right pane: the active session's Ghostty-style tab bar, terminal area
/// (with optional split + browser), and the message input row (spec §5, §6, §12).
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

    // The message input field for the active session.
    private var inputField: NSTextField?

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

        // Drop the rest of the chrome (tab bar, splits, input, browser view).
        view.subviews.forEach { $0.removeFromSuperview() }
        inputField = nil

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
        let inputRow = buildInputRow(session: session)

        for v in [tabBar, terminalArea, inputRow] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: view.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 36),

            terminalArea.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            terminalArea.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            terminalArea.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            inputRow.topAnchor.constraint(equalTo: terminalArea.bottomAnchor),
            inputRow.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputRow.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputRow.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            inputRow.heightAnchor.constraint(equalToConstant: 44),
        ])

        // Focus the active pane's surface so keystrokes land where the eye is.
        if let host = hosts[session.activePaneID] {
            DispatchQueue.main.async { host.surface.focusSurface() }
        }
    }

    // MARK: - Empty state

    private func buildEmptyState() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "No session open")
        label.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        label.textColor = Theme.textDim

        let button = NSButton(title: "New session", target: self, action: #selector(openPicker))
        button.bezelStyle = .rounded
        button.contentTintColor = Theme.accent

        stack.addArrangedSubview(label)
        stack.addArrangedSubview(button)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    @objc private func openPicker() {
        guard let project = AppState.shared.projects.first else { return }
        AgentPickerController.present(projectID: project.id, relativeTo: view)
    }

    // MARK: - Tab bar (spec §6)

    private func buildTabBar(project: Project, session: Session) -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Theme.titlebarBg.cgColor

        let hairline = NSView()
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = Theme.border.cgColor
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
        actions.spacing = 4
        actions.translatesAutoresizingMaskIntoConstraints = false

        let splitRight = makeActionButton(symbol: "rectangle.righthalf.inset.filled",
                                          fallback: "⇥", tip: "Split right (⌘D)",
                                          action: #selector(splitRightAction))
        let splitDown = makeActionButton(symbol: "rectangle.bottomhalf.inset.filled",
                                         fallback: "⤓", tip: "Split down (⌘⇧D)",
                                         action: #selector(splitDownAction))
        let newTab = makeActionButton(symbol: "plus", fallback: "+",
                                      tip: "New tab (⌘T)", action: #selector(newTabAction))
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
            tabsStack.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -8),

            actions.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8),
            actions.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])

        return bar
    }

    private func makeTab(session: Session, pane: Pane) -> NSView {
        let isActive = pane.id == session.activePaneID
        let tab = TabButton(sessionID: session.id, paneID: pane.id)
        tab.wantsLayer = true
        tab.layer?.cornerRadius = 6
        tab.layer?.backgroundColor = (isActive ? Theme.hover : NSColor.clear).cgColor
        tab.target = self
        tab.action = #selector(tabClicked(_:))
        tab.translatesAutoresizingMaskIntoConstraints = false

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

            tab.heightAnchor.constraint(equalToConstant: 26),
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

    private func makeActionButton(symbol: String, fallback: String, tip: String,
                                  action: Selector) -> NSButton {
        let b: NSButton
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tip) {
            b = NSButton(image: img, target: self, action: action)
            b.contentTintColor = Theme.textDim
        } else {
            b = NSButton(title: fallback, target: self, action: action)
        }
        b.bezelStyle = .texturedRounded
        b.isBordered = false
        b.toolTip = tip
        b.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: 24),
            b.heightAnchor.constraint(equalToConstant: 24),
        ])
        return b
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
            let split = NSSplitView()
            split.isVertical = true            // side-by-side: terminal | browser
            split.dividerStyle = .thin
            split.translatesAutoresizingMaskIntoConstraints = false
            split.addArrangedSubview(panesView)
            split.addArrangedSubview(browserView)
            container.addSubview(split)
            pin(split, to: container)
        } else {
            tearDownBrowser()
            container.addSubview(panesView)
            pin(panesView, to: container)
        }

        return container
    }

    /// Build the pane layout: a 2-pane split, or just the active pane.
    private func buildPanes(project: Project, session: Session) -> NSView {
        if session.splitLayout != .none, session.panes.count >= 2 {
            let first = host(for: session.panes[0], project: project, session: session)
            let second = host(for: session.panes[1], project: project, session: session)

            let split = NSSplitView()
            // horizontal layout => side-by-side (vertical divider);
            // vertical layout => stacked (horizontal divider).
            split.isVertical = (session.splitLayout == .horizontal)
            split.dividerStyle = .thin
            split.translatesAutoresizingMaskIntoConstraints = false
            split.addArrangedSubview(first)
            split.addArrangedSubview(second)
            return split
        } else {
            let active = session.activePane
            return host(for: active, project: project, session: session)
        }
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

    // MARK: - Message input row (spec §6)

    private func buildInputRow(session: Session) -> NSView {
        let row = NSView()
        row.wantsLayer = true
        row.layer?.backgroundColor = Theme.panelBg.cgColor

        let hairline = NSView()
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = Theme.border.cgColor
        hairline.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(hairline)

        let activePane = session.activePane

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        if activePane.kind == .agent, let img = Theme.agentImage(session.agent) {
            icon.image = img
        } else {
            icon.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "shell")
            icon.contentTintColor = Theme.textDim
        }

        let field = NSTextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Theme.mono
        field.textColor = Theme.text
        field.delegate = self
        field.target = self
        field.action = #selector(submitMessage(_:))
        let agentName = Agents.def(session.agent).name
        field.placeholderString = activePane.kind == .shell
            ? "type a command…"
            : "message \(agentName)…"
        inputField = field

        row.addSubview(icon)
        row.addSubview(field)

        NSLayoutConstraint.activate([
            hairline.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            hairline.topAnchor.constraint(equalTo: row.topAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),

            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            field.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        return row
    }

    @objc private func submitMessage(_ sender: NSTextField) {
        let text = sender.stringValue
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let session = AppState.shared.activeContext?.session else { return }

        // Write into the active pane's live surface, then record the message.
        if let host = hosts[session.activePaneID] {
            host.surface.send(text: text + "\n")
        }
        AppState.shared.send(to: session.id, message: text)
        sender.stringValue = ""
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

// MARK: - NSTextFieldDelegate

extension WorkspaceViewController: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy selector: Selector) -> Bool {
        // Enter submits; everything else behaves normally.
        if selector == #selector(NSResponder.insertNewline(_:)) {
            if let field = control as? NSTextField { submitMessage(field) }
            return true
        }
        return false
    }
}

// MARK: - Lightweight controls carrying their pane identity

/// A clickable tab that remembers which session/pane it represents.
private final class TabButton: NSButton {
    let sessionID: String
    let paneID: String
    init(sessionID: String, paneID: String) {
        self.sessionID = sessionID
        self.paneID = paneID
        super.init(frame: .zero)
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
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
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
}
