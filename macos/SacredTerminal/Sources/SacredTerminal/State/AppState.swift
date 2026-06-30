import Foundation

extension Notification.Name {
    /// Posted whenever the workspace tree or settings change; views observe this.
    static let sacredStateChanged = Notification.Name("sacredStateChanged")
    /// Posted to ask the main window to focus a specific session (menu-bar snap-back).
    static let sacredFocusSession = Notification.Name("sacredFocusSession")
}

struct AgentSettings: Codable {
    var openWithYolo: Bool = true
}

struct AppearanceSettings: Codable {
    var ghosttyTheme: String = "catppuccin-frappe"   // imported from ~/.config/ghostty/config
    var railWidth: RailWidth = .standard
    // Side-rail colors (app chrome only — the mock's Appearance pickers).
    var railBg: String = "#0a0a0c"
    var railFg: String = "#e6e6ea"
    var sessionHighlight: String = "#fab387"
    enum RailWidth: String, Codable { case compact, standard, wide
        var points: CGFloat { switch self { case .compact: return 220; case .standard: return 252; case .wide: return 288 } }
    }

    init() {}
    // Tolerant decode: fields added later default in instead of failing the load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ghosttyTheme = try c.decodeIfPresent(String.self, forKey: .ghosttyTheme) ?? "catppuccin-frappe"
        railWidth = try c.decodeIfPresent(RailWidth.self, forKey: .railWidth) ?? .standard
        railBg = try c.decodeIfPresent(String.self, forKey: .railBg) ?? "#0a0a0c"
        railFg = try c.decodeIfPresent(String.self, forKey: .railFg) ?? "#e6e6ea"
        sessionHighlight = try c.decodeIfPresent(String.self, forKey: .sessionHighlight) ?? "#fab387"
    }
}

struct GitSettings: Codable {
    var branchPrefix: String = "git"       // git | custom | none
    var customPrefix: String = ""
    var autoRenameBranch: Bool = true
    var commitAttribution: Bool = false
    var keepMainUpdated: Bool = false
    var draftByDefault: Bool = false
    // Source-control extras (the mock's Git tab).
    var scGroupOrder: String = "changes"   // changes | staged | untracked
    var showScAiActions: Bool = true
    var customCommand: String = ""
    var usePrTemplate: Bool = true
    var generatePrOnOpen: Bool = false
    var openPrAfterCreate: Bool = false

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        branchPrefix = try c.decodeIfPresent(String.self, forKey: .branchPrefix) ?? "git"
        customPrefix = try c.decodeIfPresent(String.self, forKey: .customPrefix) ?? ""
        autoRenameBranch = try c.decodeIfPresent(Bool.self, forKey: .autoRenameBranch) ?? true
        commitAttribution = try c.decodeIfPresent(Bool.self, forKey: .commitAttribution) ?? false
        keepMainUpdated = try c.decodeIfPresent(Bool.self, forKey: .keepMainUpdated) ?? false
        draftByDefault = try c.decodeIfPresent(Bool.self, forKey: .draftByDefault) ?? false
        scGroupOrder = try c.decodeIfPresent(String.self, forKey: .scGroupOrder) ?? "changes"
        showScAiActions = try c.decodeIfPresent(Bool.self, forKey: .showScAiActions) ?? true
        customCommand = try c.decodeIfPresent(String.self, forKey: .customCommand) ?? ""
        usePrTemplate = try c.decodeIfPresent(Bool.self, forKey: .usePrTemplate) ?? true
        generatePrOnOpen = try c.decodeIfPresent(Bool.self, forKey: .generatePrOnOpen) ?? false
        openPrAfterCreate = try c.decodeIfPresent(Bool.self, forKey: .openPrAfterCreate) ?? false
    }
}

/// The single source of truth for the workspace tree + settings.
/// AppKit views observe `.sacredStateChanged` and re-read this.
final class AppState {
    static let shared = AppState()

    private(set) var projects: [Project] = []
    private(set) var activeSessionID: String?
    var sidebarOpen: Bool = true { didSet { persist() } }

    var agentEnabled: Set<AgentKey> = Set(AgentKey.allCases)
    var pinnedAgents: [AgentKey] = Agents.defaultPinned
    var agentSettings = AgentSettings()
    var appearance = AppearanceSettings()
    var git = GitSettings()

    private init() {
        if let snapshot = Persistence.load() {
            apply(snapshot)
        } else {
            projects = AppState.seed()
            activeSessionID = projects.first?.sessions.first?.id
        }
    }

    // MARK: - Lookups

    func session(_ id: String?) -> (project: Project, session: Session)? {
        guard let id else { return nil }
        for project in projects {
            if let s = project.sessions.first(where: { $0.id == id }) { return (project, s) }
        }
        return nil
    }

    var activeContext: (project: Project, session: Session)? { session(activeSessionID) }

    var allSessions: [(project: Project, session: Session)] {
        projects.flatMap { p in p.sessions.map { (p, $0) } }
    }

    // MARK: - Mutations (each ends with changed())

    func setActive(_ id: String) { activeSessionID = id; changed() }
    func toggleSidebar() { sidebarOpen.toggle(); changed() }

    func toggleCollapse(_ projectID: String) {
        projects.first(where: { $0.id == projectID })?.collapsed.toggle(); changed()
    }

    func addProject(name: String, path: String) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        let p = Project(name: clean.isEmpty ? (path as NSString).lastPathComponent : clean,
                        path: path.trimmingCharacters(in: .whitespaces))
        projects.append(p); changed()
    }

    @discardableResult
    func createSession(projectID: String, agent: AgentKey, worktree: Bool) -> Session? {
        guard let p = projects.first(where: { $0.id == projectID }) else { return nil }
        let yolo = agentSettings.openWithYolo && Agents.def(agent).yoloFlag != nil
        let s = Session(agent: agent,
                        task: agent == .shell ? "zsh" : "New \(Agents.def(agent).name) session",
                        status: agent == .shell ? .idle : .working,
                        worktree: worktree, yolo: yolo)
        p.sessions.append(s)
        p.collapsed = false
        activeSessionID = s.id
        changed()
        return s
    }

    func closeSession(_ id: String) {
        for p in projects { p.sessions.removeAll { $0.id == id } }
        if activeSessionID == id { activeSessionID = allSessions.first?.session.id }
        changed()
    }

    func setStatus(_ id: String, _ status: Status) {
        session(id)?.session.status = status; changed()
    }

    func send(to id: String, message: String) {
        guard let s = session(id)?.session else { return }
        s.status = .working
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty { s.task = m }
        changed()
    }

    // panes / splits

    func addPane(_ sessionID: String, kind: Pane.Kind = .shell) {
        guard let s = session(sessionID)?.session else { return }
        let pane = Pane(title: kind == .shell ? "shell" : Agents.def(s.agent).name, kind: kind)
        s.panes.append(pane)
        s.activePaneID = pane.id
        s.splitLayout = .none
        changed()
    }

    func split(_ sessionID: String, _ direction: SplitLayout) {
        guard let s = session(sessionID)?.session else { return }
        let added = s.panes.count < 2
        if added { s.panes.append(Pane(title: "shell", kind: .shell)) }
        s.splitLayout = direction
        if added { s.activePaneID = s.panes[1].id }
        changed()
    }

    func closePane(_ sessionID: String, _ paneID: String) {
        guard let s = session(sessionID)?.session, s.panes.count > 1 else { return }
        s.panes.removeAll { $0.id == paneID }
        if s.activePaneID == paneID { s.activePaneID = s.panes[0].id }
        if s.panes.count < 2 { s.splitLayout = .none }
        changed()
    }

    func setActivePane(_ sessionID: String, _ paneID: String) {
        session(sessionID)?.session.activePaneID = paneID; changed()
    }

    // browser

    func toggleBrowser(_ sessionID: String?, force: Bool? = nil) {
        guard let s = session(sessionID ?? activeSessionID)?.session else { return }
        s.browserOpen = force ?? !s.browserOpen; changed()
    }

    func setBrowserURL(_ sessionID: String, _ url: String) {
        session(sessionID)?.session.browserURL = url; changed()
    }

    // settings

    func setAgentEnabled(_ key: AgentKey, _ enabled: Bool) {
        if !enabled && agentEnabled.count <= 1 { return }
        if enabled { agentEnabled.insert(key) } else { agentEnabled.remove(key); pinnedAgents.removeAll { $0 == key } }
        changed()
    }

    func togglePin(_ key: AgentKey) {
        guard agentEnabled.contains(key) else { return }
        if let i = pinnedAgents.firstIndex(of: key) { pinnedAgents.remove(at: i) }
        else if pinnedAgents.count < Agents.maxPinned { pinnedAgents.append(key) }
        changed()
    }

    var railAgents: [AgentKey] { pinnedAgents.filter { agentEnabled.contains($0) } }

    func changed() {
        persist()
        NotificationCenter.default.post(name: .sacredStateChanged, object: nil)
    }

    private func persist() { Persistence.save(snapshot()) }

    // MARK: - Snapshot

    func snapshot() -> AppSessionSnapshot {
        AppSessionSnapshot(projects: projects, activeSessionID: activeSessionID, sidebarOpen: sidebarOpen,
                           agentEnabled: Array(agentEnabled), pinnedAgents: pinnedAgents,
                           agentSettings: agentSettings, appearance: appearance, git: git)
    }

    private func apply(_ s: AppSessionSnapshot) {
        projects = s.projects
        activeSessionID = s.activeSessionID ?? s.projects.first?.sessions.first?.id
        sidebarOpen = s.sidebarOpen
        agentEnabled = Set(s.agentEnabled.isEmpty ? AgentKey.allCases : s.agentEnabled)
        pinnedAgents = s.pinnedAgents.isEmpty ? Agents.defaultPinned : s.pinnedAgents
        agentSettings = s.agentSettings
        appearance = s.appearance
        git = s.git
        IDGen.bump(past: projects.flatMap { p in p.sessions.flatMap { [$0.id] + $0.panes.map(\.id) } })
    }

    // MARK: - Seed (real directories so surfaces open real shells)

    private static func seed() -> [Project] {
        let home = NSHomeDirectory()
        let p0 = Project(name: "the-sacred-terminal", path: "\(home)/Developer/the-sacred-terminal", sessions: [
            Session(agent: .claude, task: "Implement the spec on top of Ghostty", status: .working),
            Session(agent: .shell, task: "zsh", status: .idle),
        ])
        let p1 = Project(name: "acme-storefront", path: "\(home)/Developer/acme-storefront", sessions: [
            Session(agent: .codex, task: "Migrate test suite to vitest", status: .waiting),
            Session(agent: .gemini, task: "Refactor checkout to server components", status: .done,
                    browserOpen: true, browserURL: "http://localhost:5173"),
        ])
        let p2 = Project(name: "design-system", path: "\(home)/Developer/design-system", sessions: [
            Session(agent: .cursor, task: "Add dark-mode tokens to Button", status: .idle),
        ])
        let p3 = Project(name: "home", path: home, collapsed: true, sessions: [
            Session(agent: .shell, task: "zsh", status: .idle),
        ])
        return [p0, p1, p2, p3]
    }
}
