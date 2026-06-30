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
            topBar.heightAnchor.constraint(equalToConstant: 44),

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

        let hairline = NSView()
        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = Theme.border.cgColor
        bar.addSubview(hairline)

        let gear = railIconButton(symbol: "gearshape", fallback: "⚙", tooltip: "Settings",
                                  target: self, action: #selector(openSettings))
        let plus = railIconButton(symbol: "plus", fallback: "+", tooltip: "Add project",
                                  target: self, action: #selector(showAddMenu(_:)))
        plusButton = plus

        let buttons = NSStackView(views: [gear, plus])
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.orientation = .horizontal
        buttons.spacing = 4
        bar.addSubview(buttons)

        NSLayoutConstraint.activate([
            buttons.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),
            buttons.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            hairline.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
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

/// A single project header: chevron + folder glyph + monospace name. Clicking
/// toggles collapse; hovering reveals the pinned-agent pill on the trailing edge.
private final class ProjectRow: HoverView {
    private let project: Project
    private let chevron = NSTextField(labelWithString: "")
    private let folder = NSTextField(labelWithString: "📁")
    private let nameLabel = NSTextField(labelWithString: "")
    private let pill: NSStackView

    init(project: Project) {
        self.project = project
        self.pill = NSStackView()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5

        chevron.font = Theme.monoSmall
        chevron.textColor = Theme.textFaint
        chevron.stringValue = project.collapsed ? "▸" : "▾"

        folder.font = NSFont.systemFont(ofSize: 11)
        folder.alphaValue = 0.85

        nameLabel.font = Theme.mono
        nameLabel.textColor = Theme.text
        nameLabel.stringValue = project.name
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let left = NSStackView(views: [chevron, folder, nameLabel])
        left.orientation = .horizontal
        left.spacing = 6
        left.alignment = .centerY
        left.translatesAutoresizingMaskIntoConstraints = false

        buildPill()

        addSubview(left)
        addSubview(pill)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            left.centerYAnchor.constraint(equalTo: centerYAnchor),
            left.trailingAnchor.constraint(lessThanOrEqualTo: pill.leadingAnchor, constant: -6),

            pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        pill.isHidden = true

        let click = NSClickGestureRecognizer(target: self, action: #selector(toggle))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildPill() {
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.orientation = .horizontal
        pill.spacing = 2
        pill.alignment = .centerY

        for agent in AppState.shared.railAgents {
            let b = agentPillButton(agent: agent, project: project)
            pill.addArrangedSubview(b)
        }
        // Trailing "+" opens the full agent picker.
        let plus = railIconButton(symbol: "plus", fallback: "+",
                                  tooltip: "New session…", target: self,
                                  action: #selector(openPicker))
        plus.toolTip = "New session…"
        pill.addArrangedSubview(plus)
    }

    private func agentPillButton(agent: AgentKey, project: Project) -> NSButton {
        let b = AgentPillButton(agent: agent, projectID: project.id)
        b.toolTip = "New \(Agents.def(agent).name) session"
        b.target = b
        b.action = #selector(AgentPillButton.fire)
        return b
    }

    @objc private func toggle() {
        AppState.shared.toggleCollapse(project.id)
    }

    @objc private func openPicker() {
        AgentPickerController.present(projectID: project.id, relativeTo: self)
    }

    override func hoverChanged(_ hovering: Bool) {
        pill.isHidden = !hovering
        layer?.backgroundColor = hovering ? Theme.hover.cgColor : NSColor.clear.cgColor
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
        layer?.cornerRadius = 4

        if let img = Theme.agentImage(agent) {
            image = resized(img, to: 16)
        } else {
            image = nil
            imagePosition = .noImage
            title = String(Agents.def(agent).name.prefix(1))
            font = Theme.monoSmall
            contentTintColor = Theme.textDim
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 22),
            heightAnchor.constraint(equalToConstant: 22),
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

// MARK: - Session row

/// A single-line session: brand icon (or spinner while working/waiting), task
/// text, a status dot (pulsing per `statusMeta`), and a ⌘N hint. Highlighted when
/// active; a hover × closes the session.
private final class SessionRow: HoverView {
    private let session: Session
    private let active: Bool

    private let iconView = NSImageView()
    private let spinner = NSProgressIndicator()
    private let taskLabel = NSTextField(labelWithString: "")
    private let dot = DotView()
    private let hintLabel = NSTextField(labelWithString: "")
    private let closeButton: NSButton

    init(project: Project, session: Session, shortcut: Int?, active: Bool) {
        self.session = session
        self.active = active
        self.closeButton = NSButton()
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5

        let meta = statusMeta(session.status)
        let busy = session.status == .working || session.status == .waiting

        // Brand icon vs. spinner.
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        if let img = Theme.agentImage(session.agent) {
            iconView.image = img
        }
        iconView.isHidden = busy

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isHidden = !busy
        if busy { spinner.startAnimation(nil) }

        let iconWrap = NSView()
        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.addSubview(iconView)
        iconWrap.addSubview(spinner)

        // Task text.
        taskLabel.font = Theme.monoSmall
        taskLabel.textColor = active ? Theme.text : Theme.textDim
        taskLabel.stringValue = session.task
        taskLabel.lineBreakMode = .byTruncatingTail
        taskLabel.cell?.usesSingleLineMode = true
        taskLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Status dot.
        dot.color = meta.color
        dot.pulse = meta.pulse

        // ⌘N hint.
        hintLabel.font = Theme.monoSmall
        hintLabel.textColor = Theme.textFaint
        hintLabel.stringValue = shortcut.map { "⌘\($0)" } ?? ""
        hintLabel.alignment = .right

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

        let row = NSStackView(views: [iconWrap, taskLabel])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false

        // Trailing cluster: dot + hint/close overlap on the right edge.
        let trailing = NSStackView(views: [dot, hintLabel])
        trailing.orientation = .horizontal
        trailing.spacing = 6
        trailing.alignment = .centerY
        trailing.translatesAutoresizingMaskIntoConstraints = false

        addSubview(row)
        addSubview(trailing)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),

            iconWrap.widthAnchor.constraint(equalToConstant: 16),
            iconWrap.heightAnchor.constraint(equalToConstant: 16),
            iconView.leadingAnchor.constraint(equalTo: iconWrap.leadingAnchor),
            iconView.trailingAnchor.constraint(equalTo: iconWrap.trailingAnchor),
            iconView.topAnchor.constraint(equalTo: iconWrap.topAnchor),
            iconView.bottomAnchor.constraint(equalTo: iconWrap.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),

            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -6),

            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor),

            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            hintLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18),
        ])

        if active {
            layer?.backgroundColor = Theme.sessionActive.withAlphaComponent(0.16).cgColor
            let stripe = NSView()
            stripe.translatesAutoresizingMaskIntoConstraints = false
            stripe.wantsLayer = true
            stripe.layer?.backgroundColor = Theme.sessionActive.cgColor
            stripe.layer?.cornerRadius = 1
            addSubview(stripe)
            NSLayoutConstraint.activate([
                stripe.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                stripe.centerYAnchor.constraint(equalTo: centerYAnchor),
                stripe.widthAnchor.constraint(equalToConstant: 2),
                stripe.heightAnchor.constraint(equalToConstant: 14),
            ])
        }

        let click = NSClickGestureRecognizer(target: self, action: #selector(activate))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func activate() {
        AppState.shared.setActive(session.id)
    }

    @objc private func close() {
        AppState.shared.closeSession(session.id)
    }

    override func hoverChanged(_ hovering: Bool) {
        // On hover, reveal × and tuck away the hint to make room.
        closeButton.isHidden = !hovering
        hintLabel.isHidden = hovering
        if !active {
            layer?.backgroundColor = hovering ? Theme.hover.cgColor : NSColor.clear.cgColor
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
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
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
