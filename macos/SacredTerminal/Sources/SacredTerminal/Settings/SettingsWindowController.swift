import AppKit

/// Settings window: three panes (Agents, Git, Appearance) switched by a toolbar.
/// All controls write straight into `AppState.shared` and call `changed()`.
final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    static let shared = SettingsWindowController()

    enum Tab: String, CaseIterable {
        case agents, git, appearance
        var title: String {
            switch self {
            case .agents: return "Agents"
            case .git: return "Git"
            case .appearance: return "Appearance"
            }
        }
        var symbol: String {
            switch self {
            case .agents: return "cpu"
            case .git: return "arrow.triangle.branch"
            case .appearance: return "paintbrush"
            }
        }
        var itemID: NSToolbarItem.Identifier { NSToolbarItem.Identifier("settings.\(rawValue)") }
    }

    private let container = NSView()
    private var currentTab: Tab = .agents
    private var paneView: NSView?
    private var observer: NSObjectProtocol?

    // MARK: - Init

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Settings"
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.chromeBg
        super.init(window: window)

        container.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.chromeBg.cgColor
        content.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            container.topAnchor.constraint(equalTo: content.topAnchor),
            container.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        if #available(macOS 11.0, *) { window.toolbarStyle = .preference }
        window.toolbar = toolbar
        toolbar.selectedItemIdentifier = currentTab.itemID

        observer = NotificationCenter.default.addObserver(
            forName: .sacredStateChanged, object: nil, queue: .main) { [weak self] _ in
            self?.rebuild()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    // MARK: - Public

    func show(tab: Tab) {
        currentTab = tab
        window?.toolbar?.selectedItemIdentifier = tab.itemID
        rebuild()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Toolbar

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = Tab.allCases.first(where: { $0.itemID == itemIdentifier }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(selectTab(_:))
        item.tag = Tab.allCases.firstIndex(of: tab) ?? 0
        return item
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map(\.itemID)
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map(\.itemID)
    }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map(\.itemID)
    }

    @objc private func selectTab(_ sender: NSToolbarItem) {
        guard sender.tag >= 0, sender.tag < Tab.allCases.count else { return }
        currentTab = Tab.allCases[sender.tag]
        rebuild()
    }

    // MARK: - Build

    private func rebuild() {
        paneView?.removeFromSuperview()
        let pane: NSView
        switch currentTab {
        case .agents: pane = buildAgentsPane()
        case .git: pane = buildGitPane()
        case .appearance: pane = buildAppearancePane()
        }
        pane.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pane.topAnchor.constraint(equalTo: container.topAnchor),
            pane.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        paneView = pane
    }

    /// A vertically-scrolling pane whose document is a flipped stack.
    private func scrollPane(_ build: (NSStackView) -> Void) -> NSView {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 26, bottom: 26, right: 26)
        build(stack)

        doc.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])

        scroll.documentView = doc
        NSLayoutConstraint.activate([
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        return scroll
    }

    // MARK: - Agents pane

    private func buildAgentsPane() -> NSView {
        scrollPane { stack in
            stack.addArrangedSubview(sectionTitle("AGENTS"))

            // YOLO toggle row
            let yoloRow = settingRow(
                title: "Open with YOLO mode",
                subtitle: "Skip permission prompts when launching new agent sessions.")
            let yoloSwitch = NSSwitch()
            yoloSwitch.state = AppState.shared.agentSettings.openWithYolo ? .on : .off
            yoloSwitch.target = self
            yoloSwitch.action = #selector(toggleYolo(_:))
            yoloRow.addArrangedSubview(yoloSwitch)
            stack.addArrangedSubview(card(yoloRow))

            // Pinned count header
            let pinnedCount = AppState.shared.pinnedAgents.count
            let header = sectionTitle("AVAILABLE AGENTS    \(pinnedCount)/\(Agents.maxPinned) PINNED")
            stack.addArrangedSubview(header)

            let openWithYolo = AppState.shared.agentSettings.openWithYolo
            let listStack = NSStackView()
            listStack.orientation = .vertical
            listStack.alignment = .leading
            listStack.spacing = 0
            listStack.translatesAutoresizingMaskIntoConstraints = false

            for (i, key) in Agents.order.enumerated() {
                let row = agentRow(key, openWithYolo: openWithYolo)
                listStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
                if i < Agents.order.count - 1 {
                    let div = divider()
                    listStack.addArrangedSubview(div)
                    div.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
                }
            }
            stack.addArrangedSubview(card(listStack))
        }
    }

    private func agentRow(_ key: AgentKey, openWithYolo: Bool) -> NSStackView {
        let def = Agents.def(key)
        let enabled = AppState.shared.agentEnabled.contains(key)
        let pinned = AppState.shared.pinnedAgents.contains(key)
        let pinnedFull = AppState.shared.pinnedAgents.count >= Agents.maxPinned

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        row.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

        // brand icon
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = Theme.agentImage(key)
        icon.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 26),
            icon.heightAnchor.constraint(equalToConstant: 26),
        ])
        row.addArrangedSubview(icon)

        // name + command preview
        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        let name = label(def.name, color: Theme.text, font: .systemFont(ofSize: 13, weight: .semibold))
        textStack.addArrangedSubview(name)
        let preview = label(Agents.launchPreview(key, yolo: openWithYolo),
                            color: Theme.textDim, font: Theme.monoSmall)
        preview.lineBreakMode = .byTruncatingTail
        textStack.addArrangedSubview(preview)
        row.addArrangedSubview(textStack)
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        // pin button
        let pin = NSButton()
        pin.bezelStyle = .regularSquare
        pin.isBordered = false
        pin.imagePosition = .imageOnly
        pin.translatesAutoresizingMaskIntoConstraints = false
        let pinSymbol = pinned ? "pin.fill" : "pin"
        pin.image = NSImage(systemSymbolName: pinSymbol, accessibilityDescription: "Pin")
        pin.contentTintColor = pinned ? Theme.sessionActive : Theme.textFaint
        pin.target = self
        pin.action = #selector(togglePin(_:))
        pin.tag = Agents.order.firstIndex(of: key) ?? 0
        // disabled if not enabled, or pin list full and this one isn't already pinned
        pin.isEnabled = enabled && (pinned || !pinnedFull)
        NSLayoutConstraint.activate([
            pin.widthAnchor.constraint(equalToConstant: 26),
            pin.heightAnchor.constraint(equalToConstant: 26),
        ])
        row.addArrangedSubview(pin)

        // enabled/disabled segmented control
        let seg = NSSegmentedControl(labels: ["Enabled", "Disabled"],
                                     trackingMode: .selectOne, target: self,
                                     action: #selector(toggleEnabled(_:)))
        seg.translatesAutoresizingMaskIntoConstraints = false
        seg.selectedSegment = enabled ? 0 : 1
        seg.tag = Agents.order.firstIndex(of: key) ?? 0
        seg.segmentDistribution = .fillEqually
        NSLayoutConstraint.activate([
            seg.widthAnchor.constraint(equalToConstant: 150),
        ])
        row.addArrangedSubview(seg)

        return row
    }

    @objc private func toggleYolo(_ sender: NSSwitch) {
        AppState.shared.agentSettings.openWithYolo = (sender.state == .on)
        AppState.shared.changed()
    }

    @objc private func togglePin(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < Agents.order.count else { return }
        AppState.shared.togglePin(Agents.order[sender.tag])
    }

    @objc private func toggleEnabled(_ sender: NSSegmentedControl) {
        guard sender.tag >= 0, sender.tag < Agents.order.count else { return }
        AppState.shared.setAgentEnabled(Agents.order[sender.tag], sender.selectedSegment == 0)
    }

    // MARK: - Git pane

    private func buildGitPane() -> NSView {
        scrollPane { stack in
            stack.addArrangedSubview(sectionTitle("GIT"))

            let git = AppState.shared.git

            // Branch prefix segmented control
            let prefixRow = settingRow(
                title: "Branch prefix",
                subtitle: "Prefix new worktree branches with a namespace.")
            let prefixSeg = NSSegmentedControl(
                labels: ["git/", "custom", "none"], trackingMode: .selectOne,
                target: self, action: #selector(setBranchPrefix(_:)))
            prefixSeg.translatesAutoresizingMaskIntoConstraints = false
            prefixSeg.selectedSegment = ["git", "custom", "none"].firstIndex(of: git.branchPrefix) ?? 0
            prefixSeg.widthAnchor.constraint(equalToConstant: 220).isActive = true
            prefixRow.addArrangedSubview(prefixSeg)
            stack.addArrangedSubview(card(prefixRow))

            // Custom prefix text field (only when custom)
            if git.branchPrefix == "custom" {
                let customRow = settingRow(
                    title: "Custom prefix",
                    subtitle: "Used as the branch namespace, e.g. \"feature/\".")
                let field = NSTextField(string: git.customPrefix)
                field.translatesAutoresizingMaskIntoConstraints = false
                field.font = Theme.mono
                field.placeholderString = "feature"
                field.target = self
                field.action = #selector(setCustomPrefix(_:))
                field.widthAnchor.constraint(equalToConstant: 220).isActive = true
                customRow.addArrangedSubview(field)
                stack.addArrangedSubview(card(customRow))
            }

            stack.addArrangedSubview(card(checkboxRow(
                title: "Auto-rename branch",
                subtitle: "Rename the branch to match the task once the agent picks a name.",
                on: git.autoRenameBranch, action: #selector(setAutoRename(_:)))))

            stack.addArrangedSubview(card(checkboxRow(
                title: "Commit attribution",
                subtitle: "Add a Co-authored-by trailer crediting the agent.",
                on: git.commitAttribution, action: #selector(setCommitAttribution(_:)))))

            stack.addArrangedSubview(card(checkboxRow(
                title: "Keep main updated",
                subtitle: "Pull the base branch before creating a new worktree.",
                on: git.keepMainUpdated, action: #selector(setKeepMainUpdated(_:)))))

            stack.addArrangedSubview(card(checkboxRow(
                title: "Draft by default",
                subtitle: "Open pull requests as drafts.",
                on: git.draftByDefault, action: #selector(setDraftByDefault(_:)))))
        }
    }

    @objc private func setBranchPrefix(_ sender: NSSegmentedControl) {
        let values = ["git", "custom", "none"]
        guard sender.selectedSegment >= 0, sender.selectedSegment < values.count else { return }
        AppState.shared.git.branchPrefix = values[sender.selectedSegment]
        AppState.shared.changed()
    }

    @objc private func setCustomPrefix(_ sender: NSTextField) {
        AppState.shared.git.customPrefix = sender.stringValue
        AppState.shared.changed()
    }

    @objc private func setAutoRename(_ sender: NSButton) {
        AppState.shared.git.autoRenameBranch = (sender.state == .on)
        AppState.shared.changed()
    }

    @objc private func setCommitAttribution(_ sender: NSButton) {
        AppState.shared.git.commitAttribution = (sender.state == .on)
        AppState.shared.changed()
    }

    @objc private func setKeepMainUpdated(_ sender: NSButton) {
        AppState.shared.git.keepMainUpdated = (sender.state == .on)
        AppState.shared.changed()
    }

    @objc private func setDraftByDefault(_ sender: NSButton) {
        AppState.shared.git.draftByDefault = (sender.state == .on)
        AppState.shared.changed()
    }

    // MARK: - Appearance pane

    private func buildAppearancePane() -> NSView {
        scrollPane { stack in
            stack.addArrangedSubview(sectionTitle("APPEARANCE"))

            // Imported ghostty theme note (read-only)
            let themeBox = NSStackView()
            themeBox.orientation = .vertical
            themeBox.alignment = .leading
            themeBox.spacing = 4
            themeBox.translatesAutoresizingMaskIntoConstraints = false
            themeBox.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
            let themeTitle = label("Terminal theme", color: Theme.text,
                                   font: .systemFont(ofSize: 13, weight: .semibold))
            themeBox.addArrangedSubview(themeTitle)
            let themeVal = label(AppState.shared.appearance.ghosttyTheme,
                                 color: Theme.sessionActive, font: Theme.mono)
            themeBox.addArrangedSubview(themeVal)
            let note = label("Imported from ~/.config/ghostty/config. Terminal colors come from Ghostty.",
                             color: Theme.textFaint, font: Theme.monoSmall)
            note.lineBreakMode = .byWordWrapping
            themeBox.addArrangedSubview(note)
            stack.addArrangedSubview(card(themeBox))

            // Rail width
            let railRow = settingRow(
                title: "Rail width",
                subtitle: "Width of the session sidebar.")
            let railSeg = NSSegmentedControl(
                labels: ["Compact", "Standard", "Wide"], trackingMode: .selectOne,
                target: self, action: #selector(setRailWidth(_:)))
            railSeg.translatesAutoresizingMaskIntoConstraints = false
            let widths: [AppearanceSettings.RailWidth] = [.compact, .standard, .wide]
            railSeg.selectedSegment = widths.firstIndex(of: AppState.shared.appearance.railWidth) ?? 1
            railSeg.widthAnchor.constraint(equalToConstant: 240).isActive = true
            railRow.addArrangedSubview(railSeg)
            stack.addArrangedSubview(card(railRow))
        }
    }

    @objc private func setRailWidth(_ sender: NSSegmentedControl) {
        let widths: [AppearanceSettings.RailWidth] = [.compact, .standard, .wide]
        guard sender.selectedSegment >= 0, sender.selectedSegment < widths.count else { return }
        AppState.shared.appearance.railWidth = widths[sender.selectedSegment]
        AppState.shared.changed()
    }

    // MARK: - Reusable chrome builders

    private func sectionTitle(_ text: String) -> NSTextField {
        let l = label(text, color: Theme.textDim,
                      font: .systemFont(ofSize: 11, weight: .bold))
        return l
    }

    /// A title + subtitle column followed by a trailing control slot.
    private func settingRow(title: String, subtitle: String?) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        row.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.addArrangedSubview(label(title, color: Theme.text,
                                           font: .systemFont(ofSize: 13, weight: .semibold)))
        if let subtitle {
            let sub = label(subtitle, color: Theme.textDim, font: .systemFont(ofSize: 11))
            sub.lineBreakMode = .byWordWrapping
            textStack.addArrangedSubview(sub)
        }
        row.addArrangedSubview(textStack)
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)
        return row
    }

    /// A title/subtitle row whose trailing control is an NSButton checkbox.
    private func checkboxRow(title: String, subtitle: String?,
                             on: Bool, action: Selector) -> NSStackView {
        let row = settingRow(title: title, subtitle: subtitle)
        let check = NSButton(checkboxWithTitle: "", target: self, action: action)
        check.state = on ? .on : .off
        check.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(check)
        return row
    }

    /// Wraps a content view in a bordered dark card that stretches full width.
    private func card(_ content: NSView) -> NSView {
        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.wantsLayer = true
        box.layer?.backgroundColor = Theme.panelBg.cgColor
        box.layer?.cornerRadius = 8
        box.layer?.borderWidth = 1
        box.layer?.borderColor = Theme.border.cgColor

        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            content.topAnchor.constraint(equalTo: box.topAnchor),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            // fill the pane's content width (628 = 680 - 2*26 insets)
            box.widthAnchor.constraint(equalToConstant: 628),
        ])
        return box
    }

    private func divider() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = Theme.border.cgColor
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    private func label(_ text: String, color: NSColor, font: NSFont) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.textColor = color
        l.font = font
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isSelectable = false
        return l
    }
}

/// A top-anchored flipped container so scroll content grows downward.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
