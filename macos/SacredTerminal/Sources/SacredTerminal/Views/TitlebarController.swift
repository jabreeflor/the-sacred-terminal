import AppKit

/// A compact horizontal accessory pinned to the right of the window titlebar.
/// It shows the active session crumb — "project › task" (project bold, separator
/// faint, task dimmed and truncating) — followed by a globe toggle that opens the
/// in-session browser and a small "⎇ main" branch label. The crumb hides when no
/// session is active. The whole row rebuilds on `.sacredStateChanged`.
final class TitlebarController: NSViewController {

    private let crumb = NSStackView()
    private let projectLabel = NSTextField(labelWithString: "")
    private let separator = NSTextField(labelWithString: "›")
    private let taskLabel = NSTextField(labelWithString: "")
    private let globeButton = NSButton()
    private let branchLabel = NSTextField(labelWithString: "")

    private var observer: NSObjectProtocol?

    // MARK: - Lifecycle

    override func loadView() {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root

        // Project name — bold, primary text.
        projectLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        projectLabel.textColor = Theme.text
        projectLabel.lineBreakMode = .byTruncatingTail
        projectLabel.cell?.usesSingleLineMode = true
        projectLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        // Separator "›" — faint, fixed.
        separator.font = Theme.mono
        separator.textColor = Theme.textFaint
        separator.setContentCompressionResistancePriority(.required, for: .horizontal)
        separator.setContentHuggingPriority(.required, for: .horizontal)

        // Task — dimmed, truncates first when space is tight.
        taskLabel.font = Theme.monoSmall
        taskLabel.textColor = Theme.textDim
        taskLabel.lineBreakMode = .byTruncatingTail
        taskLabel.cell?.usesSingleLineMode = true
        taskLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        crumb.translatesAutoresizingMaskIntoConstraints = false
        crumb.orientation = .horizontal
        crumb.alignment = .centerY
        crumb.spacing = 7
        crumb.setViews([projectLabel, separator, taskLabel], in: .leading)

        // Globe toggle — opens/closes the in-session browser.
        globeButton.translatesAutoresizingMaskIntoConstraints = false
        globeButton.isBordered = false
        globeButton.bezelStyle = .regularSquare
        globeButton.imagePosition = .imageOnly
        globeButton.toolTip = "Toggle browser"
        globeButton.target = self
        globeButton.action = #selector(toggleBrowser)
        globeButton.contentTintColor = Theme.textDim
        if let img = NSImage(systemSymbolName: "globe", accessibilityDescription: "Toggle browser") {
            globeButton.image = img
        } else {
            globeButton.imagePosition = .noImage
            globeButton.title = "◍"
            globeButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        }
        globeButton.wantsLayer = true
        globeButton.layer?.cornerRadius = 5

        // Branch label "⎇ main".
        branchLabel.font = Theme.monoSmall
        branchLabel.textColor = Theme.textFaint
        branchLabel.stringValue = "⎇ main"
        branchLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        branchLabel.setContentHuggingPriority(.required, for: .horizontal)

        root.addSubview(crumb)
        root.addSubview(globeButton)
        root.addSubview(branchLabel)

        NSLayoutConstraint.activate([
            root.heightAnchor.constraint(equalToConstant: 28),
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 520),

            crumb.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            crumb.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            crumb.trailingAnchor.constraint(lessThanOrEqualTo: globeButton.leadingAnchor, constant: -10),

            globeButton.trailingAnchor.constraint(equalTo: branchLabel.leadingAnchor, constant: -10),
            globeButton.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            globeButton.widthAnchor.constraint(equalToConstant: 24),
            globeButton.heightAnchor.constraint(equalToConstant: 24),

            branchLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            branchLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
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

    /// A sensible intrinsic width so the titlebar reserves room for the accessory.
    override var preferredContentSize: NSSize {
        get { NSSize(width: 520, height: 28) }
        set {}
    }

    // MARK: - State

    private func rebuild() {
        let context = AppState.shared.activeContext

        if let context {
            crumb.isHidden = false
            projectLabel.stringValue = context.project.name
            taskLabel.stringValue = context.session.task

            let open = context.session.browserOpen
            globeButton.state = open ? .on : .off
            globeButton.contentTintColor = open ? Theme.accent : Theme.textDim
            globeButton.layer?.backgroundColor = open
                ? Theme.accent.withAlphaComponent(0.16).cgColor
                : NSColor.clear.cgColor
            globeButton.isEnabled = true
        } else {
            crumb.isHidden = true
            globeButton.state = .off
            globeButton.contentTintColor = Theme.textFaint
            globeButton.layer?.backgroundColor = NSColor.clear.cgColor
            globeButton.isEnabled = false
        }
    }

    // MARK: - Actions

    @objc private func toggleBrowser() {
        AppState.shared.toggleBrowser(nil)
    }
}
