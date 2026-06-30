import Foundation

/// A tab inside a session — the session's agent or a shell (spec §4).
final class Pane: Codable, Identifiable {
    let id: String
    var title: String
    var kind: Kind
    /// Whether this pane already created its Ghostty surface (so we don't respawn).
    var started: Bool

    enum Kind: String, Codable { case agent, shell }

    init(id: String = ID.next(), title: String, kind: Kind, started: Bool = false) {
        self.id = id
        self.title = title
        self.kind = kind
        self.started = started
    }
}

enum SplitLayout: String, Codable { case none, horizontal, vertical }

/// A terminal bound to one agent, with a status and a short task line (spec §4).
final class Session: Codable, Identifiable {
    let id: String
    var agent: AgentKey
    var task: String
    var status: Status
    var worktree: Bool
    var yolo: Bool
    var browserOpen: Bool
    var browserURL: String
    var panes: [Pane]
    var activePaneID: String
    var splitLayout: SplitLayout

    init(id: String = ID.next(),
         agent: AgentKey,
         task: String,
         status: Status,
         worktree: Bool = false,
         yolo: Bool = false,
         browserOpen: Bool = false,
         browserURL: String = "http://localhost:3000") {
        self.id = id
        self.agent = agent
        self.task = task
        self.status = status
        self.worktree = worktree
        self.yolo = yolo
        self.browserOpen = browserOpen
        self.browserURL = browserURL
        let pane = Pane(title: Agents.def(agent).name, kind: agent == .shell ? .shell : .agent)
        self.panes = [pane]
        self.activePaneID = pane.id
        self.splitLayout = .none
    }

    var activePane: Pane { panes.first(where: { $0.id == activePaneID }) ?? panes[0] }
}

/// A folder on disk holding zero or more sessions (spec §4).
final class Project: Codable, Identifiable {
    let id: String
    var name: String
    /// Absolute path — the real cwd handed to each session's Ghostty surface.
    var path: String
    var collapsed: Bool
    var sessions: [Session]

    init(id: String = ID.next(), name: String, path: String, collapsed: Bool = false, sessions: [Session] = []) {
        self.id = id
        self.name = name
        self.path = path
        self.collapsed = collapsed
        self.sessions = sessions
    }
}

/// Monotonic id generator (kept ahead of any restored ids).
enum ID {
    private static var counter: Int = 1
    static func next() -> String { defer { counter += 1 }; return "s\(counter)" }
    static func bump(past ids: [String]) {
        let maxN = ids.compactMap { Int($0.drop(while: { !$0.isNumber })) }.max() ?? 0
        if maxN + 1 > counter { counter = maxN + 1 }
    }
}
