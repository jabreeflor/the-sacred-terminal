import Foundation

/// Full workspace + settings snapshot, persisted so layout and sessions restore
/// across restarts — cmux's `AppSessionSnapshot` model (spec §10, §11).
struct AppSessionSnapshot: Codable {
    var projects: [Project]
    var activeSessionID: String?
    var sidebarOpen: Bool
    var agentEnabled: [AgentKey]
    var pinnedAgents: [AgentKey]
    var agentSettings: AgentSettings
    var appearance: AppearanceSettings
    var git: GitSettings
}

enum Persistence {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SacredTerminal", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("session.json")
    }

    static func load() -> AppSessionSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(AppSessionSnapshot.self, from: data)
    }

    static func save(_ snapshot: AppSessionSnapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
