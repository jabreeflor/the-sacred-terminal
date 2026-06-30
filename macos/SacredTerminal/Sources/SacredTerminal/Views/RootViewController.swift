import AppKit

/// Hosts the mock's full-width titlebar (traffic lights · sidebar toggle ·
/// centered "project › task" crumb · browser toggle · branch) above a fixed-width
/// rail beside the terminal workspace. There is NO bottom status bar — the current
/// design (docs/mock-design/index.html) doesn't have one.
///
/// The rail/workspace split is laid out by hand (not NSSplitViewController, which
/// clamps the *window* to the panes' fitting width and refuses to grow). The mock
/// rail is a fixed-width aside (sized via Appearance → Rail width), collapsing to
/// zero on ⌘B — exactly what a width constraint gives us.
final class RootViewController: NSViewController {
    private let rail: NSViewController
    private let workspace: NSViewController
    private let titlebar = SacredTitlebar()
    private let divider = NSView()
    private var observer: NSObjectProtocol?

    init(rail: NSViewController, workspace: NSViewController) {
        self.rail = rail
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    private var railWidth: NSLayoutConstraint!

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.chromeBg.cgColor
        view = root

        addChild(rail)
        addChild(workspace)
        for v in [titlebar, rail.view, divider, workspace.view] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        divider.wantsLayer = true
        divider.layer?.backgroundColor = Theme.border.cgColor

        railWidth = rail.view.widthAnchor.constraint(equalToConstant: AppState.shared.appearance.railWidth.points)

        // The window with a content VC sizes itself to the content's *required*
        // minimum (lower-priority preferred sizes and setContentSize are ignored).
        // So the design width 1240×800 IS the required minimum — matching the mock.
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 1240),
            root.heightAnchor.constraint(greaterThanOrEqualToConstant: 800),

            titlebar.topAnchor.constraint(equalTo: root.topAnchor),
            titlebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            titlebar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            titlebar.heightAnchor.constraint(equalToConstant: 38),

            rail.view.topAnchor.constraint(equalTo: titlebar.bottomAnchor),
            rail.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            rail.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            railWidth,

            divider.topAnchor.constraint(equalTo: titlebar.bottomAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: rail.view.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            workspace.view.topAnchor.constraint(equalTo: titlebar.bottomAnchor),
            workspace.view.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            workspace.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            workspace.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        observer = NotificationCenter.default.addObserver(
            forName: .sacredStateChanged, object: nil, queue: .main) { [weak self] _ in self?.syncRail() }
        syncRail()
    }

    /// Apply collapse + rail-width settings (animated).
    private func syncRail() {
        let target = AppState.shared.sidebarOpen ? AppState.shared.appearance.railWidth.points : 0
        guard railWidth.constant != target else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.allowsImplicitAnimation = true
            railWidth.animator().constant = target
            divider.animator().alphaValue = target == 0 ? 0 : 1
            view.layoutSubtreeIfNeeded()
        }
    }
}

/// The mock's 38px titlebar drawn in the content (the window uses
/// `fullSizeContentView`, so the native traffic lights float over our bar at the
/// left). Left: a sidebar toggle. Center: the active session crumb. Right: a
/// browser toggle + "⎇ main" branch. Rebuilds on `.sacredStateChanged`.
private final class SacredTitlebar: NSView {
    private let sidebarButton = NSButton()
    private let crumbLabel = NSTextField(labelWithString: "")
    private let globeButton = NSButton()
    private let branchLabel = NSTextField(labelWithString: "")
    private var observer: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.titlebarBg.cgColor

        let hairline = NSView()
        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = Theme.border.cgColor
        addSubview(hairline)

        // Sidebar toggle (just right of the native traffic lights).
        configureIconButton(sidebarButton, symbol: "sidebar.left", fallback: "▤",
                            tooltip: "Toggle side rail (⌘B)", action: #selector(toggleSidebar))
        sidebarButton.contentTintColor = Theme.text
        addSubview(sidebarButton)

        // Centered crumb: a single attributed label (project bold › task dim). A
        // single label avoids the per-label intrinsic-size pitfalls of a stack.
        crumbLabel.translatesAutoresizingMaskIntoConstraints = false
        crumbLabel.lineBreakMode = .byTruncatingTail
        crumbLabel.cell?.usesSingleLineMode = true
        crumbLabel.alignment = .center
        crumbLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(crumbLabel)

        // Right: browser toggle + branch.
        configureIconButton(globeButton, symbol: "globe", fallback: "◍",
                            tooltip: "Toggle browser (⌘⌥B)", action: #selector(toggleBrowser))
        globeButton.wantsLayer = true
        globeButton.layer?.cornerRadius = 6
        addSubview(globeButton)

        branchLabel.translatesAutoresizingMaskIntoConstraints = false
        branchLabel.font = Theme.monoSmall
        branchLabel.textColor = Theme.textFaint
        branchLabel.stringValue = "⎇ main"
        branchLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        branchLabel.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(branchLabel)

        NSLayoutConstraint.activate([
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),

            // 78px reserves room for the native traffic lights.
            sidebarButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 80),
            sidebarButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            sidebarButton.widthAnchor.constraint(equalToConstant: 26),
            sidebarButton.heightAnchor.constraint(equalToConstant: 26),

            crumbLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            crumbLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            crumbLabel.leadingAnchor.constraint(greaterThanOrEqualTo: sidebarButton.trailingAnchor, constant: 8),
            crumbLabel.trailingAnchor.constraint(lessThanOrEqualTo: globeButton.leadingAnchor, constant: -8),

            globeButton.trailingAnchor.constraint(equalTo: branchLabel.leadingAnchor, constant: -10),
            globeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            globeButton.widthAnchor.constraint(equalToConstant: 26),
            globeButton.heightAnchor.constraint(equalToConstant: 26),

            branchLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            branchLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        observer = NotificationCenter.default.addObserver(
            forName: .sacredStateChanged, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    private func configureIconButton(_ b: NSButton, symbol: String, fallback: String,
                                     tooltip: String, action: Selector) {
        b.translatesAutoresizingMaskIntoConstraints = false
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.imagePosition = .imageOnly
        b.toolTip = tooltip
        b.target = self
        b.action = action
        b.contentTintColor = Theme.textDim
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) {
            b.image = img
        } else {
            b.imagePosition = .noImage
            b.title = fallback
            b.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        }
    }

    private func refresh() {
        let ctx = AppState.shared.activeContext
        if let ctx {
            let s = NSMutableAttributedString()
            s.append(NSAttributedString(string: ctx.project.name, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: Theme.text]))
            s.append(NSAttributedString(string: "  ›  ", attributes: [
                .font: Theme.mono, .foregroundColor: Theme.textFaint]))
            s.append(NSAttributedString(string: ctx.session.task, attributes: [
                .font: Theme.monoSmall, .foregroundColor: Theme.textDim]))
            crumbLabel.attributedStringValue = s
            crumbLabel.isHidden = false
            let open = ctx.session.browserOpen
            globeButton.contentTintColor = open ? Theme.accent : Theme.textDim
            globeButton.layer?.backgroundColor = open
                ? Theme.accent.withAlphaComponent(0.16).cgColor : NSColor.clear.cgColor
            globeButton.isEnabled = true
        } else {
            crumbLabel.isHidden = true
            globeButton.isEnabled = false
            globeButton.contentTintColor = Theme.textFaint
            globeButton.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    @objc private func toggleSidebar() { AppState.shared.toggleSidebar() }
    @objc private func toggleBrowser() { AppState.shared.toggleBrowser(nil) }
}
