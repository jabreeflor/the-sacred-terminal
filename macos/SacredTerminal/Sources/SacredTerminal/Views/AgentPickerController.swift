import AppKit

/// The "pre-open a session with…" popover (spec §6). Anchored to a project's
/// hover-pill "+" button (or any caller-supplied view), it lists the *enabled*
/// agents in roster order and a "worktree" toggle. Picking an agent creates the
/// session via `AppState` and dismisses the popover.
final class AgentPickerController: NSViewController {

    /// Held statically so the popover survives past `present(...)` returning.
    private static var activePopover: NSPopover?

    private let projectID: String
    private let worktreeCheckbox = NSButton()

    // MARK: - Presentation

    /// Show the picker anchored to `view`, pre-opening sessions in `projectID`.
    static func present(projectID: String, relativeTo view: NSView) {
        // Dismiss any picker already on screen.
        activePopover?.performClose(nil)

        let controller = AgentPickerController(projectID: projectID)

        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.animates = true
        // Force the dark chrome appearance regardless of system setting.
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = controller

        controller.popover = popover
        activePopover = popover

        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxX)
    }

    // MARK: - Init

    private weak var popover: NSPopover?

    private init(projectID: String) {
        self.projectID = projectID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - View

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.panelBg.cgColor
        view = root

        // Header.
        let header = NSTextField(labelWithString: "Pre-open a session with…")
        header.translatesAutoresizingMaskIntoConstraints = false
        header.font = Theme.monoSmall
        header.textColor = Theme.textDim

        // Worktree toggle.
        worktreeCheckbox.translatesAutoresizingMaskIntoConstraints = false
        worktreeCheckbox.setButtonType(.switch)
        worktreeCheckbox.title = "Open with worktree"
        worktreeCheckbox.font = Theme.monoSmall
        worktreeCheckbox.contentTintColor = Theme.text
        worktreeCheckbox.state = .off
        if let cell = worktreeCheckbox.cell as? NSButtonCell {
            cell.attributedTitle = NSAttributedString(
                string: "Open with worktree",
                attributes: [.foregroundColor: Theme.text, .font: Theme.monoSmall])
        }

        // Hairline between the toggle and the agent list.
        let hairline = NSView()
        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = Theme.border.cgColor

        // Agent list (enabled agents in roster order).
        let list = NSStackView()
        list.translatesAutoresizingMaskIntoConstraints = false
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 1

        let enabled = AppState.shared.agentEnabled
        for key in Agents.order where enabled.contains(key) {
            let row = AgentPickerRow(agent: key) { [weak self] in self?.pick(key) }
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }

        root.addSubview(header)
        root.addSubview(worktreeCheckbox)
        root.addSubview(hairline)
        root.addSubview(list)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 280),

            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),

            worktreeCheckbox.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            worktreeCheckbox.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            worktreeCheckbox.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),

            hairline.topAnchor.constraint(equalTo: worktreeCheckbox.bottomAnchor, constant: 12),
            hairline.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),

            list.topAnchor.constraint(equalTo: hairline.bottomAnchor, constant: 6),
            list.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            list.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            list.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Actions

    private func pick(_ key: AgentKey) {
        AppState.shared.createSession(projectID: projectID,
                                      agent: key,
                                      worktree: worktreeCheckbox.state == .on)
        dismissPopover()
    }

    private func dismissPopover() {
        (popover ?? AgentPickerController.activePopover)?.performClose(nil)
    }
}

// MARK: - NSPopoverDelegate

extension AgentPickerController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        // Drop the static reference once the popover is gone.
        if AgentPickerController.activePopover === (notification.object as? NSPopover) {
            AgentPickerController.activePopover = nil
        }
    }
}

// MARK: - Row

/// One selectable agent: brand icon, name, and provider. Highlights on hover and
/// fires `onPick` when clicked.
private final class AgentPickerRow: NSView {
    private let onPick: () -> Void
    private var tracking: NSTrackingArea?

    init(agent: AgentKey, onPick: @escaping () -> Void) {
        self.onPick = onPick
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 5

        let def = Agents.def(agent)

        // Brand icon.
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyUpOrDown
        if let img = Theme.agentImage(agent) {
            icon.image = img
        }

        // Name.
        let name = NSTextField(labelWithString: def.name)
        name.translatesAutoresizingMaskIntoConstraints = false
        name.font = Theme.mono
        name.textColor = Theme.text
        name.lineBreakMode = .byTruncatingTail

        // Provider.
        let provider = NSTextField(labelWithString: def.provider)
        provider.translatesAutoresizingMaskIntoConstraints = false
        provider.font = Theme.monoSmall
        provider.textColor = Theme.textFaint
        provider.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [name, provider])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        addSubview(icon)
        addSubview(textStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),

            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            textStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(fire))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func fire() { onPick() }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = Theme.hover.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
