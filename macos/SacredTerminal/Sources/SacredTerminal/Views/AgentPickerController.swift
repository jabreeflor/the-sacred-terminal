import AppKit

/// The "pre-open a session with…" picker (spec §6), matching the mock `.picker`:
/// a clean borderless FLOATING PANEL (no system arrow/material) over a dim scrim,
/// anchored just below the project's hover-pill "+". Picking an agent creates the
/// session via `AppState` and dismisses.
final class AgentPickerController: NSViewController {

    /// Held statically so the panel + scrim survive past `present(...)` returning.
    private static var active: AgentPickerController?

    private let projectID: String
    private var worktreeOn = false
    private weak var panel: PickerPanel?
    private weak var scrim: NSView?
    private var checkbox: WorktreeCheckbox?

    // MARK: - Presentation

    /// Dismiss any visible picker (e.g. after a relaunch or stuck scrim).
    static func dismissActive() {
        active?.dismiss()
    }

    static func present(projectID: String, relativeTo view: NSView) {
        dismissActive()
        guard let parent = view.window else { return }
        present(projectID: projectID, in: parent, anchor: .below(view))
    }

    /// Present centered in the window — used by ⌘N where anchoring to the whole rail
    /// would shove the picker off-screen.
    static func present(projectID: String, in window: NSWindow) {
        dismissActive()
        guard window.contentView != nil else { return }
        present(projectID: projectID, in: window, anchor: .centered)
    }

    private enum Anchor {
        case below(NSView)
        case centered
    }

    private static func present(projectID: String, in parent: NSWindow, anchor: Anchor) {
        guard let parentContent = parent.contentView else { return }

        let controller = AgentPickerController(projectID: projectID)
        controller.loadView()
        let content = controller.view
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize

        // Dim scrim over the whole window (mock `.scrim`, rgba(0,0,0,.35)).
        let scrim = NSView(frame: parentContent.bounds)
        scrim.autoresizingMask = [.width, .height]
        scrim.wantsLayer = true
        scrim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        parentContent.addSubview(scrim)
        scrim.addGestureRecognizer(NSClickGestureRecognizer(target: controller, action: #selector(scrimClicked)))
        controller.scrim = scrim

        // Borderless floating panel = the picker.
        let panel = PickerPanel(contentRect: NSRect(origin: .zero, size: size),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = content
        panel.onCancel = { [weak controller] in controller?.dismiss() }

        let origin: NSPoint
        switch anchor {
        case .below(let view):
            // Anchor below the pill's bottom-left + 6px (mock openPicker).
            let anchorInWindow = view.convert(view.bounds, to: nil)
            let anchorOnScreen = parent.convertToScreen(anchorInWindow)
            var x = anchorOnScreen.minX
            var y = anchorOnScreen.minY - 6 - size.height
            if let vf = parent.screen?.visibleFrame {
                x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
                y = max(y, vf.minY + 8)
            }
            origin = NSPoint(x: x, y: y)
        case .centered:
            let frame = parent.frame
            var x = frame.midX - size.width / 2
            var y = frame.midY - size.height / 2
            if let vf = parent.screen?.visibleFrame {
                x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
                y = min(max(y, vf.minY + 8), vf.maxY - size.height - 8)
            }
            origin = NSPoint(x: x, y: y)
        }
        panel.setFrameOrigin(origin)
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)

        controller.panel = panel
        active = controller
    }

    // MARK: - Init

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
        root.layer?.backgroundColor = Theme.pickerBg.cgColor       // #141417
        root.layer?.cornerRadius = 11
        root.layer?.borderWidth = 1
        root.layer?.borderColor = Theme.pickerLine.cgColor          // #2a2a30
        root.layer?.masksToBounds = true
        view = root

        // Header — uppercase, letterspaced, faint (mock `.picker .ph`).
        let header = NSTextField(labelWithString: "")
        header.translatesAutoresizingMaskIntoConstraints = false
        header.attributedStringValue = NSAttributedString(
            string: "PRE-OPEN A SESSION WITH…",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .bold),
                .foregroundColor: Theme.textFaint,
                .kern: 0.8,
            ])

        // Custom worktree checkbox row (mock `.picker-worktree`).
        let worktree = WorktreeCheckbox { [weak self] on in self?.worktreeOn = on }
        worktree.translatesAutoresizingMaskIntoConstraints = false
        self.checkbox = worktree

        // Agent list (enabled agents in roster order), no inter-row gap.
        let list = NSStackView()
        list.translatesAutoresizingMaskIntoConstraints = false
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0

        let enabled = AppState.shared.agentEnabled
        for key in Agents.order where enabled.contains(key) {
            let row = AgentPickerRow(agent: key) { [weak self] in self?.pick(key) }
            list.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
        if list.arrangedSubviews.isEmpty {
            let empty = NSTextField(labelWithString: "No agents enabled. Open settings to turn one on.")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = Theme.textDim
            empty.lineBreakMode = .byWordWrapping
            empty.preferredMaxLayoutWidth = 320
            list.addArrangedSubview(empty)
        }

        root.addSubview(header)
        root.addSubview(worktree)
        root.addSubview(list)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 360),

            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),

            worktree.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            worktree.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            worktree.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),

            list.topAnchor.constraint(equalTo: worktree.bottomAnchor, constant: 6),
            list.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            list.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            list.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Actions

    private func pick(_ key: AgentKey) {
        AppState.shared.createSession(projectID: projectID, agent: key, worktree: worktreeOn)
        dismiss()
    }

    @objc private func scrimClicked() { dismiss() }

    private func dismiss() {
        scrim?.removeFromSuperview()
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        if AgentPickerController.active === self { AgentPickerController.active = nil }
    }
}

// MARK: - Borderless panel that can take key (for Esc) and dismisses on cancel.

private final class PickerPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

// MARK: - Worktree checkbox row (mock `.picker-worktree`)

private final class WorktreeCheckbox: NSView {
    private var on = false
    private let onToggle: (Bool) -> Void
    private let box = CALayer()
    private let checkmark = NSImageView()
    private var tracking: NSTrackingArea?

    private let line = Theme.pickerLine                              // #2a2a30
    private let accent = NSColor(srgbRed: 0.114, green: 0.431, blue: 0.961, alpha: 1) // #1d6ef5

    init(onToggle: @escaping (Bool) -> Void) {
        self.onToggle = onToggle
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = line.cgColor
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.03).cgColor

        // 17px check tile.
        let tile = NSView()
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.wantsLayer = true
        box.cornerRadius = 5
        box.borderWidth = 1.5
        box.borderColor = Theme.hex("#3d3d46").cgColor
        box.backgroundColor = Theme.hex("#0f0f12").cgColor
        tile.layer = box
        tile.wantsLayer = true

        checkmark.translatesAutoresizingMaskIntoConstraints = false
        checkmark.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "on")
        checkmark.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        checkmark.contentTintColor = .white
        checkmark.isHidden = true
        tile.addSubview(checkmark)

        let label = NSTextField(labelWithString: "Open with worktree")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        label.textColor = Theme.hex("#c8c8d2")

        addSubview(tile)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 33),
            tile.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            tile.centerYAnchor.constraint(equalTo: centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: 17),
            tile.heightAnchor.constraint(equalToConstant: 17),
            checkmark.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            checkmark.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -11),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .assumeInside], owner: self)
        addTrackingArea(a); tracking = a
    }

    override func mouseEntered(with event: NSEvent) { if !on { layer?.borderColor = Theme.hex("#32323a").cgColor; layer?.backgroundColor = Theme.hover.cgColor } }
    override func mouseExited(with event: NSEvent) { if !on { restyle() } }
    override func mouseDown(with event: NSEvent) { on.toggle(); restyle(); onToggle(on) }

    private func restyle() {
        checkmark.isHidden = !on
        if on {
            layer?.backgroundColor = accent.withAlphaComponent(0.07).cgColor
            layer?.borderColor = accent.withAlphaComponent(0.28).cgColor
            box.backgroundColor = accent.cgColor
            box.borderColor = Theme.hex("#4d94f7").cgColor
        } else {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.03).cgColor
            layer?.borderColor = line.cgColor
            box.backgroundColor = Theme.hex("#0f0f12").cgColor
            box.borderColor = Theme.hex("#3d3d46").cgColor
        }
    }
}

// MARK: - Agent row

/// One selectable agent (mock `.agent`): a 32px icon slot + name + provider sub.
private final class AgentPickerRow: NSView {
    private let onPick: () -> Void
    private var tracking: NSTrackingArea?

    init(agent: AgentKey, onPick: @escaping () -> Void) {
        self.onPick = onPick
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8

        let def = Agents.def(agent)

        // 32px transparent slot with a 20px centered brand glyph.
        let slot = NSView()
        slot.translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.image = Theme.agentImage(agent)
        slot.addSubview(icon)

        let name = NSTextField(labelWithString: def.name)
        name.translatesAutoresizingMaskIntoConstraints = false
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.textColor = Theme.text
        name.lineBreakMode = .byTruncatingTail

        let provider = NSTextField(labelWithString: def.provider)
        provider.translatesAutoresizingMaskIntoConstraints = false
        provider.font = .systemFont(ofSize: 10.5)
        provider.textColor = Theme.textFaint
        provider.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [name, provider])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        addSubview(slot)
        addSubview(textStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 48),
            slot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            slot.centerYAnchor.constraint(equalTo: centerYAnchor),
            slot.widthAnchor.constraint(equalToConstant: 32),
            slot.heightAnchor.constraint(equalToConstant: 32),
            icon.centerXAnchor.constraint(equalTo: slot.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            textStack.leadingAnchor.constraint(equalTo: slot.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(fire))
        addGestureRecognizer(click)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { fire() }

    @objc private func fire() { onPick() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .assumeInside],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = Theme.hover.cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = NSColor.clear.cgColor }
}
