import AppKit

/// The left rail (spec §5/§6): a gear + "+" top bar over a scrollable project tree.
/// Each project row is a folder glyph + monospace name (click toggles collapse) and,
/// on hover, reveals a pill of pinned-agent brand icons that pre-open sessions.
/// Under each expanded project, its sessions are single-line rows (brand icon or
/// spinner, task text, status dot, ⌘N hint); the active row is highlighted, and a
/// hover × closes the session. The whole tree rebuilds on `.sacredStateChanged`.
final class RailViewController: NSViewController {

    private let scrollView = NSScrollView()
    private let treeStack = NSStackView()
    /// Flipped container so the tree grows top-down inside the scroll view.
    private let documentView = FlippedView()

    private var observer: NSObjectProtocol?

    // MARK: - Lifecycle

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.railBg.cgColor
        view = root

        let topBar = makeTopBar()
        root.addSubview(topBar)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none
        root.addSubview(scrollView)

        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        treeStack.translatesAutoresizingMaskIntoConstraints = false
        treeStack.orientation = .vertical
        treeStack.alignment = .leading
        treeStack.distribution = .fill
        treeStack.spacing = 1
        treeStack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 12, right: 8)
        documentView.addSubview(treeStack)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: root.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 34),

            scrollView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            // Pin the document view's width to the clip view so rows fill the rail.
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),

            treeStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            treeStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            treeStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            treeStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observer = NotificationCenter.default.addObserver(
            forName: .sacredStateChanged, object: nil, queue: .main) { [weak self] _ in
            self?.rebuild()
        }
        rebuild()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Top bar

    private func makeTopBar() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.wantsLayer = true
        bar.layer?.backgroundColor = Theme.railBg.cgColor

        let gear = railIconButton(symbol: "gearshape", fallback: "⚙", tooltip: "Settings",
                                  target: self, action: #selector(openSettings))
        let plus = railIconButton(symbol: "plus", fallback: "+", tooltip: "Add project",
                                  target: self, action: #selector(showAddMenu(_:)))
        plusButton = plus

        // Right-aligned, like the mock's flex-end rail-top.
        let buttons = NSStackView(views: [gear, plus])
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.orientation = .horizontal
        buttons.spacing = 2
        bar.addSubview(buttons)

        NSLayoutConstraint.activate([
            buttons.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -6),
            buttons.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    private weak var plusButton: NSButton?

    // MARK: - Tree

    private func rebuild() {
        treeStack.arrangedSubviews.forEach {
            treeStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let state = AppState.shared
        // Global ⌘N hint counter across all visible session rows.
        var shortcutIndex = 0

        for project in state.projects {
            let row = ProjectRow(project: project)
            treeStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: treeStack.widthAnchor,
                                       constant: -(treeStack.edgeInsets.left + treeStack.edgeInsets.right)).isActive = true

            guard !project.collapsed else { continue }

            for session in project.sessions {
                shortcutIndex += 1
                let hint = shortcutIndex <= 9 ? shortcutIndex : nil
                let sRow = SessionRow(project: project, session: session, shortcut: hint,
                                      active: session.id == state.activeSessionID)
                treeStack.addArrangedSubview(sRow)
                sRow.widthAnchor.constraint(equalTo: treeStack.widthAnchor,
                                            constant: -(treeStack.edgeInsets.left + treeStack.edgeInsets.right)).isActive = true
            }
        }
    }

    // MARK: - Actions

    @objc private func openSettings() {
        SettingsWindowController.shared.show(tab: .agents)
    }

    @objc private func showAddMenu(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Import folder…", action: #selector(importFolder), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Create new project…", action: #selector(createProject), keyEquivalent: "")
            .target = self
        let origin = NSPoint(x: 0, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: sender)
    }

    @objc private func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Choose a folder to add as a project"
        let host = view.window
        let complete: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            AppState.shared.addProject(name: url.lastPathComponent, path: url.path)
        }
        if let host {
            panel.beginSheetModal(for: host, completionHandler: complete)
        } else {
            complete(panel.runModal())
        }
    }

    @objc private func createProject() {
        let alert = NSAlert()
        alert.messageText = "Create new project"
        alert.informativeText = "Give the project a name and a folder path."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(string: "")
        nameField.placeholderString = "Name"
        nameField.translatesAutoresizingMaskIntoConstraints = false

        let pathField = NSTextField(string: NSHomeDirectory())
        pathField.placeholderString = "/path/to/folder"
        pathField.translatesAutoresizingMaskIntoConstraints = false

        let fields = NSStackView(views: [labeled("Name", nameField), labeled("Path", pathField)])
        fields.orientation = .vertical
        fields.alignment = .leading
        fields.spacing = 8
        fields.translatesAutoresizingMaskIntoConstraints = false
        fields.frame = NSRect(x: 0, y: 0, width: 320, height: 70)
        NSLayoutConstraint.activate([
            nameField.widthAnchor.constraint(equalToConstant: 240),
            pathField.widthAnchor.constraint(equalToConstant: 240),
        ])
        alert.accessoryView = fields

        let submit: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            let path = pathField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { return }
            AppState.shared.addProject(name: nameField.stringValue, path: path)
        }
        if let host = view.window {
            alert.beginSheetModal(for: host, completionHandler: submit)
        } else {
            submit(alert.runModal())
        }
    }

    private func labeled(_ title: String, _ field: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = Theme.monoSmall
        label.textColor = Theme.textDim
        let stack = NSStackView(views: [label, field])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        return stack
    }
}

// MARK: - Project row

/// A single project header: folder glyph + monospace name (no chevron, matching
/// the mock). Clicking toggles collapse; hovering reveals the pinned-agent quick
/// pill (a solid, shadowed bar) on the trailing edge. The pill's buttons stay
/// clickable because hit-testing routes pill hits to the buttons and every other
/// hit to the row's own `mouseDown` (toggle).
private final class ProjectRow: HoverView {
    private let project: Project
    private let folder = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pill = PillBar()

    init(project: Project) {
        self.project = project
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7

        // Gray folder glyph (SF Symbol), matching the mock's --text-dim folder.
        folder.translatesAutoresizingMaskIntoConstraints = false
        folder.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Project")
        folder.contentTintColor = Theme.textDim
        folder.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        folder.setContentHuggingPriority(.required, for: .horizontal)

        nameLabel.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold)
        nameLabel.textColor = Theme.text
        nameLabel.stringValue = project.name
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.cell?.usesSingleLineMode = true
        nameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let left = NSStackView(views: [folder, nameLabel])
        left.orientation = .horizontal
        left.spacing = 7
        left.alignment = .centerY
        left.translatesAutoresizingMaskIntoConstraints = false

        // Quick-pick pill: pinned agents + a "+" that opens the full picker.
        for agent in AppState.shared.railAgents {
            pill.addButton(AgentPillButton(agent: agent, projectID: project.id))
        }
        let plus = pillIconButton(symbol: "plus", fallback: "+", tooltip: "New session…",
                                  target: self, action: #selector(openPicker))
        pill.addButton(plus)

        addSubview(left)
        addSubview(pill)

        // The narrow rail can't fit name + full path inline (the mock hides the
        // path too), so the path is a hover tooltip.
        toolTip = project.path

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            folder.widthAnchor.constraint(equalToConstant: 15),
            folder.heightAnchor.constraint(equalToConstant: 14),
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            left.centerYAnchor.constraint(equalTo: centerYAnchor),
            left.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),

            pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Drive the pill with alpha, never isHidden: toggling isHidden dirties Auto
        // Layout, which rebuilds the hover tracking area and synthesizes spurious
        // enter/exit — the flicker. Alpha changes don't touch layout.
        pill.alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    // Route clicks: pill buttons fire their own actions; the rest toggles collapse.
    // The branch must NOT depend on hover/visibility-driven layout state — it keys
    // off pill.alphaValue (set by hover) so it can't feed the tracking loop.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if pill.alphaValue > 0, let v = super.hitTest(point), v != self, v.isDescendant(of: pill) {
            return v
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        AppState.shared.toggleCollapse(project.id)
    }

    @objc private func openPicker() {
        AgentPickerController.present(projectID: project.id, relativeTo: pill)
    }

    override func hoverChanged(_ hovering: Bool) {
        pill.animator().alphaValue = hovering ? 1 : 0
        layer?.backgroundColor = hovering ? Theme.hover.cgColor : NSColor.clear.cgColor
    }
}

/// The solid hover quick-pick bar (mock `.agent-bar`): a rounded, bordered,
/// shadowed pill that floats over the right edge of a project row.
private final class PillBar: NSView {
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 22/255, green: 22/255, blue: 28/255, alpha: 0.96).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.45
        layer?.shadowRadius = 11
        layer?.shadowOffset = CGSize(width: 0, height: -6)
        layer?.masksToBounds = false

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = 1
        stack.alignment = .centerY
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func addButton(_ b: NSView) { stack.addArrangedSubview(b) }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }
}

/// A small brand-icon button on the project hover pill that pre-opens a session.
private final class AgentPillButton: NSButton {
    private let agent: AgentKey
    private let projectID: String

    init(agent: AgentKey, projectID: String) {
        self.agent = agent
        self.projectID = projectID
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        title = ""
        wantsLayer = true
        layer?.cornerRadius = 12
        toolTip = "New \(Agents.def(agent).name) session"
        target = self
        action = #selector(fire)

        if let img = Theme.agentImage(agent) {
            image = resized(img, to: 16)
        } else {
            imagePosition = .noImage
            title = String(Agents.def(agent).name.prefix(1))
            font = Theme.monoSmall
            contentTintColor = Theme.textDim
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func resized(_ image: NSImage, to side: CGFloat) -> NSImage {
        let out = NSImage(size: NSSize(width: side, height: side))
        out.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        out.unlockFocus()
        return out
    }

    @objc func fire() {
        AppState.shared.createSession(projectID: projectID, agent: agent, worktree: false)
    }
}

/// A circular borderless icon button for the hover pill (24×24).
private func pillIconButton(symbol: String, fallback: String, tooltip: String,
                            target: AnyObject, action: Selector) -> NSButton {
    let b = NSButton()
    b.translatesAutoresizingMaskIntoConstraints = false
    b.isBordered = false
    b.bezelStyle = .regularSquare
    b.imagePosition = .imageOnly
    b.toolTip = tooltip
    b.target = target
    b.action = action
    b.contentTintColor = Theme.textDim
    b.wantsLayer = true
    b.layer?.cornerRadius = 12
    if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) {
        b.image = img
    } else {
        b.imagePosition = .noImage
        b.title = fallback
        b.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    }
    NSLayoutConstraint.activate([
        b.widthAnchor.constraint(equalToConstant: 24),
        b.heightAnchor.constraint(equalToConstant: 24),
    ])
    return b
}

// MARK: - Session row

/// A single-line session (mock `.session`): a faint drag handle, the agent's
/// brand icon (or a spinner while working/waiting), the task text, and a ⌘N hint.
/// The visible box is indented under its project; when active it gets the mock's
/// subtle PEACH fill + border (never a solid blue). A hover × closes it.
private final class SessionRow: HoverView {
    private let session: Session
    private let active: Bool

    private let box = NSView()
    private let iconView = NSImageView()
    private let spinner = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()

    init(project: Project, session: Session, shortcut: Int?, active: Bool) {
        self.session = session
        self.active = active
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let busy = session.status == .working || session.status == .waiting

        // The indented, optionally-highlighted box.
        box.translatesAutoresizingMaskIntoConstraints = false
        box.wantsLayer = true
        box.layer?.cornerRadius = 7
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.clear.cgColor

        // Faint drag handle (mock `.s-handle`).
        let handle = NSTextField(labelWithString: "⠿")
        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        handle.textColor = Theme.textFaint
        handle.alphaValue = 0.55

        // Brand icon vs. spinner.
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = Theme.agentImage(session.agent)
        iconView.isHidden = busy

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isHidden = !busy
        if busy { spinner.startAnimation(nil) }

        // Single-line task label (the agent identity is carried by the icon).
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        label.textColor = active ? Theme.text : Theme.textDim
        label.stringValue = session.task
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // ⌘N hint (hidden on hover to make room for ×).
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = Theme.monoSmall
        hintLabel.textColor = Theme.textFaint
        hintLabel.alphaValue = 0.55
        hintLabel.stringValue = shortcut.map { "⌘\($0)" } ?? ""

        // Close (×), revealed on hover.
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.title = "×"
        closeButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        closeButton.contentTintColor = Theme.textDim
        closeButton.target = self
        closeButton.action = #selector(close)
        closeButton.isHidden = true

        addSubview(box)
        box.addSubview(handle)
        box.addSubview(iconView)
        box.addSubview(spinner)
        box.addSubview(label)
        box.addSubview(hintLabel)
        box.addSubview(closeButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            // Indent the box under the project (mock `.sessions` padding-left:14).
            box.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            box.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            box.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            box.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            handle.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 6),
            handle.centerYAnchor.constraint(equalTo: box.centerYAnchor),

            iconView.leadingAnchor.constraint(equalTo: handle.trailingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            spinner.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: hintLabel.leadingAnchor, constant: -6),

            hintLabel.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            hintLabel.centerYAnchor.constraint(equalTo: box.centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -5),
            closeButton.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18),
        ])

        if active {
            box.layer?.backgroundColor = Theme.sessionActiveBg.cgColor
            box.layer?.borderColor = Theme.sessionActiveBorder.cgColor
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // Close button gets its own clicks; the rest of the row activates.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if !closeButton.isHidden {
            let local = convert(point, from: superview)
            if closeButton.convert(closeButton.bounds, to: self).contains(local) {
                return super.hitTest(point)
            }
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        AppState.shared.setActive(session.id)
    }

    @objc private func close() {
        AppState.shared.closeSession(session.id)
    }

    override func hoverChanged(_ hovering: Bool) {
        closeButton.isHidden = !hovering
        hintLabel.isHidden = hovering
        if !active {
            box.layer?.backgroundColor = hovering ? Theme.hover.cgColor : NSColor.clear.cgColor
        }
    }
}

// MARK: - Small reusable views

/// A flipped view so subviews lay out from the top-left downward.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A view that owns a tracking area and reports mouse enter/exit via `hoverChanged`.
private class HoverView: NSView {
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        // .assumeInside: when the area is (re)installed with the cursor already
        // inside, don't synthesize a phantom mouseEntered/Exited.
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .assumeInside],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hoverChanged(true) }
    override func mouseExited(with event: NSEvent) { hoverChanged(false) }

    /// Override to react to hover state.
    func hoverChanged(_ hovering: Bool) {}
}

/// A colored status dot that softly pulses (opacity) when `pulse` is true.
private final class DotView: NSView {
    var color: NSColor = Theme.textFaint { didSet { needsDisplay = true } }
    var pulse: Bool = false { didSet { updatePulse() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = bounds.width / 2
        layer.backgroundColor = color.cgColor
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.width / 2
    }

    private func updatePulse() {
        guard let layer else { return }
        layer.removeAnimation(forKey: "pulse")
        guard pulse else { layer.opacity = 1; return }
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.35
        anim.duration = 0.9
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(anim, forKey: "pulse")
    }
}

/// A borderless icon button using an SF Symbol when available, else a glyph.
private func railIconButton(symbol: String, fallback: String, tooltip: String,
                            target: AnyObject, action: Selector) -> NSButton {
    let b = NSButton()
    b.translatesAutoresizingMaskIntoConstraints = false
    b.isBordered = false
    b.bezelStyle = .regularSquare
    b.imagePosition = .imageOnly
    b.toolTip = tooltip
    b.target = target
    b.action = action
    b.contentTintColor = Theme.textDim
    if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) {
        b.image = img
    } else {
        b.imagePosition = .noImage
        b.title = fallback
        b.font = NSFont.systemFont(ofSize: 13, weight: .medium)
    }
    NSLayoutConstraint.activate([
        b.widthAnchor.constraint(equalToConstant: 24),
        b.heightAnchor.constraint(equalToConstant: 24),
    ])
    return b
}
