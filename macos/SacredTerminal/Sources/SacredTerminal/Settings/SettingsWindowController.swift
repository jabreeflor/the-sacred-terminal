import AppKit

/// Settings, matching docs/mock-design/index.html: a rounded, bordered dark panel
/// (`#141417` + `#2a2a30`, radius 12) floating over the app, with a "Settings"
/// header + ✕, folder-style tabs, and flat panes (sections separated by headings
/// and 1px dividers — never boxed, except the mock's explicit recipe/budget/import
/// cards). Controls write into `AppState.shared` and call `changed()`.
final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    enum Tab: String, CaseIterable {
        case agents, git, appearance
        var title: String {
            switch self {
            case .agents: return "Agents"
            case .git: return "Git + Source Control"
            case .appearance: return "Appearance"
            }
        }
    }

    // Mock palette.
    private let panelBg   = Theme.hex("#141417")
    private let bodyLine  = Theme.hex("#222228")
    private let inputBg   = Theme.hex("#0d0d10")
    private let inputLine = Theme.hex("#2a2a30")
    private let cardBg     = NSColor.white.withAlphaComponent(0.02)
    private let segOnBg    = NSColor(srgbRed: 0.114, green: 0.431, blue: 0.961, alpha: 0.22) // #1d6ef5@22
    private let segOnText  = Theme.hex("#9ec5ff")
    private let badgeBg    = NSColor.white.withAlphaComponent(0.06)

    private let contentWidth: CGFloat = 644   // 680 panel − 18×2 padding

    private let tabBar = NSStackView()
    private var tabButtons: [Tab: TabButton] = [:]
    private let paneContainer = NSView()
    private var currentTab: Tab = .agents
    private var paneView: NSView?
    private var observer: NSObjectProtocol?

    // MARK: - Init

    /// The rounded panel (mock `.settings-panel`), built once and re-hosted on show.
    private var container: NSView!
    private weak var scrim: NSView?
    private var keyMonitor: Any?

    private override init() {
        super.init()
        buildPanel()
        observer = NotificationCenter.default.addObserver(
            forName: .sacredStateChanged, object: nil, queue: .main) { [weak self] _ in
            self?.rebuild()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    private func buildPanel() {
        let c = NSView()
        c.translatesAutoresizingMaskIntoConstraints = false
        c.wantsLayer = true
        c.layer?.backgroundColor = panelBg.cgColor
        c.layer?.cornerRadius = 12
        c.layer?.borderWidth = 1
        c.layer?.borderColor = inputLine.cgColor
        c.layer?.masksToBounds = true
        container = c

        let header = makeHeader()
        let tabs = makeTabBar()
        paneContainer.translatesAutoresizingMaskIntoConstraints = false

        c.addSubview(header)
        c.addSubview(tabs)
        c.addSubview(paneContainer)

        // Intrinsic panel size (mock 680 wide; preferred ~640 tall, capped on show).
        let prefH = c.heightAnchor.constraint(equalToConstant: 640)
        prefH.priority = .defaultHigh

        NSLayoutConstraint.activate([
            c.widthAnchor.constraint(equalToConstant: 680),
            prefH,

            header.topAnchor.constraint(equalTo: c.topAnchor),
            header.leadingAnchor.constraint(equalTo: c.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: c.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),

            tabs.topAnchor.constraint(equalTo: header.bottomAnchor),
            tabs.leadingAnchor.constraint(equalTo: c.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: c.trailingAnchor),
            tabs.heightAnchor.constraint(equalToConstant: 40),

            paneContainer.topAnchor.constraint(equalTo: tabs.bottomAnchor),
            paneContainer.leadingAnchor.constraint(equalTo: c.leadingAnchor),
            paneContainer.trailingAnchor.constraint(equalTo: c.trailingAnchor),
            paneContainer.bottomAnchor.constraint(equalTo: c.bottomAnchor),
        ])
    }

    // MARK: - Public

    /// Present as an in-app centered overlay + dimmed scrim (mock `.scrim` +
    /// `.settings-panel`), hosted in the main window's content view.
    func show(tab: Tab) {
        currentTab = tab
        styleTabs()
        rebuild()

        guard let parent = (NSApp.windows.first { $0.contentViewController is RootViewController }) ?? NSApp.mainWindow,
              let parentContent = parent.contentView else { return }

        teardown()   // re-show: drop any prior overlay first

        // Dim scrim over the whole window.
        let s = NSView(frame: parentContent.bounds)
        s.autoresizingMask = [.width, .height]
        s.wantsLayer = true
        s.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        parentContent.addSubview(s)
        s.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(scrimClicked)))
        scrim = s

        // Centered panel; height capped to the window (mock max-height min(720,88vh)).
        parentContent.addSubview(container)
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: parentContent.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: parentContent.centerYAnchor),
            container.heightAnchor.constraint(lessThanOrEqualTo: parentContent.heightAnchor, multiplier: 0.9),
        ])

        parent.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.closeSettings(); return nil }   // Esc
            return e
        }
    }

    @objc private func scrimClicked() { closeSettings() }
    @objc fileprivate func closeSettings() { teardown() }

    private func teardown() {
        scrim?.removeFromSuperview()
        scrim = nil
        if container?.superview != nil { container.removeFromSuperview() }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
    }

    // MARK: - Header + tabs

    private func makeHeader() -> NSView {
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false

        let title = label("Settings", color: Theme.text, font: .systemFont(ofSize: 15, weight: .bold))
        bar.addSubview(title)

        let close = NSButton(title: "", target: self, action: #selector(closeSettings))
        close.translatesAutoresizingMaskIntoConstraints = false
        close.isBordered = false
        close.bezelStyle = .regularSquare
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        close.contentTintColor = Theme.textDim
        bar.addSubview(close)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 18),
            title.centerYAnchor.constraint(equalTo: bar.centerYAnchor, constant: 4),
            close.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
            close.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 24),
            close.heightAnchor.constraint(equalToConstant: 24),
        ])
        return bar
    }

    private func makeTabBar() -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false

        let hairline = NSView()
        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = bodyLine.cgColor
        wrap.addSubview(hairline)

        tabBar.orientation = .horizontal
        tabBar.alignment = .bottom
        tabBar.spacing = 4
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(tabBar)

        for tab in Tab.allCases {
            let b = TabButton(title: tab.title, borderColor: bodyLine, fill: panelBg)
            b.onClick = { [weak self] in self?.selectTab(tab) }
            tabButtons[tab] = b
            tabBar.addArrangedSubview(b)
        }

        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 18),
            tabBar.trailingAnchor.constraint(lessThanOrEqualTo: wrap.trailingAnchor, constant: -18),
            tabBar.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            hairline.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
        ])
        styleTabs()
        return wrap
    }

    private func styleTabs() {
        for (tab, b) in tabButtons { b.isActive = (tab == currentTab) }
    }

    private func selectTab(_ tab: Tab) {
        currentTab = tab
        styleTabs()
        rebuild()
    }

    // MARK: - Pane plumbing

    private func rebuild() {
        paneView?.removeFromSuperview()
        let pane: NSView
        switch currentTab {
        case .agents: pane = buildAgentsPane()
        case .git: pane = buildGitPane()
        case .appearance: pane = buildAppearancePane()
        }
        pane.translatesAutoresizingMaskIntoConstraints = false
        paneContainer.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: paneContainer.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: paneContainer.trailingAnchor),
            pane.topAnchor.constraint(equalTo: paneContainer.topAnchor),
            pane.bottomAnchor.constraint(equalTo: paneContainer.bottomAnchor),
        ])
        paneView = pane
    }

    /// A vertically-scrolling, flat pane. `build` adds full-width rows.
    private func scrollPane(_ build: (NSStackView) -> Void) -> NSView {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 18, bottom: 18, right: 18)
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

    private func add(_ row: NSView, to stack: NSStackView, gap: CGFloat = 0) {
        if gap > 0, let last = stack.arrangedSubviews.last {
            stack.setCustomSpacing(gap, after: last)
        }
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
    }

    // MARK: - Agents pane

    private func buildAgentsPane() -> NSView {
        scrollPane { stack in
            add(wrappedLabel("Enable agents for pre-open sessions. Pin up to \(Agents.maxPinned) for the project hover quick-select menu.",
                             color: Theme.textDim, font: .systemFont(ofSize: 12)), to: stack)

            // Meta row: Pinned X/6 (left) · Installed N detected (right).
            let pinned = AppState.shared.pinnedAgents.count
            let installed = AppState.shared.agentEnabled.count
            add(spread(metaItem("Pinned", "\(pinned)/\(Agents.maxPinned)"),
                       metaItem("Installed", "\(installed) detected"), height: 34), to: stack, gap: 6)

            // YOLO set-row.
            add(setRow(title: "Open with YOLO mode",
                       desc: "When pre-opening an agent session, launch with permission-bypass flags (--yolo, --dangerously-skip-permissions, …). Off uses each agent’s safe default command.",
                       control: makeSwitch(on: AppState.shared.agentSettings.openWithYolo) {
                           AppState.shared.agentSettings.openWithYolo = $0; AppState.shared.changed()
                       }), to: stack, gap: 2)

            // Agent rows (flat, hover only).
            let openWithYolo = AppState.shared.agentSettings.openWithYolo
            add(thinLine(), to: stack, gap: 10)
            for key in Agents.order {
                add(agentRow(key, openWithYolo: openWithYolo), to: stack, gap: 2)
            }
        }
    }

    private func agentRow(_ key: AgentKey, openWithYolo: Bool) -> NSView {
        let def = Agents.def(key)
        let enabled = AppState.shared.agentEnabled.contains(key)
        let pinned = AppState.shared.pinnedAgents.contains(key)
        let pinnedFull = AppState.shared.pinnedAgents.count >= Agents.maxPinned
        let idx = Agents.order.firstIndex(of: key) ?? 0

        let row = HoverRow()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.wantsLayer = true
        row.layer?.cornerRadius = 9
        row.hoverColor = Theme.hover

        // White rounded icon tile + brand mark (mock `.setting-agent-icon`).
        let tile = NSView()
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 8
        tile.layer?.backgroundColor = Theme.hex("#ececf1").cgColor
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = Theme.agentImage(key)
        icon.imageScaling = .scaleProportionallyUpOrDown
        tile.addSubview(icon)

        // Title: name + "Detected" pill.
        let name = label(def.name, color: Theme.text, font: .systemFont(ofSize: 13, weight: .semibold))
        let titleRow = NSStackView(views: [name, pillLabel("Detected")])
        titleRow.orientation = .horizontal
        titleRow.spacing = 7
        titleRow.alignment = .centerY
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        let cmd = label(Agents.launchPreview(key, yolo: openWithYolo),
                        color: Theme.textFaint, font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular))
        cmd.lineBreakMode = .byTruncatingTail
        cmd.cell?.usesSingleLineMode = true

        let body = NSStackView(views: [titleRow, cmd])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 3
        body.translatesAutoresizingMaskIntoConstraints = false
        body.alphaValue = enabled ? 1 : 0.55

        // Pin button.
        let pin = NSButton(title: "", target: self, action: #selector(togglePin(_:)))
        pin.translatesAutoresizingMaskIntoConstraints = false
        pin.isBordered = false
        pin.bezelStyle = .regularSquare
        pin.wantsLayer = true
        pin.layer?.cornerRadius = 7
        pin.layer?.borderWidth = 1
        pin.layer?.borderColor = pinned ? Theme.sessionActive.withAlphaComponent(0.35).cgColor : inputLine.cgColor
        pin.layer?.backgroundColor = pinned ? Theme.sessionActive.withAlphaComponent(0.10).cgColor : inputBg.cgColor
        pin.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: "Pin")
        pin.contentTintColor = pinned ? Theme.hex("#e5c890") : Theme.textFaint
        pin.tag = idx
        pin.isEnabled = enabled && (pinned || !pinnedFull)
        pin.toolTip = pinned ? "Unpin" : (pinnedFull ? "Pin list full" : "Pin to project hover menu")

        let seg = segToggle(isOn: enabled, tag: idx)

        let ctrls = NSStackView(views: [pin, seg])
        ctrls.orientation = .horizontal
        ctrls.spacing = 8
        ctrls.alignment = .centerY
        ctrls.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(tile); row.addSubview(body); row.addSubview(ctrls)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 54),
            tile.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
            tile.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: 34),
            tile.heightAnchor.constraint(equalToConstant: 34),
            icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            body.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 12),
            body.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            body.trailingAnchor.constraint(lessThanOrEqualTo: ctrls.leadingAnchor, constant: -12),
            ctrls.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            ctrls.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            pin.widthAnchor.constraint(equalToConstant: 28),
            pin.heightAnchor.constraint(equalToConstant: 28),
        ])
        return row
    }

    /// Enabled/Disabled pill toggle (mock `.seg-toggle`): blue when Enabled.
    private func segToggle(isOn: Bool, tag: Int) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.wantsLayer = true
        wrap.layer?.cornerRadius = 8
        wrap.layer?.borderWidth = 1
        wrap.layer?.borderColor = inputLine.cgColor
        wrap.layer?.backgroundColor = inputBg.cgColor
        wrap.layer?.masksToBounds = true

        let onB = NSButton(title: "", target: self, action: #selector(enableAgent(_:)))
        let offB = NSButton(title: "", target: self, action: #selector(disableAgent(_:)))
        for b in [onB, offB] {
            b.translatesAutoresizingMaskIntoConstraints = false
            b.isBordered = false; b.bezelStyle = .regularSquare; b.wantsLayer = true; b.tag = tag
        }
        onB.attributedTitle = segTitle("Enabled", active: isOn, blue: true)
        offB.attributedTitle = segTitle("Disabled", active: !isOn, blue: false)
        onB.layer?.backgroundColor = isOn ? segOnBg.cgColor : NSColor.clear.cgColor
        offB.layer?.backgroundColor = !isOn ? badgeBg.cgColor : NSColor.clear.cgColor

        let stack = NSStackView(views: [onB, offB])
        stack.orientation = .horizontal; stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrap.topAnchor),
            stack.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            wrap.heightAnchor.constraint(equalToConstant: 28),
            onB.widthAnchor.constraint(equalToConstant: 66),
            offB.widthAnchor.constraint(equalToConstant: 68),
        ])
        return wrap
    }

    private func segTitle(_ s: String, active: Bool, blue: Bool) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [
            .foregroundColor: active ? (blue ? segOnText : Theme.text) : Theme.textDim,
            .font: NSFont.systemFont(ofSize: 11, weight: active ? .semibold : .regular),
        ])
    }

    @objc private func togglePin(_ s: NSButton) { if s.tag >= 0, s.tag < Agents.order.count { AppState.shared.togglePin(Agents.order[s.tag]) } }
    @objc private func enableAgent(_ s: NSButton) { if s.tag >= 0, s.tag < Agents.order.count { AppState.shared.setAgentEnabled(Agents.order[s.tag], true) } }
    @objc private func disableAgent(_ s: NSButton) { if s.tag >= 0, s.tag < Agents.order.count { AppState.shared.setAgentEnabled(Agents.order[s.tag], false) } }

    // MARK: - Git pane

    private func buildGitPane() -> NSView {
        scrollPane { stack in
            let git = AppState.shared.git
            add(wrappedLabel("Branch naming, base refs, attribution, and Git AI author.",
                             color: Theme.textDim, font: .systemFont(ofSize: 12)), to: stack)

            // Branch prefix.
            add(sectionHeading("Branch prefix"), to: stack, gap: 16)
            add(wrappedLabel("Choose whether branch names use your Git username, a custom prefix, or no prefix.",
                             color: Theme.textDim, font: .systemFont(ofSize: 11)), to: stack, gap: 4)
            add(choiceSeg(["Git username", "Custom", "None"], values: ["git", "custom", "none"],
                          selected: git.branchPrefix, action: #selector(setBranchPrefix(_:))), to: stack, gap: 8)
            add(makeInput(git.customPrefix, placeholder: "No git username configured", action: #selector(setCustomPrefix(_:))), to: stack, gap: 8)

            // Toggles section.
            add(thinLine(), to: stack, gap: 18)
            add(setRow(title: "Keep local main up to date",
                       desc: "When creating a workspace, refresh the remote base and fast-forward your local main or master if there are no uncommitted changes.",
                       control: makeSwitch(on: git.keepMainUpdated) { AppState.shared.git.keepMainUpdated = $0; AppState.shared.changed() }), to: stack, gap: 6)
            add(divRow(setRow(title: "Source control group order",
                       desc: "Choose whether Changes, Staged Changes, or Untracked Files appear first.",
                       control: choiceSeg(["Changes first", "Staged first", "Untracked first"], values: ["changes", "staged", "untracked"],
                                          selected: git.scGroupOrder, action: #selector(setScGroupOrder(_:))))), to: stack)
            add(divRow(setRow(title: "Auto-rename branch",
                       desc: "When an agent starts in a new workspace, rename its auto-generated branch to a short name summarizing the task.",
                       control: makeSwitch(on: git.autoRenameBranch) { AppState.shared.git.autoRenameBranch = $0; AppState.shared.changed() })), to: stack)
            add(divRow(setRow(title: "Commit attribution",
                       desc: "Add attribution to commits, pull requests, and issues.",
                       control: makeSwitch(on: git.commitAttribution) { AppState.shared.git.commitAttribution = $0; AppState.shared.changed() })), to: stack)

            // Source control AI.
            add(sectionHeading("Source control AI"), to: stack, gap: 18)
            add(wrappedLabel("Recipes, prompts, and hosted-review defaults shared by the client.",
                             color: Theme.textDim, font: .systemFont(ofSize: 11)), to: stack, gap: 4)
            add(setRow(title: "Show source control AI actions",
                       desc: "Adds AI buttons that run the selected agent with the command template for that action.",
                       control: makeSwitch(on: git.showScAiActions) { AppState.shared.git.showScAiActions = $0; AppState.shared.changed() }), to: stack, gap: 4)

            // Action recipes.
            add(sectionHeading("Action recipes"), to: stack, gap: 18)
            add(wrappedLabel("Use variables only when you want the client to inject context. Leave the agent as default to follow your normal agent preference.",
                             color: Theme.textDim, font: .systemFont(ofSize: 11)), to: stack, gap: 4)
            add(recipeCard("Commit message", "Generate the commit message from staged changes.",
                           vars: "{ } Variables: {basePrompt} {branch} {stagedFiles} {stagedPatch}"), to: stack, gap: 8)
            add(recipeCard("Pull request details", "Generate the hosted review title and description.",
                           vars: "{ } Variables: {basePrompt} {branch} {baseBranch} {commitSummary} {changedFiles}"), to: stack, gap: 10)
            add(recipeCard("Branch name", "Rename auto-created branches from the initial agent task.",
                           vars: "{ } Variables: {basePrompt} {firstPrompt} {assistantMessage}"), to: stack, gap: 10)

            // Custom command.
            add(sectionHeading("Custom command"), to: stack, gap: 18)
            add(wrappedLabel("Used by commit-message, pull-request, and branch-name recipes that select Custom command. Use {prompt} to pass the command input as an argument; otherwise it is piped on stdin.",
                             color: Theme.textDim, font: .systemFont(ofSize: 11)), to: stack, gap: 4)
            add(makeInput(git.customCommand, placeholder: "e.g. ollama run llama3.1 {prompt}", action: #selector(setCustomCommand(_:))), to: stack, gap: 8)

            // Hosted-review creation defaults.
            add(sectionHeading("Hosted-review creation defaults"), to: stack, gap: 18)
            add(wrappedLabel("Used by repositories that inherit global hosted-review defaults.",
                             color: Theme.textDim, font: .systemFont(ofSize: 11)), to: stack, gap: 4)
            add(checkRow("Draft by default", "Create hosted reviews as drafts unless changed in the composer.",
                         on: git.draftByDefault) { AppState.shared.git.draftByDefault = $0; AppState.shared.changed() }, to: stack, gap: 6)
            add(divRow(checkRow("Use review template when available", "Prefer repository pull request templates when no description is set.",
                         on: git.usePrTemplate) { AppState.shared.git.usePrTemplate = $0; AppState.shared.changed() }), to: stack)
            add(divRow(checkRow("Generate details when opening Create PR", "Run hosted-review detail generation once when the composer opens.",
                         on: git.generatePrOnOpen) { AppState.shared.git.generatePrOnOpen = $0; AppState.shared.changed() }), to: stack)
            add(divRow(checkRow("Open hosted review after creation", "Open the created hosted review in your browser after submit.",
                         on: git.openPrAfterCreate) { AppState.shared.git.openPrAfterCreate = $0; AppState.shared.changed() }), to: stack)

            // API budgets.
            add(budgetCard("GitHub API budget",
                           "Uses REST, Search, and GraphQL through the GitHub CLI. Budget scope: local machine.",
                           ["REST API: 4980 of 5000 left · resets in 11m",
                            "Search API: 30 of 30 left · resets in 15s",
                            "GraphQL API: 4983 of 5000 left · resets in 11m"]), to: stack, gap: 18)
            add(budgetCard("GitLab API budget",
                           "Uses REST through the GitLab CLI. Budget scope: local machine.",
                           ["GitLab API budget is unavailable."]), to: stack, gap: 10)
        }
    }

    @objc private func setBranchPrefix(_ s: NSButton) {
        let v = ["git", "custom", "none"]; guard s.tag >= 0, s.tag < v.count else { return }
        AppState.shared.git.branchPrefix = v[s.tag]; AppState.shared.changed()
    }
    @objc private func setScGroupOrder(_ s: NSButton) {
        let v = ["changes", "staged", "untracked"]; guard s.tag >= 0, s.tag < v.count else { return }
        AppState.shared.git.scGroupOrder = v[s.tag]; AppState.shared.changed()
    }
    @objc private func setCustomPrefix(_ s: NSTextField) { AppState.shared.git.customPrefix = s.stringValue; AppState.shared.changed() }
    @objc private func setCustomCommand(_ s: NSTextField) { AppState.shared.git.customCommand = s.stringValue; AppState.shared.changed() }

    // MARK: - Appearance pane

    private func buildAppearancePane() -> NSView {
        scrollPane { stack in
            let ap = AppState.shared.appearance
            add(wrappedLabel("Terminal colors come from Ghostty. Customize the side rail here.",
                             color: Theme.textDim, font: .systemFont(ofSize: 12)), to: stack)

            add(sectionHeading("Terminal"), to: stack, gap: 14)
            let resolved = GhosttyApp.resolvedTheme()
            add(wrappedLabel(resolved.isAppDefault
                                ? "No theme set in your Ghostty config, so sessions use the app's default. Set `theme` in Ghostty to override it."
                                : "Imported from your Ghostty config — not editable in this app.",
                             color: Theme.textDim, font: .systemFont(ofSize: 11)), to: stack, gap: 4)
            add(ghosttyImportCard(theme: resolved.name, isAppDefault: resolved.isAppDefault), to: stack, gap: 8)
            add(wrappedLabel("Change the theme in your Ghostty config, then start a new session to apply it. Open location reveals the config file in Finder.",
                             color: Theme.textDim, font: .systemFont(ofSize: 11)), to: stack, gap: 8)

            add(sectionHeading("Side rail"), to: stack, gap: 18)
            add(wrappedLabel("App chrome only — does not affect the terminal pane.",
                             color: Theme.textDim, font: .systemFont(ofSize: 11)), to: stack, gap: 4)

            add(setRow(title: "Background", desc: "Main rail color.",
                       control: ColorControl(hexString: ap.railBg) { AppState.shared.appearance.railBg = $0; AppState.shared.changed() }), to: stack, gap: 6)
            add(divRow(setRow(title: "Foreground", desc: "Primary text color in the rail.",
                       control: ColorControl(hexString: ap.railFg) { AppState.shared.appearance.railFg = $0; AppState.shared.changed() })), to: stack)
            add(divRow(setRow(title: "Rail width", desc: "Horizontal space for the project tree.",
                       control: choiceSeg(["Compact", "Default", "Wide"], values: ["compact", "standard", "wide"],
                                          selected: railWidthValue(), action: #selector(setRailWidth(_:))))), to: stack)
            add(divRow(setRow(title: "Active session highlight", desc: "Border and fill for the selected session row.",
                       control: ColorControl(hexString: ap.sessionHighlight) { AppState.shared.appearance.sessionHighlight = $0; AppState.shared.changed() })), to: stack)

            add(railPreview(), to: stack, gap: 12)
        }
    }

    private func railWidthValue() -> String {
        switch AppState.shared.appearance.railWidth {
        case .compact: return "compact"; case .standard: return "standard"; case .wide: return "wide"
        }
    }
    @objc private func setRailWidth(_ s: NSButton) {
        let map: [AppearanceSettings.RailWidth] = [.compact, .standard, .wide]
        guard s.tag >= 0, s.tag < map.count else { return }
        AppState.shared.appearance.railWidth = map[s.tag]; AppState.shared.changed()
    }

    // Re-detect the Ghostty theme from disk: `changed()` rebuilds the pane, which
    // re-reads GhosttyApp.resolvedTheme(). (New sessions pick up a changed theme.)
    @objc private func reloadGhostty() { AppState.shared.changed() }
    @objc private func openGhosttyLocation() {
        let path = (NSString(string: "~/.config/ghostty/config")).expandingTildeInPath
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: - Cards

    private func ghosttyImportCard(theme: String, isAppDefault: Bool) -> NSView {
        let card = cardView()

        let swatch = NSView()
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 8
        swatch.layer?.backgroundColor = Theme.terminalBg.cgColor
        swatch.layer?.borderWidth = 1
        swatch.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor

        let importLabel = label(isAppDefault ? "DEFAULT THEME" : "IMPORTED THEME",
                                color: Theme.textFaint, font: .systemFont(ofSize: 10, weight: .semibold))
        let themeName = label(theme, color: segOnText, font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold))
        let pathMeta = label(isAppDefault ? "app default — no theme in Ghostty config" : "~/.config/ghostty/config",
                             color: Theme.textFaint, font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular))
        let body = NSStackView(views: [importLabel, themeName, pathMeta])
        body.orientation = .vertical; body.alignment = .leading; body.spacing = 3
        body.translatesAutoresizingMaskIntoConstraints = false

        let reload = ghosttyAction("Reload", action: #selector(reloadGhostty))
        let openLoc = ghosttyAction("Open location", action: #selector(openGhosttyLocation))
        let actions = NSStackView(views: [reload, openLoc])
        actions.orientation = .vertical; actions.alignment = .trailing; actions.spacing = 6
        actions.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(swatch); card.addSubview(body); card.addSubview(actions)
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 76),
            swatch.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            swatch.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            swatch.widthAnchor.constraint(equalToConstant: 52),
            swatch.heightAnchor.constraint(equalToConstant: 52),
            body.leadingAnchor.constraint(equalTo: swatch.trailingAnchor, constant: 12),
            body.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            actions.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            actions.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            body.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -10),
        ])
        return card
    }

    private func ghosttyAction(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: "", target: self, action: action)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.isBordered = false; b.bezelStyle = .regularSquare; b.wantsLayer = true
        b.layer?.cornerRadius = 7
        b.layer?.borderWidth = 1
        b.layer?.borderColor = inputLine.cgColor
        b.layer?.backgroundColor = inputBg.cgColor
        b.attributedTitle = NSAttributedString(string: "  \(title)  ", attributes: [
            .foregroundColor: Theme.textDim, .font: NSFont.systemFont(ofSize: 11),
        ])
        b.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return b
    }

    private func recipeCard(_ title: String, _ desc: String, vars: String) -> NSView {
        let card = cardView()

        let h = label(title, color: Theme.text, font: .systemFont(ofSize: 12.5, weight: .bold))
        let p = wrappedLabel(desc, color: Theme.textDim, font: .systemFont(ofSize: 11), maxWidth: 340)
        let headText = NSStackView(views: [h, p])
        headText.orientation = .vertical; headText.alignment = .leading; headText.spacing = 2
        headText.translatesAutoresizingMaskIntoConstraints = false

        let select = NSPopUpButton(frame: .zero, pullsDown: false)
        select.translatesAutoresizingMaskIntoConstraints = false
        select.addItem(withTitle: "Use default agent")
        select.font = .systemFont(ofSize: 11)

        let argLabel = label("CLI arguments", color: Theme.textDim, font: .systemFont(ofSize: 10.5))
        let argInput = plainInput("--model sonnet")
        let argCol = NSStackView(views: [argLabel, argInput])
        argCol.orientation = .vertical; argCol.alignment = .leading; argCol.spacing = 4
        argCol.translatesAutoresizingMaskIntoConstraints = false

        let tmplLabel = label("Command template", color: Theme.textDim, font: .systemFont(ofSize: 10.5))
        let tmplInput = plainInput("{basePrompt}")
        let tmplCol = NSStackView(views: [tmplLabel, tmplInput])
        tmplCol.orientation = .vertical; tmplCol.alignment = .leading; tmplCol.spacing = 4
        tmplCol.translatesAutoresizingMaskIntoConstraints = false

        let grid = NSStackView(views: [argCol, tmplCol])
        grid.orientation = .horizontal; grid.distribution = .fillEqually; grid.spacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false

        let varsLabel = label(vars, color: Theme.textFaint, font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular))
        varsLabel.lineBreakMode = .byTruncatingTail

        card.addSubview(headText); card.addSubview(select); card.addSubview(grid); card.addSubview(varsLabel)
        NSLayoutConstraint.activate([
            headText.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            headText.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            select.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            select.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            select.leadingAnchor.constraint(greaterThanOrEqualTo: headText.trailingAnchor, constant: 10),
            grid.topAnchor.constraint(equalTo: headText.bottomAnchor, constant: 10),
            grid.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            grid.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            argInput.widthAnchor.constraint(equalTo: tmplInput.widthAnchor),
            varsLabel.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 8),
            varsLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            varsLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            varsLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
        return card
    }

    private func budgetCard(_ title: String, _ desc: String, _ stats: [String]) -> NSView {
        let card = cardView()
        let views: [NSView] = [
            label(title, color: Theme.text, font: .systemFont(ofSize: 12.5, weight: .bold)),
            wrappedLabel(desc, color: Theme.textDim, font: .systemFont(ofSize: 11), maxWidth: contentWidth - 24),
        ] + stats.map { label($0, color: Theme.textDim, font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)) }
        let col = NSStackView(views: views)
        col.orientation = .vertical; col.alignment = .leading; col.spacing = 4
        col.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(col)
        NSLayoutConstraint.activate([
            col.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            col.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            col.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            col.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
        return card
    }

    private func railPreview() -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.wantsLayer = true
        wrap.layer?.cornerRadius = 10
        wrap.layer?.borderWidth = 1
        wrap.layer?.borderColor = Theme.border.cgColor
        wrap.layer?.masksToBounds = true

        let railSide = NSView()
        railSide.translatesAutoresizingMaskIntoConstraints = false
        railSide.wantsLayer = true
        // Render from the live Appearance values so the preview reflects the controls.
        railSide.layer?.backgroundColor = Theme.railBgLive.cgColor

        func bar(active: Bool) -> NSView {
            let v = NSView()
            v.translatesAutoresizingMaskIntoConstraints = false
            v.wantsLayer = true
            v.layer?.cornerRadius = 4
            if active {
                v.layer?.backgroundColor = Theme.sessionActiveBgLive.cgColor
                v.layer?.borderWidth = 1
                v.layer?.borderColor = Theme.sessionActiveBorderLive.cgColor
            } else {
                // Inactive rows hint at the Foreground color.
                v.layer?.backgroundColor = Theme.railFgLive.withAlphaComponent(0.12).cgColor
            }
            v.heightAnchor.constraint(equalToConstant: 8).isActive = true
            return v
        }
        let bars = NSStackView(views: [bar(active: false), bar(active: true), bar(active: false)])
        bars.orientation = .vertical; bars.spacing = 5; bars.alignment = .leading
        bars.distribution = .fill
        bars.translatesAutoresizingMaskIntoConstraints = false
        railSide.addSubview(bars)

        let mainSide = NSView()
        mainSide.translatesAutoresizingMaskIntoConstraints = false
        mainSide.wantsLayer = true
        mainSide.layer?.backgroundColor = Theme.terminalBg.cgColor

        wrap.addSubview(railSide); wrap.addSubview(mainSide)
        NSLayoutConstraint.activate([
            wrap.heightAnchor.constraint(equalToConstant: 88),
            railSide.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            railSide.topAnchor.constraint(equalTo: wrap.topAnchor),
            railSide.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            railSide.widthAnchor.constraint(equalTo: wrap.widthAnchor, multiplier: 0.38),
            bars.topAnchor.constraint(equalTo: railSide.topAnchor, constant: 8),
            bars.leadingAnchor.constraint(equalTo: railSide.leadingAnchor, constant: 6),
            bars.trailingAnchor.constraint(equalTo: railSide.trailingAnchor, constant: -6),
            mainSide.leadingAnchor.constraint(equalTo: railSide.trailingAnchor),
            mainSide.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            mainSide.topAnchor.constraint(equalTo: wrap.topAnchor),
            mainSide.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        // Bars stretch to the rail width.
        for b in bars.arrangedSubviews { b.widthAnchor.constraint(equalTo: bars.widthAnchor).isActive = true }
        return wrap
    }

    private func cardView() -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 1
        card.layer?.borderColor = inputLine.cgColor
        card.layer?.backgroundColor = cardBg.cgColor
        return card
    }

    // MARK: - Reusable mock-styled pieces

    private func metaItem(_ title: String, _ value: String) -> NSView {
        let row = NSStackView(views: [label(title, color: Theme.textDim, font: .systemFont(ofSize: 12)), pillLabel(value)])
        row.orientation = .horizontal; row.spacing = 6; row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    /// Two views pinned to opposite ends of a fixed-height row.
    private func spread(_ left: NSView, _ right: NSView, height: CGFloat) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        left.translatesAutoresizingMaskIntoConstraints = false
        right.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(left); row.addSubview(right)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: height),
            left.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            left.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            right.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func sectionHeading(_ text: String) -> NSView {
        label(text, color: Theme.text, font: .systemFont(ofSize: 13, weight: .bold))
    }

    /// Wrap a row with a 1px top divider (mock `.set-row { border-top }`).
    private func divRow(_ inner: NSView) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let line = NSView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        line.layer?.backgroundColor = Theme.hex("#1c1c22").cgColor
        inner.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(line); wrap.addSubview(inner)
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: wrap.topAnchor),
            line.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
            inner.topAnchor.constraint(equalTo: line.bottomAnchor),
            inner.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            inner.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        return wrap
    }

    /// Title + description column with a trailing control (mock `.set-row`).
    private func setRow(title: String, desc: String, control: NSView) -> NSView {
        let titleL = label(title, color: Theme.text, font: .systemFont(ofSize: 12.5, weight: .semibold))
        let descL = wrappedLabel(desc, color: Theme.textDim, font: .systemFont(ofSize: 11), maxWidth: 430)
        let body = NSStackView(views: [titleL, descL])
        body.orientation = .vertical; body.alignment = .leading; body.spacing = 2
        body.translatesAutoresizingMaskIntoConstraints = false

        control.translatesAutoresizingMaskIntoConstraints = false
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(body); row.addSubview(control)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 2),
            body.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
            body.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -10),
            body.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -16),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -2),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    /// Checkbox + (title + desc) (mock `.set-check-row`).
    private func checkRow(_ title: String, _ desc: String, on: Bool, onChange: @escaping (Bool) -> Void) -> NSView {
        let check = CheckBox(on: on, onChange: onChange)
        check.translatesAutoresizingMaskIntoConstraints = false
        let titleL = label(title, color: Theme.text, font: .systemFont(ofSize: 12.5, weight: .semibold))
        let descL = wrappedLabel(desc, color: Theme.textDim, font: .systemFont(ofSize: 11), maxWidth: 560)
        let body = NSStackView(views: [titleL, descL])
        body.orientation = .vertical; body.alignment = .leading; body.spacing = 2
        body.translatesAutoresizingMaskIntoConstraints = false
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(check); row.addSubview(body)
        NSLayoutConstraint.activate([
            check.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 2),
            check.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
            body.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 10),
            body.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            body.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8),
            body.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -2),
        ])
        return row
    }

    /// Choice segmented control built from buttons (mock `.set-seg`).
    private func choiceSeg(_ titles: [String], values: [String], selected: String, action: Selector) -> NSView {
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.wantsLayer = true
        wrap.layer?.cornerRadius = 8
        wrap.layer?.borderWidth = 1
        wrap.layer?.borderColor = inputLine.cgColor
        wrap.layer?.backgroundColor = inputBg.cgColor
        wrap.layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = .horizontal; stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        for (i, title) in titles.enumerated() {
            let on = values[i] == selected
            let b = NSButton(title: "", target: self, action: action)
            b.isBordered = false; b.bezelStyle = .regularSquare; b.wantsLayer = true; b.tag = i
            b.attributedTitle = NSAttributedString(string: "  \(title)  ", attributes: [
                .foregroundColor: on ? segOnText : Theme.textDim,
                .font: NSFont.systemFont(ofSize: 10.5, weight: on ? .semibold : .regular),
            ])
            b.layer?.backgroundColor = on ? segOnBg.cgColor : NSColor.clear.cgColor
            stack.addArrangedSubview(b)
            b.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        wrap.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrap.topAnchor),
            stack.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
        ])
        return wrap
    }

    /// Full-width text input (mock `.set-input`).
    private func makeInput(_ value: String, placeholder: String, action: Selector) -> NSView {
        let f = makeTextField(value, placeholder: placeholder)
        f.target = self; f.action = action
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(f)
        NSLayoutConstraint.activate([
            f.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 2),
            f.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -2),
            f.topAnchor.constraint(equalTo: wrap.topAnchor),
            f.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            f.heightAnchor.constraint(equalToConstant: 30),
        ])
        return wrap
    }

    /// A compact input used inside cards.
    private func plainInput(_ value: String) -> NSTextField {
        let f = makeTextField(value, placeholder: "")
        f.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return f
    }

    private func makeTextField(_ value: String, placeholder: String) -> NSTextField {
        let f = NSTextField(string: value)
        f.translatesAutoresizingMaskIntoConstraints = false
        f.placeholderString = placeholder
        f.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        f.textColor = Theme.text
        f.drawsBackground = true
        f.backgroundColor = inputBg
        f.isBordered = true
        f.bezelStyle = .roundedBezel
        f.focusRingType = .none
        return f
    }

    private func makeSwitch(on: Bool, onChange: @escaping (Bool) -> Void) -> NSView {
        let s = ToggleSwitch()
        s.isOn = on
        s.onToggle = onChange
        return s
    }

    private func pillLabel(_ text: String) -> NSView {
        let l = label(text, color: Theme.textFaint, font: .systemFont(ofSize: 10, weight: .medium))
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.wantsLayer = true
        wrap.layer?.cornerRadius = 8
        wrap.layer?.backgroundColor = badgeBg.cgColor
        l.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(l)
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 7),
            l.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -7),
            l.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 2),
            l.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -2),
        ])
        return wrap
    }

    private func thinLine() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = bodyLine.cgColor
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    private func wrappedLabel(_ text: String, color: NSColor, font: NSFont, maxWidth: CGFloat = 600) -> NSTextField {
        let l = label(text, color: color, font: font)
        l.lineBreakMode = .byWordWrapping
        l.preferredMaxLayoutWidth = maxWidth
        return l
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

/// A folder-style tab: transparent when inactive; when active it fills with the
/// panel color and draws a top + side border that merges into the body below.
private final class TabButton: NSView {
    var onClick: (() -> Void)?
    var isActive = false { didSet { restyle() } }

    private let titleLabel = NSTextField(labelWithString: "")
    private let fill: NSColor
    private let borderColor: NSColor
    private let top = NSView()
    private let left = NSView()
    private let right = NSView()

    init(title: String, borderColor: NSColor, fill: NSColor) {
        self.fill = fill
        self.borderColor = borderColor
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isSelectable = false
        addSubview(titleLabel)

        for v in [top, left, right] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.wantsLayer = true
            v.layer?.backgroundColor = borderColor.cgColor
            v.isHidden = true
            addSubview(v)
        }
        titleLabel.stringValue = title

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 31),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor, constant: -12),
            trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12),

            top.topAnchor.constraint(equalTo: topAnchor),
            top.leadingAnchor.constraint(equalTo: leadingAnchor),
            top.trailingAnchor.constraint(equalTo: trailingAnchor),
            top.heightAnchor.constraint(equalToConstant: 1),
            left.topAnchor.constraint(equalTo: topAnchor),
            left.bottomAnchor.constraint(equalTo: bottomAnchor),
            left.leadingAnchor.constraint(equalTo: leadingAnchor),
            left.widthAnchor.constraint(equalToConstant: 1),
            right.topAnchor.constraint(equalTo: topAnchor),
            right.bottomAnchor.constraint(equalTo: bottomAnchor),
            right.trailingAnchor.constraint(equalTo: trailingAnchor),
            right.widthAnchor.constraint(equalToConstant: 1),
        ])
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func restyle() {
        layer?.backgroundColor = isActive ? fill.cgColor : NSColor.clear.cgColor
        for v in [top, left, right] { v.isHidden = !isActive }
        titleLabel.attributedStringValue = NSAttributedString(string: titleLabel.stringValue, attributes: [
            .foregroundColor: isActive ? Theme.text : Theme.textDim,
            .font: NSFont.systemFont(ofSize: 12.5, weight: isActive ? .semibold : .medium),
        ])
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// A blue pill toggle matching the mock `.set-switch` (the native NSSwitch follows
/// the system accent color, which may not be blue — so we draw our own).
private final class ToggleSwitch: NSView {
    var isOn: Bool = false { didSet { relayout() } }
    var onToggle: ((Bool) -> Void)?

    private let track = CALayer()
    private let knob = CALayer()
    private let onColor = NSColor(srgbRed: 0.114, green: 0.431, blue: 0.961, alpha: 0.35)  // #1d6ef5@35
    private let onBorder = NSColor(srgbRed: 0.114, green: 0.431, blue: 0.961, alpha: 0.5)
    private let offColor = Theme.hex("#0d0d10")
    private let offBorder = Theme.hex("#2a2a30")

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 36, height: 20))
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        widthAnchor.constraint(equalToConstant: 36).isActive = true
        heightAnchor.constraint(equalToConstant: 20).isActive = true

        track.frame = NSRect(x: 0, y: 0, width: 36, height: 20)
        track.cornerRadius = 10
        track.borderWidth = 1
        knob.frame = NSRect(x: 2, y: 2, width: 14, height: 14)
        knob.cornerRadius = 7
        layer?.addSublayer(track)
        layer?.addSublayer(knob)
        relayout()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func relayout() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.backgroundColor = (isOn ? onColor : offColor).cgColor
        track.borderColor = (isOn ? onBorder : offBorder).cgColor
        knob.backgroundColor = (isOn ? Theme.hex("#9ec5ff") : Theme.hex("#5b5b63")).cgColor
        knob.frame = NSRect(x: isOn ? 18 : 2, y: 2, width: 14, height: 14)
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        onToggle?(isOn)
    }
}

/// A small square checkbox (mock `.set-check-row input`, accent blue).
private final class CheckBox: NSView {
    var isOn: Bool { didSet { restyle() } }
    private let onChange: (Bool) -> Void
    private let check = CALayer()

    init(on: Bool, onChange: @escaping (Bool) -> Void) {
        self.isOn = on
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        widthAnchor.constraint(equalToConstant: 16).isActive = true
        heightAnchor.constraint(equalToConstant: 16).isActive = true
        restyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func restyle() {
        let accent = NSColor(srgbRed: 0.114, green: 0.431, blue: 0.961, alpha: 1)
        layer?.backgroundColor = (isOn ? accent : Theme.hex("#0d0d10")).cgColor
        layer?.borderColor = (isOn ? accent : Theme.hex("#3d3d46")).cgColor
        toolTip = isOn ? "On" : "Off"
        layer?.contents = isOn ? checkImage() : nil
    }

    private func checkImage() -> CGImage? {
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size)
        img.lockFocus()
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 4, y: 8))
        p.line(to: NSPoint(x: 7, y: 5))
        p.line(to: NSPoint(x: 12, y: 11))
        NSColor.white.setStroke()
        p.lineWidth = 1.8
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        p.stroke()
        img.unlockFocus()
        var rect = NSRect(origin: .zero, size: size)
        return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    override func mouseDown(with event: NSEvent) { isOn.toggle(); onChange(isOn) }
}

/// A compact color swatch + hex field (mock `.color-ctrl`).
private final class ColorControl: NSView {
    private let well = NSColorWell()
    private let hexField = NSTextField()
    private let onChange: (String) -> Void

    init(hexString: String, onChange: @escaping (String) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        well.translatesAutoresizingMaskIntoConstraints = false
        well.color = Theme.hex(hexString)
        well.colorWellStyle = .minimal
        well.target = self
        well.action = #selector(wellChanged)

        hexField.translatesAutoresizingMaskIntoConstraints = false
        hexField.stringValue = hexString
        hexField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        hexField.textColor = Theme.text
        hexField.drawsBackground = true
        hexField.backgroundColor = Theme.hex("#0d0d10")
        hexField.isBordered = true
        hexField.bezelStyle = .roundedBezel
        hexField.focusRingType = .none
        hexField.target = self
        hexField.action = #selector(hexChanged)

        addSubview(well); addSubview(hexField)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            well.leadingAnchor.constraint(equalTo: leadingAnchor),
            well.centerYAnchor.constraint(equalTo: centerYAnchor),
            well.widthAnchor.constraint(equalToConstant: 40),
            well.heightAnchor.constraint(equalToConstant: 26),
            hexField.leadingAnchor.constraint(equalTo: well.trailingAnchor, constant: 8),
            hexField.trailingAnchor.constraint(equalTo: trailingAnchor),
            hexField.centerYAnchor.constraint(equalTo: centerYAnchor),
            hexField.widthAnchor.constraint(equalToConstant: 80),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func wellChanged() {
        let hex = Self.hexString(from: well.color)
        hexField.stringValue = hex
        onChange(hex)
    }

    @objc private func hexChanged() {
        let v = hexField.stringValue
        well.color = Theme.hex(v)
        onChange(v)
    }

    private static func hexString(from color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

/// A row that lights up its background on hover (mock `.setting-agent:hover`).
private final class HoverRow: NSView {
    var hoverColor: NSColor = .clear
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(a); tracking = a
    }
    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = hoverColor.cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = NSColor.clear.cgColor }
}

/// A top-anchored flipped container so scroll content grows downward.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
